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
# ENTRA NO SAVE PELO SaveManager: o diário é o participante "insights" (to_dict/from_dict), registrado
# no _ready(). Quem escolhe o slot e abre a partida é o SaveManager; toda mudança aqui só PEDE
# gravação (request_save), e carregar não pede. Sem partida ativa (menu, cena rodada pelo F6) o
# diário começa vazio e nada é gravado.
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

var _read_ids: Dictionary = {}    # StringName(id do insight) -> true
var _flags: Dictionary = {}       # StringName(flag) -> true


func _ready() -> void:
	EventBus.insight_revealed.connect(_on_insight_revealed)
	# Sem partida ativa no boot, isto só registra: quem entrega a seção salva é o continue_game.
	SaveManager.register_participant(SAVE_KEY, to_dict, from_dict)
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": estado do diário (ver docs/insights.md).
		DebugMenu.register_action(DEBUG_SECTION, "Listar estado do diário", _print_journal)
		DebugMenu.register_input(DEBUG_SECTION, "Conceder flag", _debug_grant_flag, [
			DebugParam.string_value("flag", "", _debug_flag_suggestions)
		])
		DebugMenu.register_action(DEBUG_SECTION, "Resetar lidos", _debug_reset_read, true)
		DebugMenu.register_action(DEBUG_SECTION, "Resetar diário", _debug_reset_all, true)


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


# Esquece tudo: lidos e flags. Existe para o debug: zera o diário da partida ativa (e pede gravação)
# sem apagar o slot. O novo jogo não passa por aqui: ele chega como from_dict({}).
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


# Recarrega o diário a partir da seção "insights" do save. {} é o novo jogo (diário zerado), nunca
# erro: slot novo e save antigo sem a chave caem aqui. A conversão explícita para StringName é a
# armadilha documentada no topo deste arquivo: sem ela, is_read() nunca mais acha nada.
func from_dict(data: Dictionary) -> void:
	_read_ids.clear()
	_flags.clear()
	for raw_id: Variant in data.get(READ_KEY, []):
		_read_ids[StringName(str(raw_id))] = true
	for raw_flag: Variant in data.get(FLAGS_KEY, []):
		_flags[StringName(str(raw_flag))] = true
	print("[Insights] - Diário carregado do save (%d lidos, %d flags)" % [_read_ids.size(), _flags.size()])
	# Sem pedir gravação: carregar não é mudança, e gravar de volta o que se acabou de ler
	# reescreveria o arquivo a cada partida aberta por nada.
	_notify_changed(false)


# Registra a leitura do insight. Só reage à primeira vez: releitura não muda estado nenhum, e
# disparar journal_changed nela custaria uma reavaliação de todos os marcadores por nada. A flag
# concedida pelo insight é responsabilidade do Director, que conhece o recurso; aqui só chega o id.
func _on_insight_revealed(event: InsightRevealedEvent) -> void:
	if not event.first_time:
		return
	mark_read(event.insight_id)


# Anuncia a mudança e pede gravação ao SaveManager. Uma leitura costuma marcar o lido e conceder uma
# flag em sequência; os dois pedidos viram uma escrita só, porque o SaveManager junta tudo o que
# chega até o próximo frame. schedule_autosave existe para a leitura do save não pedir gravação do
# que acabou de ler.
func _notify_changed(schedule_autosave: bool = true) -> void:
	journal_changed.emit()
	if schedule_autosave:
		SaveManager.request_save()


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


# [DEBUG] Esquece tudo. Com partida ativa, o diário zerado vai para o slot na próxima gravação.
func _debug_reset_all() -> void:
	reset()
