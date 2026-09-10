# InsightJournal.gd — Autoload: o que o jogador já leu e quais flags o mundo já concedeu.
#
# É o dono do estado do sistema de insights. O InsightDirector consulta este registro para decidir
# o que ainda vale mostrar; ninguém mais escreve nele por fora — o diário escuta insight_revealed e
# se atualiza sozinho.
#
# ARMADILHA DO SAVE: o SaveManager serializa via JSON.stringify, e na volta todo StringName vira
# String. Comparar StringName com String falha em silêncio e o jogador reencontra insights que já
# leu, então a conversão na leitura (StringName(...)) é obrigatória, não estilo.
#
# ENQUANTO NÃO HÁ DONO DO SLOT ATIVO: o jogo ainda não tem fluxo de save de verdade (o menu vai
# direto para a cidade, sem escolher slot), então o diário carrega e salva sozinho no slot 1. No dia
# em que o slot ativo existir, quem for dono dele define save_slot_path e desliga o autosave — a
# API pública (to_dict/from_dict) já é a que esse fluxo vai usar.
#
# O guia completo está em docs/insights.md.
extends Node

# Emitido quando o conjunto de lidos ou de flags muda. Não é evento de bus: o único interessado é o
# InsightDirector, que reavalia os marcadores — relação direta e permanente entre dois sistemas,
# que docs/event_bus.md manda resolver com signal direto em vez de engordar o bus.
signal journal_changed

const DEBUG_SECTION: StringName = &"Insights"
const SAVE_KEY: String = "insights"
const READ_KEY: String = "read"
const FLAGS_KEY: String = "flags"

# Slot em que o diário lê e grava. Público de propósito: é o gancho para o dia em que alguém for
# dono do slot ativo.
var save_slot_path: String = ""
# Grava o diário no slot a cada mudança. Ver o bloco "ENQUANTO NÃO HÁ DONO DO SLOT ATIVO" acima.
var autosave_enabled: bool = true

var _read_ids: Dictionary = {}    # StringName(id do insight) -> true
var _flags: Dictionary = {}       # StringName(flag) -> true
# Evita gravar o arquivo N vezes quando uma leitura marca o lido e concede a flag no mesmo frame.
var _autosave_queued: bool = false


func _ready() -> void:
	if save_slot_path.is_empty():
		save_slot_path = SaveManager.save_file_1
	EventBus.insight_revealed.connect(_on_insight_revealed)
	load_from_slot()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": estado do diário (ver docs/insights.md).
		DebugMenu.register_action(DEBUG_SECTION, "Listar estado do diário", _print_journal)
		DebugMenu.register_input(DEBUG_SECTION, "Conceder flag", _debug_grant_flag, [
			DebugParam.string_value("flag", "", _debug_flag_suggestions)
		])
		DebugMenu.register_action(DEBUG_SECTION, "Resetar lidos", _debug_reset_read, true)
		DebugMenu.register_action(DEBUG_SECTION, "Resetar diário", _debug_reset_all, true)
		DebugMenu.register_action(DEBUG_SECTION, "Salvar diário", save_to_slot)
		DebugMenu.register_action(DEBUG_SECTION, "Carregar diário", load_from_slot)
		DebugMenu.register_toggle(DEBUG_SECTION, "Salvar automático", _debug_set_autosave, autosave_enabled)


# Diz se o insight já foi lido alguma vez. É a consulta mais quente do sistema (roda por insight, a
# cada reavaliação de marcador), por isso o registro é um Dictionary e não um Array.
func is_read(insight_id: StringName) -> bool:
	return _read_ids.has(insight_id)


# Marca o insight como lido. Idempotente: marcar de novo não emite journal_changed à toa, o que
# custaria uma reavaliação de todos os marcadores por nada.
func mark_read(insight_id: StringName) -> void:
	if insight_id == &"" or _read_ids.has(insight_id):
		return
	_read_ids[insight_id] = true
	_notify_changed()


# Diz se a flag foi concedida. É o que abre (required_flags) e fecha (blocked_by_flags) as portas de
# um insight.
func has_flag(flag: StringName) -> bool:
	return _flags.has(flag)


# Concede uma flag ao mundo. Idempotente pelo mesmo motivo de mark_read().
func grant_flag(flag: StringName) -> void:
	if flag == &"" or _flags.has(flag):
		return
	_flags[flag] = true
	print("[Insights] - Flag \"%s\" concedida" % flag)
	_notify_changed()


# Flags concedidas até agora, em ordem alfabética. Usada pelo relatório de debug e pela validação em
# lote (que procura porta morta comparando com o que os insights concedem).
func get_flags() -> Array[StringName]:
	var result: Array[StringName] = []
	for flag: StringName in _flags.keys():
		result.append(flag)
	result.sort_custom(_compare_names)
	return result


# Ids de insight já lidos, em ordem alfabética. Mesma motivação de get_flags().
func get_read_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for insight_id: StringName in _read_ids.keys():
		result.append(insight_id)
	result.sort_custom(_compare_names)
	return result


# Esquece tudo: lidos e flags. Existe para o debug e para o dia em que "novo jogo" precisar zerar o
# diário sem apagar o arquivo de save inteiro.
func reset() -> void:
	_read_ids.clear()
	_flags.clear()
	print("[Insights] - Diário zerado")
	_notify_changed()


# Estado do diário como Dictionary, no formato que o SaveManager sabe serializar. Arrays de String
# (e não de StringName) porque é isso que sobrevive ao JSON.
func to_dict() -> Dictionary:
	var read_list: Array[String] = []
	for insight_id: StringName in get_read_ids():
		read_list.append(String(insight_id))
	var flag_list: Array[String] = []
	for flag: StringName in get_flags():
		flag_list.append(String(flag))
	return { READ_KEY: read_list, FLAGS_KEY: flag_list }


# Recarrega o diário a partir de um Dictionary vindo do save. A conversão explícita para StringName
# é a armadilha documentada no topo deste arquivo: sem ela, is_read() nunca mais acha nada.
func from_dict(data: Dictionary) -> void:
	_read_ids.clear()
	_flags.clear()
	for raw_id: Variant in data.get(READ_KEY, []):
		_read_ids[StringName(str(raw_id))] = true
	for raw_flag: Variant in data.get(FLAGS_KEY, []):
		_flags[StringName(str(raw_flag))] = true
	# Sem agendar gravação: carregar não é mudança, e salvar de volta o que se acabou de ler
	# reescreveria o arquivo a cada boot do jogo por nada.
	_notify_changed(false)


# Grava o diário dentro do slot atual, preservando as outras chaves do arquivo: o save é de todos os
# sistemas, e reescrevê-lo inteiro apagaria o que os outros já tinham guardado.
func save_to_slot() -> void:
	var data: Dictionary = SaveManager.load_game(save_slot_path)
	data[SAVE_KEY] = to_dict()
	SaveManager.save_game(data, save_slot_path)
	print("[Insights] - Diário salvo em \"%s\" (%d lidos, %d flags)"
		% [save_slot_path, _read_ids.size(), _flags.size()])


# Lê o diário do slot atual. Slot sem a chave de insights (save antigo, ou slot novo) devolve
# Dictionary vazio e o diário simplesmente começa zerado — nunca é erro.
func load_from_slot() -> void:
	var data: Dictionary = SaveManager.load_game(save_slot_path)
	from_dict(data.get(SAVE_KEY, {}) as Dictionary)
	print("[Insights] - Diário carregado de \"%s\" (%d lidos, %d flags)"
		% [save_slot_path, _read_ids.size(), _flags.size()])


# Registra a leitura do insight. Só reage à primeira vez: releitura não muda estado nenhum, e
# disparar journal_changed nela custaria uma reavaliação de todos os marcadores por nada. A flag
# concedida pelo insight é responsabilidade do Director, que conhece o recurso; aqui só chega o id.
func _on_insight_revealed(event: InsightRevealedEvent) -> void:
	if not event.first_time:
		return
	mark_read(event.insight_id)


# Anuncia a mudança e agenda a gravação. A gravação é adiada para o fim do frame porque uma leitura
# costuma marcar o lido e conceder uma flag em sequência, e o arquivo não precisa ser escrito duas
# vezes por causa disso. schedule_autosave existe para a leitura do save não gravar de volta o que
# acabou de ler.
func _notify_changed(schedule_autosave: bool = true) -> void:
	journal_changed.emit()
	if not schedule_autosave or not autosave_enabled or _autosave_queued:
		return
	_autosave_queued = true
	_flush_autosave.call_deferred()


# Executa a gravação agendada por _notify_changed().
func _flush_autosave() -> void:
	_autosave_queued = false
	if autosave_enabled:
		save_to_slot()


# [DEBUG] Imprime lidos e flags no log do jogo (visível no visualizador de log, F5).
func _print_journal() -> void:
	var flags: Array[StringName] = get_flags()
	var read_ids: Array[StringName] = get_read_ids()
	print("[Insights] - Flags concedidas (%d): %s" % [flags.size(), _join_names(flags, "nenhuma")])
	print("[Insights] - Insights lidos (%d): %s" % [read_ids.size(), _join_names(read_ids, "nenhum")])


# Ordena dois StringName em ordem alfabética de verdade. Existe porque a comparação nativa de
# StringName é por ponteiro interno (rápida, e sem relação nenhuma com o alfabeto): sem a conversão
# para String, a lista sai numa ordem diferente a cada execução e o relatório fica ilegível.
func _compare_names(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


# Junta uma lista de nomes numa linha só, com um texto de fallback para a lista vazia — sem ele o
# relatório imprime uma linha terminada em dois-pontos e ninguém sabe se é vazio ou se quebrou.
func _join_names(names: Array[StringName], empty_text: String) -> String:
	if names.is_empty():
		return empty_text
	var parts: PackedStringArray = PackedStringArray()
	for name_value: StringName in names:
		parts.append(String(name_value))
	return ", ".join(parts)


# [DEBUG] Concede uma flag pelo menu/console, para testar uma porta sem reproduzir a condição de
# jogo que a abriria.
func _debug_grant_flag(flag: String) -> void:
	grant_flag(StringName(flag))


# [DEBUG] Sugere ao autocomplete do console as flags que algum insight do projeto concede ou exige —
# assim o operador não precisa decorar nome de flag.
func _debug_flag_suggestions() -> PackedStringArray:
	var names: Dictionary = {}
	for insight: InsightData in InsightCatalog.load_all_insights():
		if insight.grants_flag != &"":
			names[String(insight.grants_flag)] = true
		for flag: StringName in insight.required_flags:
			names[String(flag)] = true
		for flag: StringName in insight.blocked_by_flags:
			names[String(flag)] = true
	var result: PackedStringArray = PackedStringArray(names.keys())
	result.sort()
	return result


# [DEBUG] Esquece só os lidos, mantendo as flags: é o reset que serve para reler o conteúdo de uma
# cena sem desmontar o progresso das portas.
func _debug_reset_read() -> void:
	_read_ids.clear()
	print("[Insights] - Lidos zerados")
	_notify_changed()


# [DEBUG] Esquece tudo.
func _debug_reset_all() -> void:
	reset()


# [DEBUG] Liga/desliga a gravação automática do diário.
func _debug_set_autosave(enabled: bool) -> void:
	autosave_enabled = enabled
	print("[Insights] - Salvamento automático do diário %s" % ("ligado" if enabled else "desligado"))
