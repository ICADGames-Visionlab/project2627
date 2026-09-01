# DebugConsoleOverlay.gd — Console de comando livre para o Debug Menu. Cena e script próprios,
# ancorados no rodapé (o menu e o OSD de desempenho ocupam o topo), tecla própria (F1).
#
# Não tem registro próprio: os comandos SÃO as entradas do DebugMenu (ver DebugMenu.execute_command,
# find_commands, get_command_history). Registrar uma ação no menu passa a dar as duas coisas de
# uma vez — é o "um registro, dois front-ends" documentado em docs/debug_menu.md.
#
# Ao contrário do menu, o console pega o foco do teclado ao abrir e o solta ao fechar: digitar é a
# única coisa que ele faz.
#
# Os textos deste painel (e as mensagens de erro que vêm do DebugMenu) são intencionalmente
# hardcoded: a exigência de tr() do Guideline vale para texto exibido ao jogador, e este console
# não existe em build de release. Ver docs/debug_menu.md, "Os textos da ferramenta não passam por
# tr()".
extends CanvasLayer

@export var output_lines: int = 12
@export var history_size: int = 64
@export var suggestion_count: int = 6
# Escape hatch de Expression livre (prefixo ">"), desligado por padrão. Ver docs/debug_menu.md
# para os motivos de isto não ser o modelo principal do console.
@export var allow_expressions: bool = false

var _history_index: int = -1
var _tab_candidates: PackedStringArray = []
var _tab_index: int = -1
var _output_buffer: PackedStringArray = []

@onready var _output: RichTextLabel = $Panel/Margin/Layout/Output
@onready var _suggestions_label: Label = $Panel/Margin/Layout/Suggestions
@onready var _input_field: LineEdit = $Panel/Margin/Layout/Input


func _ready() -> void:
	# Sem isto, o console congela junto com o jogo assim que "Pausar jogo" é ligado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Entra no grupo dos overlays de debug para a captura de tela (F6) poder escondê-lo sem
	# conhecer esta cena (ver DebugScreenCapture).
	add_to_group(DebugMenu.OVERLAY_GROUP)
	visible = false
	_input_field.text_submitted.connect(_on_input_text_submitted)
	_input_field.gui_input.connect(_on_input_gui_input)
	_append_output("Digite \"ajuda\" para listar os comandos, ou \"ajuda <comando>\" para ver o uso de um deles.")


# Mostra o console e passa o foco ao campo de texto.
func open() -> void:
	visible = true
	_input_field.grab_focus.call_deferred()


# Esconde o console e devolve o foco.
func close() -> void:
	visible = false
	_input_field.release_focus()


# Processa a linha submetida (Enter). "limpar" é tratado aqui, e não em DebugMenu.execute_command,
# porque é uma ação de UI (esvaziar o RichTextLabel) e não uma entrada do registro.
func _on_input_text_submitted(line: String) -> void:
	var trimmed: String = line.strip_edges()
	_input_field.text = ""
	_history_index = -1
	_tab_candidates = PackedStringArray()
	_tab_index = -1
	_update_suggestions_label(PackedStringArray())

	if trimmed.is_empty():
		return
	if trimmed.to_lower() == "limpar":
		_clear_output()
		return

	_append_output("> %s" % trimmed)
	var response: String = DebugMenu.execute_command(trimmed, allow_expressions)
	if not response.is_empty():
		_append_output(response)


# Tab completa/cicla comando ou argumento; ↑/↓ navegam o histórico. Interceptado aqui (e não
# deixado para o comportamento default do LineEdit) porque Tab move o foco por padrão e ↑/↓ não
# fazem nada num LineEdit de uma linha só.
func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key_event: InputEventKey = event as InputEventKey
	match key_event.keycode:
		KEY_TAB:
			_handle_tab_completion()
			_input_field.accept_event()
		KEY_UP:
			_navigate_history(1)
			_input_field.accept_event()
		KEY_DOWN:
			_navigate_history(-1)
			_input_field.accept_event()


# Completa pelo prefixo comum e cicla entre os candidatos a cada Tab seguinte. Na posição de
# comando (nenhum espaço ainda digitado), casa contra DebugMenu.find_commands(); na posição de
# argumento, casa contra DebugParam.get_suggestions() do parâmetro correspondente.
# Simplificação conhecida: a linha é reconstruída token a token, então um valor entre aspas já
# digitado perde as aspas ao completar outro token — aceitável para uma ferramenta de debug.
func _handle_tab_completion() -> void:
	var line: String = _input_field.text
	var ends_with_space: bool = line.ends_with(" ")
	var tokens: PackedStringArray = DebugCommandParser.tokenize(line)
	var is_command_position: bool = tokens.size() <= 1 and not ends_with_space

	var candidates: PackedStringArray
	if is_command_position:
		var partial: String = tokens[0] if tokens.size() == 1 else ""
		candidates = _command_name_candidates(partial)
	else:
		var command_name: String = tokens[0] if not tokens.is_empty() else ""
		var arg_index: int = tokens.size() if ends_with_space else tokens.size() - 1
		var partial: String = "" if ends_with_space else tokens[tokens.size() - 1]
		candidates = _argument_candidates(command_name, arg_index, partial)

	if candidates.is_empty():
		_update_suggestions_label(PackedStringArray())
		return

	if _tab_candidates != candidates:
		_tab_candidates = candidates
		_tab_index = 0
	else:
		_tab_index = (_tab_index + 1) % _tab_candidates.size()

	var completed: String = _tab_candidates[_tab_index]
	if is_command_position:
		_input_field.text = completed + " "
	else:
		var prefix_tokens: PackedStringArray = tokens.duplicate()
		if ends_with_space:
			prefix_tokens.append(completed)
		else:
			prefix_tokens[prefix_tokens.size() - 1] = completed
		_input_field.text = " ".join(prefix_tokens) + " "
	_input_field.caret_column = _input_field.text.length()
	_update_suggestions_label(_tab_candidates)


func _command_name_candidates(partial: String) -> PackedStringArray:
	var matches: Array = DebugMenu.find_commands(partial)
	var names: PackedStringArray = PackedStringArray()
	for entry: DebugMenu.DebugEntry in matches:
		names.append(String(entry.command))
	return names


# Sugestões para o parâmetro na posição arg_index do comando já identificado. A lista vem de
# DebugParam.get_suggestions() — nunca assada no registro, então itens adicionados depois do
# registro (ex.: um catálogo de itens) aparecem sozinhos.
func _argument_candidates(command_name: String, arg_index: int, partial: String) -> PackedStringArray:
	var matches: Array = DebugMenu.find_commands(command_name)
	if matches.is_empty():
		return PackedStringArray()
	var entry: DebugMenu.DebugEntry = matches[0]
	if arg_index < 0 or arg_index >= entry.params.size():
		return PackedStringArray()
	var param: DebugParam = entry.params[arg_index]
	var all_suggestions: PackedStringArray = param.get_suggestions()
	if partial.is_empty():
		return all_suggestions

	var needle: String = DebugTextFilter.normalize(partial)
	var scored: Array = []
	for suggestion: String in all_suggestions:
		var suggestion_score: int = DebugTextFilter.score(DebugTextFilter.normalize(suggestion), needle)
		if suggestion_score >= 0:
			scored.append({"text": suggestion, "score": suggestion_score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var result: PackedStringArray = PackedStringArray()
	for item: Dictionary in scored:
		result.append(item["text"])
	return result


func _update_suggestions_label(candidates: PackedStringArray) -> void:
	if candidates.is_empty():
		_suggestions_label.text = ""
		return
	var shown: PackedStringArray = candidates.slice(0, mini(suggestion_count, candidates.size()))
	_suggestions_label.text = "  ".join(shown)


# Navega um histórico circular: direction=1 (↑) vai para trás no tempo, direction=-1 (↓) vai para
# frente, e os dois dão a volta nas pontas. O histórico em si vive no DebugMenu (sobrevive a
# fechar o console); aqui só se navega os últimos history_size itens dele.
func _navigate_history(direction: int) -> void:
	var history: PackedStringArray = DebugMenu.get_command_history()
	if history.is_empty():
		return
	var recent: PackedStringArray = history.slice(maxi(0, history.size() - history_size))
	_history_index = wrapi(_history_index + direction, 0, recent.size())
	_input_field.text = recent[recent.size() - 1 - _history_index]
	_input_field.caret_column = _input_field.text.length()


func _append_output(text: String) -> void:
	for line: String in text.split("\n"):
		_output_buffer.append(line)
	if _output_buffer.size() > output_lines:
		_output_buffer = _output_buffer.slice(_output_buffer.size() - output_lines)
	_output.text = "\n".join(_output_buffer)


func _clear_output() -> void:
	_output_buffer = PackedStringArray()
	_output.text = ""
