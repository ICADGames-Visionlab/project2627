# ControllerSupportSelfTest.gd — Autoteste do suporte a controle.
#
# O suporte a controle quebra em silêncio: alguém cria uma ação nova só com tecla, um menu novo sem
# MenuFocus, um aviso com a tecla escrita no texto, e nada fica vermelho — só o jogador de controle
# descobre, travado numa tela que não responde. Este autoteste é a trava que acusa isso antes do PR.
#
# O que ele confere (cada item é uma regra do checklist de docs/suporte_a_controle.md):
#   1. Toda ação do Input Map tem um botão ou analógico do controle (ou está nas exceções, com motivo).
#   2. Todo botão/analógico usado tem nome no CSV, nos dois idiomas, para o aviso escrever "A" e não
#      "JOY 0".
#   3. Todo {acao} citado no CSV existe no Input Map e tem tecla E botão; toda chave _JOYPAD tem a
#      chave normal.
#   4. Todo script que entra no grupo FocusTargets tem os métodos do contrato.
#   5. Toda cena com botão tem um MenuFocus (ou está nas exceções, com motivo).
#   6. Nenhum texto do CSV escreve a tecla à mão ("Aperte ESPAÇO") em vez de citar a ação ({sleep}).
#   7. Toda ação que o código lê (is_action_pressed(&"..."), const ..._ACTION) existe no Input Map.
#   8. A detecção de dispositivo, o aviso de troca e o MenuFocus funcionam (casos montados à mão).
#
# Duas portas de entrada: a ação "Autoteste do controle" no menu de debug (F4, seção "Controle") e o
# script de linha de comando tests/run_controller_support_self_test.gd, que sai com código de erro
# quando algo falha.
#
# Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao jogador — ver
# docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
class_name ControllerSupportSelfTest
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"

# Ações que não precisam de botão no controle, cada uma com o motivo. Ação nova entra aqui só com um
# motivo que convença no code review — o normal é ganhar um botão.
const EXEMPT_ACTIONS: Dictionary[StringName, String] = {
	&"move_click": "andar pelo clique é do mouse; no controle o analógico/D-pad anda (move_*)",
	&"ui_focus_next": "sem tecla nenhuma de propósito (o Tab é do insight_cycle, ver docs/insights.md); o D-pad navega o foco",
	&"ui_focus_prev": "idem ui_focus_next",
	&"dialogue_option_1": "atalho numérico; no controle a opção é escolhida com dialogue_focus_* + A",
	&"dialogue_option_2": "idem dialogue_option_1",
	&"dialogue_option_3": "idem dialogue_option_1",
	&"dialogue_option_4": "idem dialogue_option_1",
	&"dialogue_option_5": "idem dialogue_option_1",
	&"dialogue_option_6": "idem dialogue_option_1",
	&"dialogue_option_7": "idem dialogue_option_1",
	&"dialogue_option_8": "idem dialogue_option_1",
	&"dialogue_option_9": "idem dialogue_option_1",
}

# Prefixo das ações de ferramenta: ninguém debuga com o controle na mão, e elas não existem pro jogador.
const EXEMPT_ACTION_PREFIX: String = "debug_"

# Ações que só existem no controle, cada uma com o que o teclado/mouse faz no lugar. Um aviso que cite
# uma delas precisa ser mostrado só no controle (variante _JOYPAD, ou escondido fora dele).
const JOYPAD_ONLY_ACTIONS: Dictionary[StringName, String] = {
	&"dream_wake": "no mouse o botão \"Acordar\" é clicado; no teclado o ESC abre o menu de pausa",
	&"collect_words": "no mouse cada palavra sublinhada é clicada",
}

# Pastas de cena de ferramenta: o menu de debug e o console são usados de mouse e teclado.
const EXEMPT_SCENE_DIRS: Array[String] = ["res://scenes/debug_menu/"]

# Cenas com botão que cuidam do próprio foco no controle, sem MenuFocus, cada uma com o motivo.
const SELF_MANAGED_FOCUS_SCENES: Dictionary[String, String] = {
	"res://scenes/dialogue/DialogueScrollIndicator.tscn": "atalho do mouse; no controle o analógico direito (dialogue_jump_to_end) faz o mesmo",
	"res://scenes/ui/DiaryOverlay.tscn": "as setas do diário andam pelo D-pad (move_left/move_right) e o Y fecha; foco nos botões só atrapalharia",
	"res://scenes/profiling/DreamHud.tscn": "o B (dream_wake) abre a pergunta, que já nasce com foco no \"não\"",
	"res://scenes/profiling/ProfilingEmotionOption.tscn": "peça da ProfilingScreen, focada por ela",
	"res://scenes/profiling/GlossaryPanel.tscn": "peça da ProfilingScreen; refaz a lista e devolve o foco à evidência certa",
	"res://scenes/profiling/GlossaryMarkMenu.tscn": "abre com foco na lixeira e fecha no B (ui_cancel) sozinho",
}

# Tipos de nó que, numa cena, querem dizer "isto tem coisa pra apertar".
const FOCUSABLE_NODE_TYPES: Array[String] = [
	"Button", "CheckBox", "CheckButton", "OptionButton", "HSlider", "VSlider", "LineEdit", "SpinBox",
]

# Onde ficam as cenas e os scripts do jogo (addons ficam de fora: não são nossos).
const SCENES_DIR: String = "res://scenes"
const SCRIPTS_DIR: String = "res://scripts"
const TRANSLATIONS_CSV: String = "res://translations/translations.csv"
# Uma linha de código (não comentário) que põe o nó no grupo do foco.
const FOCUS_TARGETS_JOIN_PATTERN: String = "(?m)^\\s*add_to_group\\(FocusTargets\\.GROUP\\)"
# Chaves de texto que com certeza citam ações (avisos e variantes de controle): nelas um {marcador}
# desconhecido é erro de digitação. Nas outras, {day}/{name} são parâmetros de String.format().
const PROMPT_KEY_PREFIX: String = "PROMPT_"
# Chaves de nome de tecla/botão (INPUT_*): são elas que PODEM escrever a tecla.
const INPUT_NAME_KEY_PREFIX: String = "INPUT_"
# Verbo de instrução seguido de uma palavra toda em maiúsculas que não é {acao}: "Aperte ESPAÇO",
# "Press F", "Use J". É o jeito de um texto escrever a tecla à mão.
const HARDCODED_KEY_PATTERN: String = "\\b(?:[Pp]ress|[Aa]perte|[Ss]egure|[Hh]old|[Uu]se|[Cc]lique|[Cc]lick|[Tt]ecla|[Kk]ey)\\s+(?:o\\s+|a\\s+|the\\s+)?([A-ZÇÃÕÉ0-9][A-ZÇÃÕÉ0-9]{0,7})\\b"
# Leituras de ação no código: is_action_pressed(&"x"), Input.is_action_pressed("x"), get_vector("a", ...)
# não entra (é lido pela lista de ações de movimento, que o item 1 já cobre).
const ACTION_READ_PATTERN: String = "is_action(?:_just)?_(?:pressed|released)\\(\\s*&?\"([a-z0-9_]+)\""
# Constantes de nome de ação: const SLEEP_ACTION: StringName = &"sleep".
const ACTION_CONST_PATTERN: String = "(?m)^\\s*(?:const|@export var|var)\\s+\\w*_[Aa][Cc][Tt][Ii][Oo][Nn]\\s*:\\s*StringName\\s*=\\s*&\"([a-z0-9_]+)\""
const MENU_FOCUS_SCRIPT: String = "res://scripts/ui/MenuFocus.gd"
const PROJECT_FILE: String = "res://project.godot"
const INPUT_SECTION: String = "input"

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()


# Roda todos os casos e devolve o jogo ao estado em que estava. Pode ser chamado de novo: cada
# execução começa zerada.
func run() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()

	var device_snapshot: GameManager.InputDevice = GameManager.active_input_device

	_test_actions_have_joypad()
	_test_joypad_labels()
	_test_prompt_placeholders()
	_test_focus_targets_contract()
	_test_scenes_have_menu_focus()
	_test_no_hardcoded_keys()
	_test_code_actions_exist()
	_test_device_detection()
	_test_device_change_signal()
	_test_prompt_switches_device()
	_test_menu_focus()

	GameManager.set_active_input_device(device_snapshot)


# Relatório da última execução, pronto para print(): o resumo na primeira linha e um ✓/✗ por caso.
func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[Input] - Autoteste do controle: %d ok, %d falha(s)" % [passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# 1. Toda ação de jogo tem botão ou analógico do controle.
func _test_actions_have_joypad() -> void:
	var missing: PackedStringArray = PackedStringArray()
	for action: StringName in _project_actions():
		if _is_exempt_action(action):
			continue
		if not _has_joypad_event(action):
			missing.append(String(action))
	_record("Toda ação do Input Map tem botão no controle (ou exceção com motivo)", missing.is_empty(),
		"sem botão: %s — dê um botão em Projeto > Input Map ou ponha em EXEMPT_ACTIONS com o motivo" % ", ".join(missing))

	var stale: PackedStringArray = PackedStringArray()
	for action: StringName in EXEMPT_ACTIONS.keys() + JOYPAD_ONLY_ACTIONS.keys():
		if not InputMap.has_action(action):
			stale.append(String(action))
	_record("Toda exceção de ação ainda existe no Input Map", stale.is_empty(),
		"exceção de ação que não existe mais: %s" % ", ".join(stale))


# 2. Todo botão/analógico das ações tem nome traduzido nos dois idiomas.
func _test_joypad_labels() -> void:
	var translations: Array[Translation] = _project_translations()
	if translations.is_empty():
		_skip("Todo botão do controle tem nome no CSV", "nenhuma tradução carregada")
		return
	var missing: PackedStringArray = PackedStringArray()
	for action: StringName in _project_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			var key: String = _joypad_label_key(event)
			if key.is_empty():
				continue
			for translation: Translation in translations:
				if String(translation.get_message(key)).is_empty():
					var entry: String = "%s (%s)" % [key, translation.locale]
					if not missing.has(entry):
						missing.append(entry)
	_record("Todo botão do controle usado tem nome no CSV, nos dois idiomas", missing.is_empty(),
		"faltam no CSV: %s" % ", ".join(missing))


# 3. Os {acao} do CSV apontam pra ações que existem e têm tecla e botão; _JOYPAD tem chave normal.
func _test_prompt_placeholders() -> void:
	var rows: Dictionary[String, PackedStringArray] = _read_csv_rows()
	if rows.is_empty():
		_skip("Os {acao} do CSV são ações de verdade", "CSV não encontrado (%s)" % TRANSLATIONS_CSV)
		return
	var regex: RegEx = RegEx.create_from_string(InputGlyphs.PLACEHOLDER_PATTERN)
	var unknown: PackedStringArray = PackedStringArray()
	var without_joypad: PackedStringArray = PackedStringArray()
	var without_keyboard: PackedStringArray = PackedStringArray()
	var orphan_variants: PackedStringArray = PackedStringArray()
	for key: String in rows:
		if key.ends_with(InputGlyphs.JOYPAD_KEY_SUFFIX) and not rows.has(key.trim_suffix(InputGlyphs.JOYPAD_KEY_SUFFIX)):
			orphan_variants.append(key)
		var joypad_only_text: bool = key.ends_with(InputGlyphs.JOYPAD_KEY_SUFFIX)
		for text: String in rows[key]:
			var matches: Array[RegExMatch] = regex.search_all(text)
			var cites_actions: bool = key.begins_with(PROMPT_KEY_PREFIX) or joypad_only_text
			for match_result: RegExMatch in matches:
				cites_actions = cites_actions or InputMap.has_action(StringName(match_result.get_string(1)))
			if not cites_actions:
				continue
			for match_result: RegExMatch in matches:
				var action: StringName = StringName(match_result.get_string(1))
				var entry: String = "%s em %s" % [action, key]
				if not InputMap.has_action(action):
					_append_unique(unknown, entry)
					continue
				if InputGlyphs.find_event(action, GameManager.InputDevice.JOYPAD) == null:
					_append_unique(without_joypad, entry)
				if joypad_only_text or JOYPAD_ONLY_ACTIONS.has(action):
					continue
				if InputGlyphs.find_event(action, GameManager.InputDevice.KEYBOARD_MOUSE) == null:
					_append_unique(without_keyboard, entry)
	_record("Todo {acao} do CSV existe no Input Map", unknown.is_empty(),
		"ação inexistente: %s" % ", ".join(unknown))
	_record("Todo {acao} do CSV tem botão no controle", without_joypad.is_empty(),
		"o aviso sairia \"?\" no controle: %s" % ", ".join(without_joypad))
	_record("Todo {acao} do CSV tem tecla ou botão do mouse (fora as só de controle)", without_keyboard.is_empty(),
		"o aviso sairia \"?\" no teclado: %s — dê uma tecla, use uma chave _JOYPAD ou ponha em JOYPAD_ONLY_ACTIONS" % ", ".join(without_keyboard))
	_record("Toda chave _JOYPAD tem a chave normal", orphan_variants.is_empty(),
		"variante sem a chave normal: %s" % ", ".join(orphan_variants))


# 4. Quem entra no grupo do foco cumpre o contrato inteiro. Varre os scripts (e não uma cena), para
# pegar também o que ainda não foi posto em cena nenhuma.
func _test_focus_targets_contract() -> void:
	var join_regex: RegEx = RegEx.create_from_string(FOCUS_TARGETS_JOIN_PATTERN)
	var joiners: int = 0
	var broken: PackedStringArray = PackedStringArray()
	for path: String in _files_with_extension(SCRIPTS_DIR, ".gd"):
		var source: String = FileAccess.get_file_as_string(path)
		if join_regex.search(source) == null:
			continue
		joiners += 1
		var script: Script = load(path) as Script
		var methods: Array[StringName] = _script_methods(script)
		var missing: PackedStringArray = PackedStringArray()
		for method: StringName in FocusTargets.REQUIRED_METHODS:
			if not methods.has(method):
				missing.append(String(method))
		if not missing.is_empty():
			broken.append("%s (falta %s)" % [path.get_file(), ", ".join(missing)])
	_record("Todo script no grupo FocusTargets cumpre o contrato (%d script(s))" % joiners,
		joiners > 0 and broken.is_empty(),
		"nenhum script entra no grupo" if joiners == 0 else ", ".join(broken))


# 5. Cena com coisa pra apertar tem MenuFocus, ou cuida do foco sozinha (com motivo registrado).
func _test_scenes_have_menu_focus() -> void:
	var missing: PackedStringArray = PackedStringArray()
	for path: String in _files_with_extension(SCENES_DIR, ".tscn"):
		if SELF_MANAGED_FOCUS_SCENES.has(path) or _is_exempt_scene_dir(path):
			continue
		var source: String = FileAccess.get_file_as_string(path)
		if _has_focusable_node(source) and not source.contains(MENU_FOCUS_SCRIPT):
			missing.append(path)
	_record("Toda cena com botão tem MenuFocus (ou exceção com motivo)", missing.is_empty(),
		"sem MenuFocus: %s — adicione um nó MenuFocus ou ponha em SELF_MANAGED_FOCUS_SCENES" % ", ".join(missing))

	var stale: PackedStringArray = PackedStringArray()
	for path: String in SELF_MANAGED_FOCUS_SCENES:
		if not ResourceLoader.exists(path):
			stale.append(path)
	_record("Toda exceção de cena ainda existe", stale.is_empty(),
		"exceção de cena que não existe mais: %s" % ", ".join(stale))


# 6. Nenhum texto escreve a tecla à mão. A tecla escrita no texto não troca pro botão no controle (o
# aviso diria "Aperte ESPAÇO" pra quem está de controle) e não acompanha a troca de tecla no Input Map.
func _test_no_hardcoded_keys() -> void:
	var rows: Dictionary[String, PackedStringArray] = _read_csv_rows()
	if rows.is_empty():
		_skip("Nenhum texto do CSV escreve a tecla à mão", "CSV não encontrado (%s)" % TRANSLATIONS_CSV)
		return
	var regex: RegEx = RegEx.create_from_string(HARDCODED_KEY_PATTERN)
	var found: PackedStringArray = PackedStringArray()
	for key: String in rows:
		if key.begins_with(INPUT_NAME_KEY_PREFIX):
			continue
		for text: String in rows[key]:
			for match_result: RegExMatch in regex.search_all(text):
				_append_unique(found, "%s (\"%s\")" % [key, match_result.get_string(0)])
	_record("Nenhum texto do CSV escreve a tecla à mão", found.is_empty(),
		"tecla escrita no texto: %s — troque por {acao} e use InputGlyphs.tr_prompt()" % ", ".join(found))


# 7. Toda ação que o código lê existe. Ação renomeada no Input Map (ou digitada errada no código) não dá
# erro nenhum: is_action_pressed só passa a devolver false, e o botão "para de funcionar" sem aviso.
func _test_code_actions_exist() -> void:
	var read_regex: RegEx = RegEx.create_from_string(ACTION_READ_PATTERN)
	var const_regex: RegEx = RegEx.create_from_string(ACTION_CONST_PATTERN)
	var unknown: PackedStringArray = PackedStringArray()
	for path: String in _files_with_extension(SCRIPTS_DIR, ".gd"):
		var source: String = FileAccess.get_file_as_string(path)
		for regex: RegEx in [read_regex, const_regex]:
			for match_result: RegExMatch in regex.search_all(source):
				if _is_inside_comment(source, match_result.get_start()):
					continue
				var action: StringName = StringName(match_result.get_string(1))
				if not InputMap.has_action(action):
					_append_unique(unknown, "%s em %s" % [action, path.get_file()])
	_record("Toda ação lida no código existe no Input Map", unknown.is_empty(),
		"ação que não existe: %s — confira o nome em Projeto > Input Map" % ", ".join(unknown))


# 8a. Que evento diz qual dispositivo.
func _test_device_detection() -> void:
	var mouse_threshold: float = 3.0
	var axis_threshold: float = 0.5
	var joypad: int = GameManager.InputDevice.JOYPAD
	var keyboard: int = GameManager.InputDevice.KEYBOARD_MOUSE

	var button_down: InputEventJoypadButton = InputEventJoypadButton.new()
	button_down.button_index = JOY_BUTTON_A
	button_down.pressed = true
	_expect_device("Botão do controle apertado -> controle", button_down, joypad, mouse_threshold, axis_threshold)

	var button_up: InputEventJoypadButton = InputEventJoypadButton.new()
	button_up.button_index = JOY_BUTTON_A
	button_up.pressed = false
	_expect_device("Botão do controle solto não diz nada", button_up, -1, mouse_threshold, axis_threshold)

	var stick_rest: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_rest.axis = JOY_AXIS_LEFT_X
	stick_rest.axis_value = axis_threshold * 0.5
	_expect_device("Analógico na folga não diz nada", stick_rest, -1, mouse_threshold, axis_threshold)

	var stick_pushed: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_pushed.axis = JOY_AXIS_LEFT_X
	stick_pushed.axis_value = -1.0
	_expect_device("Analógico empurrado -> controle", stick_pushed, joypad, mouse_threshold, axis_threshold)

	var key_down: InputEventKey = InputEventKey.new()
	key_down.keycode = KEY_SPACE
	key_down.pressed = true
	_expect_device("Tecla apertada -> teclado/mouse", key_down, keyboard, mouse_threshold, axis_threshold)

	var key_echo: InputEventKey = InputEventKey.new()
	key_echo.keycode = KEY_SPACE
	key_echo.pressed = true
	key_echo.echo = true
	_expect_device("Tecla repetida (segurada) não diz nada", key_echo, -1, mouse_threshold, axis_threshold)

	var mouse_still: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse_still.relative = Vector2(mouse_threshold * 0.5, 0.0)
	_expect_device("Mouse tremendo parado não diz nada", mouse_still, -1, mouse_threshold, axis_threshold)

	var mouse_moved: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse_moved.relative = Vector2(mouse_threshold * 4.0, 0.0)
	_expect_device("Mouse andando -> teclado/mouse", mouse_moved, keyboard, mouse_threshold, axis_threshold)

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_expect_device("Clique -> teclado/mouse", click, keyboard, mouse_threshold, axis_threshold)


# 8b. O aviso de troca sai uma vez por troca, nunca a cada evento do mesmo dispositivo.
func _test_device_change_signal() -> void:
	GameManager.set_active_input_device(GameManager.InputDevice.KEYBOARD_MOUSE)
	var emitted: Array[int] = []
	var listener: Callable = func(device: int) -> void: emitted.append(device)
	EventBus.input_device_changed.connect(listener)
	GameManager.set_active_input_device(GameManager.InputDevice.JOYPAD)
	GameManager.set_active_input_device(GameManager.InputDevice.JOYPAD)
	GameManager.set_active_input_device(GameManager.InputDevice.KEYBOARD_MOUSE)
	EventBus.input_device_changed.disconnect(listener)
	_record("input_device_changed sai só na troca", emitted == [
		GameManager.InputDevice.JOYPAD, GameManager.InputDevice.KEYBOARD_MOUSE],
		"emitido %s" % str(emitted))


# 8c. O mesmo aviso escreve a tecla no teclado e o botão no controle.
func _test_prompt_switches_device() -> void:
	var keyboard_text: String = InputGlyphs.tr_prompt("PROMPT_SLEEP", GameManager.InputDevice.KEYBOARD_MOUSE)
	var joypad_text: String = InputGlyphs.tr_prompt("PROMPT_SLEEP", GameManager.InputDevice.JOYPAD)
	_record("O aviso não deixa {acao} sem trocar", not keyboard_text.contains("{") and not joypad_text.contains("{"),
		"teclado \"%s\", controle \"%s\"" % [keyboard_text, joypad_text])
	_record("O aviso muda com o dispositivo", keyboard_text != joypad_text,
		"igual nos dois: \"%s\"" % keyboard_text)

	var joypad_variant: String = InputGlyphs.tr_prompt("PROFILING_CONTINUE", GameManager.InputDevice.JOYPAD)
	var joypad_expected: String = InputGlyphs.format_actions(
		String(TranslationServer.translate("PROFILING_CONTINUE_JOYPAD")), GameManager.InputDevice.JOYPAD)
	_record("No controle, a variante _JOYPAD ganha da chave normal", joypad_variant == joypad_expected,
		"veio \"%s\", esperado \"%s\"" % [joypad_variant, joypad_expected])


# 8d. Um menu de mentira, montado em memória: foco ao pegar o controle, cancelar no B, botão
# desabilitado fora do caminho, foco escolhido em código e menu congelado pela pausa.
func _test_menu_focus() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_skip("MenuFocus foca o menu e aperta o cancelar", "sem SceneTree")
		return
	GameManager.set_active_input_device(GameManager.InputDevice.KEYBOARD_MOUSE)

	var menu: VBoxContainer = VBoxContainer.new()
	menu.name = "__SelfTestMenu"
	var first: Button = Button.new()
	first.text = "first"
	var back: Button = Button.new()
	back.text = "back"
	menu.add_child(first)
	menu.add_child(back)
	var menu_focus: MenuFocus = MenuFocus.new()
	menu_focus.menu_root = menu
	menu_focus.initial_focus = back
	menu_focus.cancel_button = back
	menu.add_child(menu_focus)
	tree.root.add_child(menu)

	_record("Com o mouse, o menu aberto não ganha foco sozinho", menu.get_viewport().gui_get_focus_owner() == null,
		"foco em \"%s\"" % str(menu.get_viewport().gui_get_focus_owner()))

	# O primeiro aperto do D-pad depois de pegar o controle: a troca adia o foco, então o aperto chega
	# ao MenuFocus sem nada focado e só põe o foco — sem andar pro segundo botão.
	GameManager.set_active_input_device(GameManager.InputDevice.JOYPAD)
	var first_press: InputEventAction = InputEventAction.new()
	first_press.action = &"ui_down"
	first_press.pressed = true
	menu_focus._unhandled_input(first_press)
	var focus_owner: Control = menu.get_viewport().gui_get_focus_owner()
	_record("O primeiro aperto no controle põe o foco no Initial Focus", focus_owner == back,
		"foco em \"%s\"" % (str(focus_owner.name) if focus_owner != null else "nada"))

	var cancel_presses: Array[int] = [0]
	back.pressed.connect(func() -> void: cancel_presses[0] += 1)
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	menu_focus._unhandled_input(cancel)
	_record("ui_cancel com o menu aberto aperta o Cancel Button", cancel_presses[0] == 1,
		"apertado %d vez(es)" % cancel_presses[0])

	MenuFocus.apply_joypad_focus_mode(first)
	var joypad_mode: Control.FocusMode = first.focus_mode
	GameManager.set_active_input_device(GameManager.InputDevice.KEYBOARD_MOUSE)
	MenuFocus.apply_joypad_focus_mode(first)
	_record("apply_joypad_focus_mode só deixa focar no controle",
		joypad_mode == Control.FOCUS_ALL and first.focus_mode == Control.FOCUS_NONE,
		"controle %d, mouse %d" % [joypad_mode, first.focus_mode])

	# Botão desabilitado sai do caminho do D-pad e volta quando é habilitado de novo.
	var locked: Button = Button.new()
	locked.text = "locked"
	locked.disabled = true
	menu.add_child(locked)
	menu_focus.refresh_focus_modes()
	var disabled_mode: Control.FocusMode = locked.focus_mode
	locked.disabled = false
	menu_focus.refresh_focus_modes()
	_record("Botão desabilitado fica fora do D-pad e volta ao ser habilitado",
		disabled_mode == Control.FOCUS_NONE and locked.focus_mode == Control.FOCUS_ALL,
		"desabilitado %d, habilitado %d" % [disabled_mode, locked.focus_mode])

	# Foco escolhido em código (tela cujo foco de entrada muda com o estado) ganha do Initial Focus.
	first.focus_mode = Control.FOCUS_ALL
	menu_focus.initial_focus_provider = func() -> Control: return first
	back.release_focus()
	menu_focus.focus_initial()
	var provided_owner: Control = menu.get_viewport().gui_get_focus_owner()
	_record("initial_focus_provider escolhe o foco de entrada", provided_owner == first,
		"foco em \"%s\"" % (str(provided_owner.name) if provided_owner != null else "nada"))
	menu_focus.initial_focus_provider = Callable()

	# Menu pausável com o jogo pausado (as evidências por baixo do diário): visível, mas quieto.
	var was_paused: bool = tree.paused
	menu.process_mode = Node.PROCESS_MODE_PAUSABLE
	tree.paused = true
	var presses_before: int = cancel_presses[0]
	menu_focus._unhandled_input(cancel)
	var frozen_active: bool = menu_focus.is_menu_active()
	tree.paused = was_paused
	_record("Menu congelado pela pausa não responde ao cancelar",
		not frozen_active and cancel_presses[0] == presses_before,
		"ativo=%s, cancelar apertado %d vez(es)" % [frozen_active, cancel_presses[0] - presses_before])

	first.release_focus()
	back.release_focus()
	# queue_free, e não free: a troca de dispositivo deixou um foco adiado na fila, que precisa achar o
	# nó ainda vivo (e fora da árvore, onde ele não faz nada).
	tree.root.remove_child(menu)
	menu.queue_free()


# As ações declaradas no projeto (Projeto > Input Map), sem as centenas de ui_* internas da engine
# que o projeto nunca mexeu (de edição de texto, de diálogo de arquivo...). Lidas do project.godot
# porque o ProjectSettings lista as internas junto.
func _project_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	var config: ConfigFile = ConfigFile.new()
	if config.load(PROJECT_FILE) != OK or not config.has_section(INPUT_SECTION):
		return actions
	for action_name: String in config.get_section_keys(INPUT_SECTION):
		if InputMap.has_action(StringName(action_name)):
			actions.append(StringName(action_name))
	return actions


# Diz se a ação está dispensada de ter botão no controle (lista de exceções ou prefixo de ferramenta).
func _is_exempt_action(action: StringName) -> bool:
	return EXEMPT_ACTIONS.has(action) or String(action).begins_with(EXEMPT_ACTION_PREFIX)


# Diz se a ação tem algum botão ou analógico do controle no Input Map.
func _has_joypad_event(action: StringName) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


# Chave do CSV que dá nome a um evento do controle (a mesma que o InputGlyphs procura), ou vazio
# quando o evento não é do controle.
func _joypad_label_key(event: InputEvent) -> String:
	var joypad_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joypad_button != null:
		return "INPUT_JOY_BUTTON_%d" % joypad_button.button_index
	var joypad_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joypad_motion != null:
		return "INPUT_JOY_AXIS_%d_%s" % [joypad_motion.axis, "NEG" if joypad_motion.axis_value < 0.0 else "POS"]
	return ""


# As traduções registradas no projeto, uma por idioma.
func _project_translations() -> Array[Translation]:
	var translations: Array[Translation] = []
	var paths: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	for path: String in paths:
		var translation: Translation = load(path) as Translation
		if translation != null:
			translations.append(translation)
	return translations


# As linhas do CSV de textos: chave -> os textos de cada idioma.
func _read_csv_rows() -> Dictionary[String, PackedStringArray]:
	var rows: Dictionary[String, PackedStringArray] = {}
	var file: FileAccess = FileAccess.open(TRANSLATIONS_CSV, FileAccess.READ)
	if file == null:
		return rows
	file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() < 2 or line[0].is_empty():
			continue
		rows[line[0]] = line.slice(1)
	return rows


# Todos os arquivos de uma extensão debaixo de uma pasta, recursivo.
func _files_with_extension(directory: String, extension: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(extension):
			found.append(directory.path_join(file_name))
	for subdirectory: String in DirAccess.get_directories_at(directory):
		found.append_array(_files_with_extension(directory.path_join(subdirectory), extension))
	return found


# Os métodos de um script, incluindo os herdados de scripts-base (um Interactable novo herda o
# contrato do Interactable.gd).
func _script_methods(script: Script) -> Array[StringName]:
	var methods: Array[StringName] = []
	var current: Script = script
	while current != null:
		for method: Dictionary in current.get_script_method_list():
			methods.append(StringName(method["name"]))
		current = current.get_base_script()
	return methods


# Diz se a cena mora numa pasta de ferramenta (o menu de debug), que não precisa de MenuFocus.
func _is_exempt_scene_dir(path: String) -> bool:
	for directory: String in EXEMPT_SCENE_DIRS:
		if path.begins_with(directory):
			return true
	return false


# Diz se o texto da cena (.tscn) tem algum nó "de apertar" (ver FOCUSABLE_NODE_TYPES).
func _has_focusable_node(scene_source: String) -> bool:
	for node_type: String in FOCUSABLE_NODE_TYPES:
		if scene_source.contains("type=\"%s\"" % node_type):
			return true
	return false


# Diz se a posição do texto-fonte cai num comentário (há um # antes dela na mesma linha). Os exemplos
# de uso nos comentários (is_action_pressed(&"x")) não são leituras de ação de verdade.
func _is_inside_comment(source: String, position: int) -> bool:
	var line_start: int = source.rfind("\n", position) + 1
	return source.substr(line_start, position - line_start).contains("#")


# Acrescenta a entrada na lista só se ela ainda não estiver lá (o relatório lista cada caso uma vez).
func _append_unique(list: PackedStringArray, entry: String) -> void:
	if not list.has(entry):
		list.append(entry)


# Confere o dispositivo que um evento indica.
func _expect_device(label: String, event: InputEvent, expected: int, mouse_threshold: float,
		axis_threshold: float) -> void:
	var actual: int = InputDeviceDetector.detect_device(event, mouse_threshold, axis_threshold)
	_record(label, actual == expected, "esperado %d, veio %d" % [expected, actual])


# Registra o resultado de um caso no relatório.
func _record(label: String, passed: bool, failure_detail: String) -> void:
	if passed:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
		return
	failed_count += 1
	_lines.append("  %s %s — %s" % [CROSS, label, failure_detail])


# Registra um caso que não pôde rodar. Não conta como falha nem como acerto.
func _skip(label: String, reason: String) -> void:
	_lines.append("  - %s (pulado: %s)" % [label, reason])
