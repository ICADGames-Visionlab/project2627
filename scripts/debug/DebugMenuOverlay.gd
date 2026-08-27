# DebugMenuOverlay.gd — Painel "mod menu" que lê o registro do DebugMenu e monta a UI em runtime.
# A cena é casca: nenhum botão existe nela, todos nascem aqui a partir do que foi registrado. É o
# que permite "adicionar uma seção" sem abrir o editor.
#
# Os textos deste painel são intencionalmente hardcoded: a exigência de tr() do Guideline vale
# para texto exibido ao jogador, e este menu não existe em build de release.
extends CanvasLayer

# Largura fixa do painel. Default cabe em 720p (ver docs/debug_menu.md).
@export var panel_width: float = 520.0
# Altura máxima da coluna de ações antes de rolar — evita a UI de debug estourar telas pequenas.
@export var max_panel_height: float = 320.0
# Intervalo do cabeçalho (FPS + cena). Propositalmente baixo em frequência: a UI de debug não pode
# distorcer a métrica de tempo por frame que ela própria existe para mostrar.
@export var refresh_interval_seconds: float = 0.25

var _selected_section: StringName = &""
var _elapsed: float = 0.0

@onready var _panel: PanelContainer = $Panel
@onready var _header: Label = $Panel/Margin/Layout/Header
@onready var _sections_list: VBoxContainer = $Panel/Margin/Layout/Body/Sections
@onready var _actions_scroll: ScrollContainer = $Panel/Margin/Layout/Body/ActionsScroll
@onready var _actions_list: VBoxContainer = $Panel/Margin/Layout/Body/ActionsScroll/Actions


func _ready() -> void:
	# Sem isto, o painel congela junto com o jogo assim que "Pausar jogo" é ligado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.custom_minimum_size.x = panel_width
	_actions_scroll.custom_minimum_size.y = max_panel_height
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


# Monta a coluna esquerda: um botão por seção, marcando a selecionada.
func _rebuild_sections_column(sections: Dictionary) -> void:
	for child: Node in _sections_list.get_children():
		child.queue_free()
	for section: StringName in sections.keys():
		var button: Button = Button.new()
		button.text = ("> " if section == _selected_section else "   ") + String(section)
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_section_pressed.bind(section))
		_sections_list.add_child(button)


# Monta a coluna direita: um botão por action, um CheckButton por toggle, na seção selecionada.
func _rebuild_actions_column(sections: Dictionary) -> void:
	for child: Node in _actions_list.get_children():
		child.queue_free()
	if not sections.has(_selected_section):
		return
	for entry: DebugMenu.DebugEntry in sections[_selected_section]:
		if entry.is_toggle:
			var check: CheckButton = CheckButton.new()
			check.text = entry.label
			check.button_pressed = entry.toggle_state
			check.toggled.connect(_on_entry_toggled.bind(entry))
			_actions_list.add_child(check)
		else:
			var button: Button = Button.new()
			button.text = entry.label
			button.pressed.connect(_on_entry_pressed.bind(entry))
			_actions_list.add_child(button)


# Troca a seção selecionada e remonta a tela.
func _on_section_pressed(section: StringName) -> void:
	_selected_section = section
	refresh()


# Executa uma action e loga. Sem try/catch (GDScript não tem): um erro dentro do Callable segue
# aparecendo como erro na engine, e este log só diz qual botão foi apertado antes.
func _on_entry_pressed(entry: DebugMenu.DebugEntry) -> void:
	entry.callable.call()
	print("[DebugMenu] - Ação \"%s\" executada (seção %s)" % [entry.label, entry.section])


# Aplica o novo estado do toggle, avisa o dono e loga.
func _on_entry_toggled(new_value: bool, entry: DebugMenu.DebugEntry) -> void:
	entry.toggle_state = new_value
	entry.callable.call(new_value)
	print("[DebugMenu] - Ação \"%s\" executada (seção %s)" % [entry.label, entry.section])


# Atualiza FPS e cena atual no cabeçalho.
func _update_header() -> void:
	var scene_name: String = "-"
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var scene_path: String = current_scene.scene_file_path
		scene_name = scene_path.get_file() if not scene_path.is_empty() else current_scene.name
	_header.text = "DEBUG MENU        %d fps · %s" % [Engine.get_frames_per_second(), scene_name]
