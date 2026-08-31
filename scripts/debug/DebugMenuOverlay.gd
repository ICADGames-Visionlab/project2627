# DebugMenuOverlay.gd — Painel "mod menu" que lê o registro do DebugMenu e monta a UI em runtime.
# A cena é casca: nenhum botão existe nela, todos nascem aqui a partir do que foi registrado. É o
# que permite "adicionar uma seção" sem abrir o editor.
#
# Os textos deste painel são intencionalmente hardcoded: a exigência de tr() do Guideline vale
# para texto exibido ao jogador, e este menu não existe em build de release.
extends CanvasLayer

# Largura fixa do painel. Default cabe em 720p (ver docs/debug_menu.md).
@export var panel_width: float = 520.0
# Altura máxima de cada coluna antes de rolar — evita a UI de debug estourar telas pequenas.
# Aplicada nas duas colunas (seções e ações), para a altura do painel não depender de qual delas
# está mais cheia.
@export var max_panel_height: float = 320.0
# Intervalo do cabeçalho (FPS + cena). Propositalmente baixo em frequência: a UI de debug não pode
# distorcer a métrica de tempo por frame que ela própria existe para mostrar.
@export var refresh_interval_seconds: float = 0.25
# Se o campo de filtro puxa o teclado ao abrir o menu. Default false: metade do debug é olhar o
# jogo se mexendo, e um menu que come o WASD ao abrir quebra isso. Quem quer digitar clica no campo.
@export var focus_search_on_open: bool = false

var _selected_section: StringName = &""
var _elapsed: float = 0.0

var _filter_active: bool = false
var _filter_shown_count: int = 0
var _filter_total_count: int = 0

var _confirm_dialog: ConfirmationDialog
var _pending_entry: DebugMenu.DebugEntry
var _pending_confirm_callback: Callable

@onready var _panel: PanelContainer = $Panel
@onready var _header: Label = $Panel/Margin/Layout/Header
@onready var _filter: LineEdit = $Panel/Margin/Layout/Filter
@onready var _sections_scroll: ScrollContainer = $Panel/Margin/Layout/Body/SectionsScroll
@onready var _sections_list: VBoxContainer = $Panel/Margin/Layout/Body/SectionsScroll/Sections
@onready var _actions_scroll: ScrollContainer = $Panel/Margin/Layout/Body/ActionsScroll
@onready var _actions_list: VBoxContainer = $Panel/Margin/Layout/Body/ActionsScroll/Actions


func _ready() -> void:
	# Sem isto, o painel congela junto com o jogo assim que "Pausar jogo" é ligado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Entra no grupo dos overlays de debug para a captura de tela (F6) poder escondê-lo sem
	# conhecer esta cena (ver DebugScreenCapture).
	add_to_group(DebugMenu.OVERLAY_GROUP)
	_panel.custom_minimum_size.x = panel_width
	_actions_scroll.custom_minimum_size.y = max_panel_height
	_sections_scroll.custom_minimum_size.y = max_panel_height
	_filter.text_changed.connect(_on_filter_text_changed)
	_filter.gui_input.connect(_on_filter_gui_input)

	# Diálogo único, reusado por toda entrada destrutiva: conectar por clique com .bind(entry)
	# acumularia conexões (ver docs/debug_menu.md, "Ação destrutiva").
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_dialog.exclusive = true
	_confirm_dialog.dialog_autowrap = true
	_confirm_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirm_dialog.canceled.connect(_on_confirmation_canceled)
	add_child(_confirm_dialog)

	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < refresh_interval_seconds:
		return
	_elapsed = 0.0
	_update_header()


# Reconstrói as duas colunas a partir do registro atual do DebugMenu. Chamado pelo DebugMenu toda
# vez que o menu abre, para pegar ações registradas (ou removidas) enquanto ele estava fechado.
func refresh() -> void:
	var sections: Dictionary = DebugMenu.get_sections()
	if not sections.has(_selected_section):
		_selected_section = sections.keys()[0] if not sections.is_empty() else &""
	_rebuild_sections_column(sections)
	_rebuild_actions_column(sections)
	_update_header()
	if focus_search_on_open:
		_filter.grab_focus.call_deferred()


# Monta a coluna esquerda: um botão por seção, marcando a selecionada, e rola até ela ficar
# visível (útil com muitas seções registradas).
func _rebuild_sections_column(sections: Dictionary) -> void:
	for child: Node in _sections_list.get_children():
		child.queue_free()
	var selected_button: Button
	for section: StringName in sections.keys():
		var button: Button = Button.new()
		button.text = ("> " if section == _selected_section else "   ") + String(section)
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_section_pressed.bind(section))
		_sections_list.add_child(button)
		if section == _selected_section:
			selected_button = button
	# Adiado de propósito: ensure_control_visible() precisa do tamanho já calculado do botão, que
	# só existe depois do passo de layout do frame.
	if selected_button != null:
		_sections_scroll.ensure_control_visible.call_deferred(selected_button)


# Monta a coluna direita. Sem filtro: as entradas da seção selecionada, por kind. Com filtro: os
# resultados de TODAS as seções, prefixados pela seção de origem — é o modelo de command palette,
# porque o problema real é "não lembro em que seção está X" (ver docs/debug_menu.md).
func _rebuild_actions_column(sections: Dictionary) -> void:
	for child: Node in _actions_list.get_children():
		child.queue_free()

	var filter_text: String = _filter.text.strip_edges()
	_filter_active = not filter_text.is_empty()

	if not _filter_active:
		_sections_list.modulate = Color(1, 1, 1, 1)
		if not sections.has(_selected_section):
			return
		for entry: DebugMenu.DebugEntry in sections[_selected_section]:
			_add_entry_widget(entry, false)
		return

	_sections_list.modulate = Color(1, 1, 1, 0.4)
	var matches: Array = _filter_all_entries(sections, filter_text)
	_filter_shown_count = matches.size()
	_filter_total_count = _count_total_entries(sections)
	if matches.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Nenhuma ação corresponde a \"%s\"" % filter_text
		_actions_list.add_child(empty_label)
		return
	for entry: DebugMenu.DebugEntry in matches:
		_add_entry_widget(entry, true)


# Casa o filtro contra TODAS as entradas de TODAS as seções (search_key já normalizado no
# registro), ranqueado por DebugTextFilter.score() e desempatado por ordem de registro.
func _filter_all_entries(sections: Dictionary, filter_text: String) -> Array:
	var needle: String = DebugTextFilter.normalize(filter_text)
	var scored: Array = []
	for section: StringName in sections.keys():
		for entry: DebugMenu.DebugEntry in sections[section]:
			var entry_score: int = DebugTextFilter.score(entry.search_key, needle)
			if entry_score < 0:
				continue
			scored.append({"entry": entry, "score": entry_score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["entry"].order < b["entry"].order)
	var result: Array = []
	for item: Dictionary in scored:
		result.append(item["entry"])
	return result


func _count_total_entries(sections: Dictionary) -> int:
	var total: int = 0
	for entries: Array in sections.values():
		total += entries.size()
	return total


# Cria o Control certo para uma entrada, de acordo com o kind. show_section_prefix é ligado só
# durante o filtro global, para o resultado dizer de onde a ação veio.
func _add_entry_widget(entry: DebugMenu.DebugEntry, show_section_prefix: bool) -> void:
	var label_text: String = "%s · %s" % [entry.section, entry.label] if show_section_prefix else entry.label
	if entry.requires_confirmation:
		label_text = "⚠ " + label_text

	match entry.kind:
		DebugMenu.EntryKind.ACTION:
			var button: Button = Button.new()
			button.text = label_text
			button.pressed.connect(_on_entry_pressed.bind(entry))
			_actions_list.add_child(button)
		DebugMenu.EntryKind.TOGGLE:
			var check: CheckButton = CheckButton.new()
			check.text = label_text
			check.button_pressed = entry.toggle_state
			check.toggled.connect(_on_entry_toggled.bind(entry))
			_actions_list.add_child(check)
		DebugMenu.EntryKind.VALUE:
			_actions_list.add_child(_build_value_row(entry, label_text))
		DebugMenu.EntryKind.INPUT:
			_actions_list.add_child(_build_input_block(entry, label_text))


# VALUE: rótulo + o Control do único DebugParam. Se houver getter, o overlay exibe o valor de
# verdade do sistema (e sincroniza o DebugParam com ele) em vez da cópia guardada.
func _build_value_row(entry: DebugMenu.DebugEntry, label_text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	row.add_child(label)

	var param: DebugParam = entry.params[0]
	if entry.getter.is_valid():
		param.value = entry.getter.call()

	row.add_child(_build_param_control(param, func(new_value: Variant) -> void:
		param.value = new_value
		entry.callable.call(new_value)
	))
	return row


# INPUT: um Control por parâmetro + o botão que dispara callv(). Até 2 parâmetros cabem numa
# linha só; com 3 ou mais, os campos vão para um HFlowContainer (com wrap) e o botão desce para
# uma linha própria — regra de layout de docs/debug_menu.md para não estourar o painel de 520px.
func _build_input_block(entry: DebugMenu.DebugEntry, label_text: String) -> Control:
	var button: Button = Button.new()
	button.text = label_text
	button.pressed.connect(_on_input_pressed.bind(entry))

	var field_rows: Array[Control] = []
	for param: DebugParam in entry.params:
		field_rows.append(_build_field_row(param))

	if entry.params.size() <= 2:
		var row: HBoxContainer = HBoxContainer.new()
		for field: Control in field_rows:
			row.add_child(field)
		row.add_child(button)
		return row

	var container: VBoxContainer = VBoxContainer.new()
	var flow: HFlowContainer = HFlowContainer.new()
	for field: Control in field_rows:
		flow.add_child(field)
	container.add_child(flow)
	container.add_child(button)
	return container


# Um parâmetro de INPUT: rótulo (quando o nome não é vazio) + widget. A escrita no DebugParam
# acontece no sinal do widget, e não no clique do botão: fechar o menu sem clicar preserva o que
# foi digitado.
func _build_field_row(param: DebugParam) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	if not param.name.is_empty():
		var label: Label = Label.new()
		label.text = param.name
		row.add_child(label)
	row.add_child(_build_param_control(param, func(new_value: Variant) -> void:
		param.value = new_value
	))
	return row


# Constrói o Control certo por DebugParam.Type e conecta o sinal correspondente a on_change.
func _build_param_control(param: DebugParam, on_change: Callable) -> Control:
	match param.type:
		DebugParam.Type.INT, DebugParam.Type.FLOAT:
			return _build_number_control(param, on_change)
		DebugParam.Type.STRING:
			var line_edit: LineEdit = LineEdit.new()
			line_edit.text = str(param.value)
			line_edit.custom_minimum_size.x = 140
			line_edit.select_all_on_focus = true
			line_edit.text_changed.connect(func(new_text: String) -> void:
				on_change.call(new_text)
			)
			return line_edit
		DebugParam.Type.BOOL:
			var check_box: CheckBox = CheckBox.new()
			check_box.button_pressed = bool(param.value)
			check_box.toggled.connect(func(new_value: bool) -> void:
				on_change.call(new_value)
			)
			return check_box
		DebugParam.Type.ENUM:
			var option_button: OptionButton = OptionButton.new()
			for option_text: String in param.options:
				option_button.add_item(option_text)
			option_button.selected = int(param.value)
			option_button.item_selected.connect(func(index: int) -> void:
				on_change.call(index)
			)
			return option_button
	return Control.new()


# SpinBox (+ HSlider opcional, sincronizados) para INT/FLOAT. select_all_on_focus porque digitar
# por cima é o gesto esperado num campo de debug.
func _build_number_control(param: DebugParam, on_change: Callable) -> Control:
	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = param.min_value
	spin_box.max_value = param.max_value
	spin_box.step = param.step
	spin_box.value = float(param.value)
	spin_box.select_all_on_focus = true
	spin_box.custom_minimum_size.x = 90

	var apply_value: Callable = func(new_value: float) -> void:
		on_change.call(int(new_value) if param.type == DebugParam.Type.INT else new_value)

	if not param.use_slider:
		spin_box.value_changed.connect(apply_value)
		return spin_box

	var slider: HSlider = HSlider.new()
	slider.min_value = param.min_value
	slider.max_value = param.max_value
	slider.step = param.step
	slider.value = float(param.value)
	slider.custom_minimum_size.x = 100
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	spin_box.value_changed.connect(func(new_value: float) -> void:
		slider.set_value_no_signal(new_value)
		apply_value.call(new_value)
	)
	slider.value_changed.connect(func(new_value: float) -> void:
		spin_box.set_value_no_signal(new_value)
		apply_value.call(new_value)
	)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(spin_box)
	row.add_child(slider)
	return row


# Troca a seção selecionada e remonta a tela.
func _on_section_pressed(section: StringName) -> void:
	_selected_section = section
	refresh()


# Remonta só a coluna de ações. Esta é a armadilha central da busca: o campo de filtro mora fora
# da subárvore que refresh() destrói, e o handler dele NUNCA chama refresh() inteiro — só isso já
# evita que cada tecla digitada derrube o foco do próprio campo (ver docs/debug_menu.md).
func _on_filter_text_changed(_new_text: String) -> void:
	_rebuild_actions_column(DebugMenu.get_sections())
	_update_header()


# Esc com texto no filtro limpa o filtro; Esc com o campo vazio fecha o menu.
func _on_filter_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _filter.text.is_empty():
		DebugMenu.close_menu()
	else:
		_filter.text = ""
		_on_filter_text_changed("")
	_filter.accept_event()


# Executa uma ACTION, passando por confirmação primeiro se a entrada exigir.
func _on_entry_pressed(entry: DebugMenu.DebugEntry) -> void:
	if entry.requires_confirmation:
		_request_confirmation(entry, func() -> void: _run_action(entry))
		return
	_run_action(entry)


func _run_action(entry: DebugMenu.DebugEntry) -> void:
	entry.callable.call()
	print("[DebugMenu] - Ação \"%s\" executada (seção %s)" % [entry.label, entry.section])


# Aplica o novo estado do toggle, avisa o dono e loga. Toggle nunca pede confirmação (ver
# DebugMenu.register_toggle): é reversível por definição.
func _on_entry_toggled(new_value: bool, entry: DebugMenu.DebugEntry) -> void:
	entry.toggle_state = new_value
	entry.callable.call(new_value)
	print("[DebugMenu] - Ação \"%s\" executada (seção %s)" % [entry.label, entry.section])


# Executa um INPUT com os valores atuais dos campos, passando por confirmação primeiro se exigir.
func _on_input_pressed(entry: DebugMenu.DebugEntry) -> void:
	if entry.requires_confirmation:
		_request_confirmation(entry, func() -> void: _run_input(entry))
		return
	_run_input(entry)


func _run_input(entry: DebugMenu.DebugEntry) -> void:
	var values: Array = []
	for param: DebugParam in entry.params:
		values.append(param.value)
	entry.callable.callv(values)
	print("[DebugMenu] - Ação \"%s\" executada (seção %s)" % [entry.label, entry.section])


# Abre o diálogo único de confirmação, guardando a entrada e o Callable a rodar se confirmado.
func _request_confirmation(entry: DebugMenu.DebugEntry, on_confirmed: Callable) -> void:
	_pending_entry = entry
	_pending_confirm_callback = on_confirmed
	_confirm_dialog.dialog_text = entry.confirmation_text if not entry.confirmation_text.is_empty() else "Executar \"%s\"?" % entry.label
	_confirm_dialog.popup_centered()
	print("[DebugMenu] - Confirmação pedida para \"%s\"" % entry.label)


func _on_confirmation_confirmed() -> void:
	var callback: Callable = _pending_confirm_callback
	_pending_confirm_callback = Callable()
	_pending_entry = null
	if callback.is_valid():
		callback.call()


func _on_confirmation_canceled() -> void:
	print("[DebugMenu] - Ação \"%s\" cancelada" % _pending_entry.label)
	_pending_confirm_callback = Callable()
	_pending_entry = null


# Atualiza FPS, cena atual e, durante o filtro, a contagem "N de M ações".
func _update_header() -> void:
	var scene_name: String = "-"
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var scene_path: String = current_scene.scene_file_path
		scene_name = scene_path.get_file() if not scene_path.is_empty() else current_scene.name
	var text: String = "DEBUG MENU        %d fps · %s" % [Engine.get_frames_per_second(), scene_name]
	if _filter_active:
		text += "        %d de %d ações" % [_filter_shown_count, _filter_total_count]
	_header.text = text
