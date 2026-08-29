# DebugMenu.gd — Autoload: registro de ações de debug, teclas de atalho (F1, F2 e F4) e instância
# das cenas de debug sob demanda. É "o lugar onde as ações vão ser penduradas" quando os sistemas
# de jogo existirem — hoje só as seções "Sistema" e "Desempenho" (registradas abaixo) usam o
# registro.
#
# Registrar não exige desregistrar: o Callable de um sistema descarregado é limpo sozinho na
# próxima abertura do menu (ver _purge_dead_entries()). O par (seção, rótulo) é a identidade de
# uma entrada — registrar de novo substitui em vez de duplicar, o que também cobre o caso de
# recarregar a cena.
#
# Quatro formas de registrar: register_action (botão), register_toggle (interruptor),
# register_value (campo editável solto) e register_input (botão com campos, para ações
# parametrizadas). As quatro alimentam o mesmo registro, lido pelo menu (DebugMenuOverlay) e pelo
# console (DebugConsoleOverlay/execute_command) — um registro, dois front-ends, nunca um sem o
# outro.
#
# Em build de release, register_*()/execute_command() não fazem nada e os atalhos de abrir
# menu/console ficam desligados: o autoload continua existindo (é um Node vazio), mas custa zero.
#
# O guia completo está em docs/debug_menu.md.
extends Node

enum EntryKind { ACTION, TOGGLE, VALUE, INPUT }

const TOGGLE_ACTION: StringName = &"debug_toggle_menu"
const OVERLAY_SCENE_PATH: String = "res://scenes/debugs/DebugMenu.tscn"

const CONSOLE_TOGGLE_ACTION: StringName = &"debug_toggle_console"
const CONSOLE_SCENE_PATH: String = "res://scenes/debugs/DebugConsole.tscn"
const COMMAND_HISTORY_SIZE: int = 256

const STATS_TOGGLE_ACTION: StringName = &"debug_toggle_stats"
const STATS_SCENE_PATH: String = "res://scenes/debugs/DebugStats.tscn"
const STATS_SECTION: StringName = &"Desempenho"
# O rótulo é a identidade da entrada no registro, então precisa ser constante: é por ele que
# _set_stats_enabled() reescreve o toggle com o estado real depois de um F2.
const STATS_TOGGLE_LABEL: String = "Overlay de desempenho (F2)"
const STATS_CORNER_NAMES: Array[String] = [
	"superior esquerdo", "superior direito", "inferior direito", "inferior esquerdo"
]

var _sections: Dictionary = {}   # StringName(seção) -> Array[DebugEntry], na ordem de registro
var _overlay: CanvasLayer
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
# Contador monotônico usado como DebugEntry.order — desempata o ranking do filtro/autocomplete de
# forma estável entre aberturas, e sobrevive a um re-registro (ver _store_entry()).
var _next_order: int = 0

var _console_overlay: CanvasLayer
var _command_history: PackedStringArray = []

var _stats_overlay: CanvasLayer
var _stats_enabled: bool = false
var _stats_graphs_visible: bool = true
# Canto superior direito por padrão: o menu de debug ocupa o canto superior esquerdo, e os dois
# abertos ao mesmo tempo é o caso normal, não a exceção.
var _stats_corner: int = 1


# Uma entrada registrada: um botão (ACTION), um interruptor com estado (TOGGLE), um campo solto
# (VALUE) ou um botão com campos (INPUT).
class DebugEntry:
	var section: StringName = &""
	var label: String = ""
	var callable: Callable
	# int, e não EntryKind: classe interna de GDScript não enxerga o enum do script externo de
	# forma confiável. Os call sites ficam todos no escopo externo, onde EntryKind.X funciona.
	var kind: int = 0
	var toggle_state: bool = false
	var params: Array[DebugParam] = []
	var getter: Callable = Callable()
	var requires_confirmation: bool = false
	var confirmation_text: String = ""
	var command: StringName = &""    # id do console, derivado em _store_entry()
	var search_key: String = ""      # "seção rótulo" normalizado, para o filtro
	var order: int = 0               # ordem global de registro, desempata o ranking do filtro


func _ready() -> void:
	# Sem isto, o menu para de responder assim que ele mesmo pausa o jogo (ver "Pausar jogo").
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_debug_build():
		return
	# [DEBUG] Seção "Sistema": ações de engine que não dependem de nenhum sistema de jogo,
	# registradas antes de qualquer cena, então ficam sempre em primeiro (ver docs/debug_menu.md).
	register_toggle(&"Sistema", "Pausar jogo", _on_pause_toggled)
	register_toggle(&"Sistema", "Câmera lenta (0.25x)", _on_slow_motion_toggled)
	register_action(&"Sistema", "Avançar 1 frame", _advance_one_frame)
	register_action(&"Sistema", "Recarregar cena", _reload_scene)
	register_action(&"Sistema", "Sair do jogo", _quit_game, true)
	# [DEBUG] Seção "Desempenho": controles do OSD de métricas (ver docs/debug_menu.md).
	register_toggle(STATS_SECTION, STATS_TOGGLE_LABEL, _on_stats_toggled, _stats_enabled)
	register_toggle(STATS_SECTION, "Gráficos das métricas", _on_stats_graphs_toggled, _stats_graphs_visible)
	register_action(STATS_SECTION, "Mover para o próximo canto", _cycle_stats_corner)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_debug_build():
		return
	if _is_shortcut_pressed(event, TOGGLE_ACTION, KEY_F4):
		_toggle_menu()
		get_viewport().set_input_as_handled()
	elif _is_shortcut_pressed(event, STATS_TOGGLE_ACTION, KEY_F2):
		_set_stats_enabled(not _stats_enabled)
		get_viewport().set_input_as_handled()
	elif _is_shortcut_pressed(event, CONSOLE_TOGGLE_ACTION, KEY_F1):
		_toggle_console()
		get_viewport().set_input_as_handled()


# Registra um botão que dispara uma ação imediata. requires_confirmation pendura um
# ConfirmationDialog no clique (ver docs/debug_menu.md, "Ação destrutiva"); vale só quando desfazer
# é caro ou impossível. Não faz nada em build de release.
func register_action(section: StringName, label: String, action: Callable, requires_confirmation: bool = false) -> void:
	if not _is_debug_build():
		return
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = action
	entry.kind = EntryKind.ACTION
	entry.requires_confirmation = requires_confirmation
	_check_arity(label, action, 0)
	_store_entry(entry)


# Registra um interruptor com estado visível no menu. O menu é dono do bool: guarda o valor e
# avisa a mudança via on_changed(novo_valor). Se o sistema alterar o valor por outro caminho, o
# menu desencontra até ser reaberto — ver docs/debug_menu.md. Não recebe requires_confirmation de
# propósito: um interruptor é reversível por definição (desfazer é clicar de novo). Não faz nada
# em build de release.
func register_toggle(section: StringName, label: String, on_changed: Callable, initial: bool = false) -> void:
	if not _is_debug_build():
		return
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = on_changed
	entry.kind = EntryKind.TOGGLE
	entry.toggle_state = initial
	_check_arity(label, on_changed, 1)
	_store_entry(entry)


# Registra um valor editável no menu (número, texto, bool ou opção). O menu guarda o valor no
# DebugParam e chama on_changed(novo_valor) a cada mudança do widget. getter é opcional: quando
# presente, o overlay lê o valor de verdade do sistema ao remontar em vez de exibir a cópia
# guardada — resolve o mesmo desencontro já documentado do toggle. Não faz nada em release.
func register_value(section: StringName, label: String, on_changed: Callable, param: DebugParam, getter: Callable = Callable()) -> void:
	if not _is_debug_build():
		return
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = on_changed
	entry.kind = EntryKind.VALUE
	entry.params = [param]
	entry.getter = getter
	_check_arity(label, on_changed, 1)
	_store_entry(entry)


# Registra um botão que só dispara depois de os campos declarados serem preenchidos. O clique
# chama action.callv() com os valores na ordem declarada — é o que substitui o .bind(100)
# hardcoded para ações com argumento de verdade. Não faz nada em build de release.
func register_input(section: StringName, label: String, action: Callable, params: Array[DebugParam], requires_confirmation: bool = false) -> void:
	if not _is_debug_build():
		return
	if params.is_empty():
		push_warning("[DebugMenu] - AVISO: \"%s\" chamou register_input sem parâmetros; use register_action" % label)
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = action
	entry.kind = EntryKind.INPUT
	entry.params = params
	entry.requires_confirmation = requires_confirmation
	_check_arity(label, action, params.size())
	_store_entry(entry)


# Devolve o registro atual, já sem entradas cujo dono saiu da árvore. É a única leitura do
# registro (o overlay chama isto ao montar a UI), então a limpeza acontece de graça, sem exigir
# unregister() de ninguém.
func get_sections() -> Dictionary:
	_purge_dead_entries()
	return _sections


# Executa uma linha digitada no Debug Console e devolve o texto de saída (resultado ou erro). Não
# imprime nada por conta própria: quem chamou decide onde mostrar. Mora aqui, e não no overlay do
# console, para a mesma linha poder vir de um teste automatizado ou de um argumento de linha de
# comando.
# allow_expressions tem default false (o mesmo default seguro do console) de propósito: um teste
# automatizado ou um argumento de linha de comando não deve herdar sem querer a flag de um console
# aberto — quem quer o escape hatch de expressão livre (ver docs/debug_menu.md) passa true.
func execute_command(line: String, allow_expressions: bool = false) -> String:
	var trimmed: String = line.strip_edges()
	if trimmed.is_empty():
		return ""
	_push_command_history(trimmed)

	if trimmed.begins_with(">"):
		return _run_expression(trimmed.substr(1).strip_edges(), allow_expressions)

	var tokens: PackedStringArray = DebugCommandParser.tokenize(trimmed)
	if tokens.is_empty():
		return ""
	var head: String = tokens[0]
	var rest: PackedStringArray = tokens.slice(1)

	if head == "ajuda":
		return _run_help(rest)
	if head == "secoes":
		return _run_sections()

	var matches: Array[DebugEntry] = _resolve_command(head)
	if matches.is_empty():
		return "Erro: comando \"%s\" não encontrado. Digite \"ajuda\" para listar." % head
	if matches.size() > 1:
		var names: PackedStringArray = PackedStringArray()
		for entry: DebugEntry in matches:
			names.append(String(entry.command))
		return "Comando \"%s\" é ambíguo. Candidatos: %s" % [head, ", ".join(names)]
	return _run_entry(matches[0], rest)


# Comandos cujo id casa com o texto, ranqueados pelo mesmo casador do filtro do menu. Usado pelo
# autocomplete do console (Tab e a lista de sugestões).
func find_commands(text: String) -> Array:
	_purge_dead_entries()
	var needle: String = DebugTextFilter.normalize(text)
	var scored: Array = []
	for entries: Array in _sections.values():
		for entry: DebugEntry in entries:
			if entry.command == &"":
				continue
			var entry_score: int = DebugTextFilter.score(DebugTextFilter.normalize(String(entry.command)), needle)
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


# Histórico de linhas executadas com sucesso de resolver (incluindo erros de sintaxe já
# tokenizados), do mais antigo ao mais recente. Sobrevive a fechar o console porque vive aqui.
func get_command_history() -> PackedStringArray:
	return _command_history


# Fecha o menu por código. Existe para o Esc do campo de filtro (campo vazio) poder fechar o menu
# sem duplicar a lógica de restaurar o mouse já feita em _on_menu_closed().
func close_menu() -> void:
	if _overlay != null and _overlay.visible:
		_overlay.visible = false
		_on_menu_closed()


# Fecha o console por código. Mesma motivação de close_menu(): o próprio overlay do console
# precisa fechar a si mesmo (F1 de novo, ou uma tecla dentro do campo) sem duplicar log/estado.
func close_console() -> void:
	if _console_overlay != null and _console_overlay.visible:
		_console_overlay.call(&"close")
		print("[DebugConsole] - Console de debug fechado")


# Insere a entrada na seção, substituindo qualquer entrada anterior com o mesmo rótulo. É o que
# torna o registro idempotente quando a cena que registra recarrega. Também deriva o id de
# console e a chave de busca — todo caminho de registro passa por aqui, então as duas ficam
# sempre em dia sem cada register_* precisar calculá-las.
func _store_entry(entry: DebugEntry) -> void:
	entry.command = _derive_command(entry.section, entry.label)
	entry.search_key = DebugTextFilter.normalize("%s %s" % [entry.section, entry.label])
	entry.order = _next_order
	_next_order += 1

	var entries: Array = _sections.get(entry.section, [])
	for index: int in entries.size():
		var existing: DebugEntry = entries[index]
		if existing.label == entry.label:
			_carry_over_params(existing, entry)
			entry.order = existing.order   # mantém a posição original no ranking do filtro
			entries[index] = entry
			return
	entries.append(entry)
	_sections[entry.section] = entries


# Preserva os valores digitados quando um register_value/register_input roda de novo (cena
# recarregada) com a MESMA assinatura de parâmetros. Tipos diferentes ⇒ a assinatura mudou de
# verdade, e aí o default novo é o correto — por isso a checagem é tudo ou nada.
func _carry_over_params(existing: DebugEntry, entry: DebugEntry) -> void:
	if existing.params.size() != entry.params.size():
		return
	for index: int in entry.params.size():
		if existing.params[index].type != entry.params[index].type:
			return
	for index: int in entry.params.size():
		entry.params[index].value = existing.params[index].value


# Compara a aridade do Callable com o número de parâmetros declarados. Só AVISA, nunca recusa:
# get_argument_count() não tem resposta confiável em todos os casos (variádicas, Callable já
# parcialmente ligado por bind()), e derrubar o registro por um falso positivo tiraria do ar
# exatamente a ferramenta que existe para investigar.
func _check_arity(label: String, action: Callable, expected: int) -> void:
	var declared: int = action.get_argument_count()
	if declared >= 0 and declared != expected:
		push_warning("[DebugMenu] - AVISO: \"%s\" declara %d parâmetro(s) e o Callable aceita %d"
			% [label, expected, declared])


# Deriva o id de console a partir de seção + rótulo: minúsculas, sem acento, sufixo entre
# parênteses cortado, tudo que não for [a-z0-9] vira "_". Renomear o rótulo renomeia o comando —
# é o preço documentado de não obrigar todo call site a inventar um id (ver docs/debug_menu.md).
func _derive_command(section: StringName, label: String) -> StringName:
	var section_slug: String = _slugify(String(section))
	var label_slug: String = _slugify(_strip_parenthetical(label))
	return StringName("%s.%s" % [section_slug, label_slug])


# Corta o sufixo entre parênteses de um rótulo, ex.: "Overlay de desempenho (F2)" →
# "Overlay de desempenho ". Usado só na derivação do comando; o rótulo exibido no menu não muda.
func _strip_parenthetical(text: String) -> String:
	var paren_index: int = text.find("(")
	return text if paren_index == -1 else text.substr(0, paren_index)


# Normaliza e reduz um texto a [a-z0-9_], colapsando underscores repetidos. É o passo final da
# derivação do comando, compartilhado entre seção e rótulo.
func _slugify(text: String) -> String:
	var normalized: String = DebugTextFilter.normalize(text)
	var result: String = ""
	for character: String in normalized:
		var is_lowercase_letter: bool = character >= "a" and character <= "z"
		var is_digit: bool = character >= "0" and character <= "9"
		result += character if (is_lowercase_letter or is_digit) else "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	return result.trim_prefix("_").trim_suffix("_")


# Resolve um nome digitado no console para as entradas cujo command bate exatamente ou cujo
# sufixo (depois do ".") bate — o "sufixo mais curto que for único" documentado em
# docs/debug_menu.md. Prioriza sempre o match exato sobre sufixos.
func _resolve_command(name: String) -> Array[DebugEntry]:
	_purge_dead_entries()
	var exact: Array[DebugEntry] = []
	var suffix_matches: Array[DebugEntry] = []
	for entries: Array in _sections.values():
		for entry: DebugEntry in entries:
			if entry.command == &"":
				continue
			var command_text: String = String(entry.command)
			if command_text == name:
				exact.append(entry)
			elif command_text.ends_with("." + name):
				suffix_matches.append(entry)
	return exact if not exact.is_empty() else suffix_matches


func _push_command_history(line: String) -> void:
	_command_history.append(line)
	if _command_history.size() > COMMAND_HISTORY_SIZE:
		_command_history = _command_history.slice(_command_history.size() - COMMAND_HISTORY_SIZE)


# Comando embutido "ajuda": sem argumento lista tudo; com um comando exato mostra a linha de uso;
# com texto livre, filtra pelo mesmo casador do menu.
func _run_help(args: PackedStringArray) -> String:
	if args.is_empty():
		return _list_all_commands()
	var query: String = " ".join(args)
	var exact: Array[DebugEntry] = _resolve_command(query)
	if exact.size() == 1:
		return DebugCommandParser.usage_line(exact[0].command, exact[0].params)
	var matches: Array = find_commands(query)
	if matches.is_empty():
		return "Nenhum comando corresponde a \"%s\"." % query
	var lines: PackedStringArray = PackedStringArray()
	for entry: DebugEntry in matches:
		lines.append(String(entry.command))
	return "\n".join(lines)


func _list_all_commands() -> String:
	_purge_dead_entries()
	var lines: PackedStringArray = PackedStringArray()
	for section: StringName in _sections.keys():
		for entry: DebugEntry in _sections[section]:
			if entry.command != &"":
				lines.append(String(entry.command))
	return "\n".join(lines)


# Comando embutido "secoes": lista as seções na ordem de registro.
func _run_sections() -> String:
	_purge_dead_entries()
	var names: PackedStringArray = PackedStringArray()
	for section: StringName in _sections.keys():
		names.append(String(section))
	return "\n".join(names)


# Escape hatch de expressão livre (prefixo ">"), atrás de allow_expressions. Ver docs/debug_menu.md
# e SPEC §2.4 para os motivos de isto não ser o modelo principal do console.
func _run_expression(code: String, allow_expressions: bool) -> String:
	if not allow_expressions:
		return "Expressões livres estão desligadas. Ative \"Allow Expressions\" no console (F1) para habilitar."
	if code.is_empty():
		return "Uso: > <expressão>"
	var expression: Expression = Expression.new()
	if expression.parse(code) != OK:
		return "Erro ao interpretar: %s" % expression.get_error_text()
	var result: Variant = expression.execute([], null, true)
	if expression.has_execute_failed():
		return "Erro ao executar: %s" % expression.get_error_text()
	print("[DebugConsole] - Expressão \"%s\" executada" % code)
	return str(result)


# Despacha a execução de uma entrada resolvida pelo tipo dela. O console não pede confirmação
# nenhuma aqui (ver docs/debug_menu.md, "Console"): digitar o comando inteiro já é o ato
# deliberado que a confirmação do menu existe para exigir.
func _run_entry(entry: DebugEntry, tokens: PackedStringArray) -> String:
	match entry.kind:
		EntryKind.ACTION:
			return _run_console_action(entry, tokens)
		EntryKind.TOGGLE:
			return _run_console_toggle(entry, tokens)
		EntryKind.VALUE:
			return _run_console_value(entry, tokens)
		EntryKind.INPUT:
			return _run_console_input(entry, tokens)
	return ""


func _run_console_action(entry: DebugEntry, tokens: PackedStringArray) -> String:
	if not tokens.is_empty():
		return "Erro: \"%s\" não aceita argumentos." % entry.command
	entry.callable.call()
	print("[DebugConsole] - Comando \"%s\" executado" % entry.command)
	return "\"%s\" executado." % entry.command


func _run_console_toggle(entry: DebugEntry, tokens: PackedStringArray) -> String:
	var param: DebugParam = DebugParam.bool_value("ligado", entry.toggle_state)
	if tokens.size() != 1:
		return "Uso: %s %s" % [entry.command, param.usage_text()]
	var value: Variant = param.coerce(tokens[0])
	if value == null:
		return "Erro: \"%s\" não é um bool válido para %s.\nUso: %s %s" % [tokens[0], param.usage_text(), entry.command, param.usage_text()]
	entry.toggle_state = value
	entry.callable.call(value)
	print("[DebugConsole] - Comando \"%s\" executado" % entry.command)
	return "\"%s\" agora %s." % [entry.command, "ligado" if value else "desligado"]


func _run_console_value(entry: DebugEntry, tokens: PackedStringArray) -> String:
	var param: DebugParam = entry.params[0]
	if tokens.size() != 1:
		return "Uso: %s %s" % [entry.command, param.usage_text()]
	var value: Variant = param.coerce(tokens[0])
	if value == null:
		return "Erro: \"%s\" não é um %s válido para %s.\nUso: %s %s" % [
			tokens[0], param.type_name(), param.usage_text(), entry.command, param.usage_text()
		]
	param.value = value
	entry.callable.call(value)
	print("[DebugConsole] - Comando \"%s\" executado" % entry.command)
	return "\"%s\" definido para %s." % [entry.command, value]


func _run_console_input(entry: DebugEntry, tokens: PackedStringArray) -> String:
	var bind_result: DebugCommandParser.Result = DebugCommandParser.bind_arguments(entry.params, tokens)
	if not bind_result.ok:
		return "Erro: %s\nUso: %s" % [bind_result.message, DebugCommandParser.usage_line(entry.command, entry.params)]
	for index: int in entry.params.size():
		entry.params[index].value = bind_result.values[index]
	entry.callable.callv(bind_result.values)
	print("[DebugConsole] - Comando \"%s\" executado" % entry.command)
	return "\"%s\" executado." % entry.command


# Remove entradas cujo Callable aponta para um nó já liberado (cena descarregada). Sem isto, o
# menu acumularia botões mortos toda vez que uma cena de jogo troca.
func _purge_dead_entries() -> void:
	for section: StringName in _sections.keys():
		var alive: Array = []
		for entry: DebugEntry in _sections[section]:
			if entry.callable.is_valid():
				alive.append(entry)
		if alive.is_empty():
			_sections.erase(section)
		else:
			_sections[section] = alive


# Abre ou fecha o menu, instanciando a cena na primeira vez que é pedido: enquanto ninguém aperta
# F4, o menu não custa nada.
func _toggle_menu() -> void:
	if _overlay == null:
		var scene: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugMenu] - ERRO: cena do menu de debug não encontrada em %s" % OVERLAY_SCENE_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		add_child(_overlay)
		_on_menu_opened()
		return
	if _overlay.visible:
		_overlay.visible = false
		_on_menu_closed()
	else:
		_overlay.visible = true
		_on_menu_opened()


# Guarda o modo de mouse anterior e força o cursor visível: o jogo pode estar com o mouse
# capturado, e sem isto não dá para clicar em nada no menu.
func _on_menu_opened() -> void:
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.call(&"refresh")
	print("[DebugMenu] - Menu de debug aberto")


# Restaura o modo de mouse anterior ao fechar, para não deixar o cursor visível dentro do jogo.
func _on_menu_closed() -> void:
	Input.mouse_mode = _previous_mouse_mode
	print("[DebugMenu] - Menu de debug fechado")


# Abre ou fecha o console, instanciando a cena na primeira vez que é pedido. Ao contrário do menu,
# o console pega o foco do teclado ao abrir e o solta ao fechar — digitar é a única coisa que ele
# faz, então não precisa liberar o mouse.
func _toggle_console() -> void:
	if _console_overlay == null:
		var scene: PackedScene = load(CONSOLE_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugMenu] - ERRO: cena do console de debug não encontrada em %s" % CONSOLE_SCENE_PATH)
			return
		_console_overlay = scene.instantiate() as CanvasLayer
		add_child(_console_overlay)
		_console_overlay.call(&"open")
		print("[DebugConsole] - Console de debug aberto")
		return
	if _console_overlay.visible:
		close_console()
	else:
		_console_overlay.call(&"open")
		print("[DebugConsole] - Console de debug aberto")


# Liga/desliga a pausa da árvore. É a ação mais usada de um mod menu: metade do debug é olhar o
# jogo parado num instante específico.
func _on_pause_toggled(enabled: bool) -> void:
	get_tree().paused = enabled


# Liga/desliga câmera lenta via time_scale, para observar movimento rápido demais para o olho.
func _on_slow_motion_toggled(enabled: bool) -> void:
	Engine.time_scale = 0.25 if enabled else 1.0


# Despausa por exatamente um frame e pausa de novo. Só faz sentido com o jogo já pausado — é a
# única forma honesta de investigar um bug que dura um frame só.
func _advance_one_frame() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().paused = true


# Recarrega a cena atual, tirando a pausa antes para a cena não nascer congelada.
func _reload_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# Encerra o jogo. Útil para testar o caminho de saída sem alt+F4. Pede confirmação (ver
# register_action acima) porque mata a sessão e, junto com ela, o estado que estava sendo
# investigado.
func _quit_game() -> void:
	get_tree().quit()


# Liga/desliga o OSD de desempenho, instanciando a cena na primeira vez e liberando-a ao desligar.
# Liberar (em vez de esconder) é proposital: o overlay pede à RenderingServer a medição de tempo de
# render do viewport, que custa uma consulta ao driver por quadro. Um medidor invisível que continua
# cobrando pela medição é exatamente o tipo de coisa que envenena um profiling.
func _set_stats_enabled(enabled: bool) -> void:
	_stats_enabled = enabled
	if enabled:
		var scene: PackedScene = load(STATS_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugMenu] - ERRO: cena do overlay de desempenho não encontrada em %s" % STATS_SCENE_PATH)
			_stats_enabled = false
			return
		_stats_overlay = scene.instantiate() as CanvasLayer
		add_child(_stats_overlay)
		# As preferências vivem aqui, não no overlay: elas precisam sobreviver ao overlay ser
		# liberado e recriado a cada F2.
		_stats_overlay.call(&"set_corner", _stats_corner)
		_stats_overlay.call(&"set_graphs_visible", _stats_graphs_visible)
		print("[DebugMenu] - Overlay de desempenho ligado (canto %s)" % STATS_CORNER_NAMES[_stats_corner])
	else:
		if _stats_overlay != null:
			_stats_overlay.queue_free()
			_stats_overlay = null
		print("[DebugMenu] - Overlay de desempenho desligado")
	# Reescreve o toggle com o estado real. Sem isto, ligar o OSD pelo F2 deixaria o interruptor do
	# menu marcando o valor errado na próxima abertura — o menu é dono do bool que ele exibe.
	register_toggle(STATS_SECTION, STATS_TOGGLE_LABEL, _on_stats_toggled, _stats_enabled)


# Reage ao interruptor do menu. Mesmo caminho do F2, para os dois não poderem divergir.
func _on_stats_toggled(enabled: bool) -> void:
	_set_stats_enabled(enabled)


# Liga/desliga os mini-gráficos do OSD, deixando só os números. Guarda a preferência mesmo com o
# overlay desligado, para ela valer no próximo F2.
func _on_stats_graphs_toggled(enabled: bool) -> void:
	_stats_graphs_visible = enabled
	if _stats_overlay != null:
		_stats_overlay.call(&"set_graphs_visible", enabled)
	print("[DebugMenu] - Gráficos do overlay de desempenho %s" % ("ligados" if enabled else "desligados"))


# Gira o OSD entre os quatro cantos da tela. Existe porque o canto certo depende do que se está
# investigando: um HUD de jogo ou o próprio menu de debug empurram o OSD para outro lugar.
func _cycle_stats_corner() -> void:
	_stats_corner = (_stats_corner + 1) % STATS_CORNER_NAMES.size()
	if _stats_overlay != null:
		_stats_overlay.call(&"set_corner", _stats_corner)
	print("[DebugMenu] - Overlay de desempenho movido para o canto %s" % STATS_CORNER_NAMES[_stats_corner])


# Aceita a ação de input configurada e, se ela não existir no projeto, cai para a tecla direta.
# Evita que uma falha de configuração do Input Map deixe uma ferramenta de debug inacessível.
func _is_shortcut_pressed(event: InputEvent, action: StringName, fallback_keycode: Key) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == fallback_keycode


# Único ponto de checagem de build: editor ou build de debug. Release cai fora de register_*,
# do input de abertura e do registro de fábrica, sem precisar de um `if` em cada call site.
func _is_debug_build() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()
