# InsightDebugReport.gd — Os dois relatórios que respondem "por que este insight não aparece?".
#
# O sistema tem cinco portas e todas falham do mesmo jeito: o orbe não aparece. Sem ferramenta, o
# designer coloca um insight, roda o jogo, não vê nada e não tem como saber qual das cinco foi — e
# aí cada teste de conteúdo vira um pedido a um programador.
#
#   - scene_report()   responde por uma cena: cada fonte, cada insight, ✓/✗ por porta e o vencedor.
#   - project_report() varre o projeto inteiro: id repetido, text_key inexistente, head_id
#                      inexistente e porta morta — a required_flag que nenhum insight concede, que é
#                      um insight que nunca vai aparecer para ninguém.
#
# Os dois saem por print(), então aparecem no visualizador de log do jogo (F5) sem precisar do
# editor aberto. Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao
# jogador — ver docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
class_name InsightDebugReport
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"


# Diagnóstico da cena atual: uma linha por insight de cada fonte registrada, com o motivo exato de
# cada ausência e o vencedor de cada disputa marcado.
static func scene_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var scene_name: String = "?"
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene != null:
		scene_name = tree.current_scene.name
	var sources: Array[InsightSource] = InsightDirector.get_sources()
	lines.append("[Insights] - Diagnóstico da cena \"%s\": %d fonte(s)" % [scene_name, sources.size()])
	if InsightDirector.is_ignoring_gates():
		lines.append("  ATENÇÃO: \"Ignorar portas\" está ligado — tudo aparece aberto.")
	if sources.is_empty():
		lines.append("  Nenhuma InsightSource registrada nesta cena.")
		return "\n".join(lines)

	for source: InsightSource in sources:
		lines.append("  Fonte \"%s\" (jogador no raio: %s)"
			% [source.name, "sim" if source.is_player_in_range() else "não"])
		if source.insights.is_empty():
			lines.append("    (sem nenhum InsightData atribuído)")
			continue
		var winners: Dictionary = _winners_of(source)
		for insight: InsightData in source.insights:
			if insight == null:
				lines.append("    %s (entrada vazia na lista de insights)" % CROSS)
				continue
			lines.append("    %s" % _insight_line(insight, winners))
	return "\n".join(lines)


# Validação em lote de todos os .tres do projeto. Roda em segundos e acha o tipo de erro que
# sobrevive meses: o insight que nunca vai aparecer e cujo sintoma é o mesmo silêncio de todos os
# outros.
static func project_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var insights: Array[InsightData] = InsightCatalog.load_all_insights()
	var heads: Array[HeadData] = InsightCatalog.load_all_heads()
	lines.append("[Insights] - Validação: %d insight(s), %d cabeça(s)" % [insights.size(), heads.size()])

	var head_ids: Dictionary = {}
	for head: HeadData in heads:
		head_ids[head.id] = true
	var id_counts: Dictionary = {}
	var granted_flags: Dictionary = {}
	for insight: InsightData in insights:
		id_counts[insight.id] = int(id_counts.get(insight.id, 0)) + 1
		if insight.grants_flag != &"":
			granted_flags[insight.grants_flag] = true

	var problems: PackedStringArray = PackedStringArray()
	var reported_duplicates: Dictionary = {}
	for insight: InsightData in insights:
		var label: String = String(insight.id) if insight.id != &"" else insight.resource_path
		if insight.id == &"":
			problems.append("%s %s: sem id." % [CROSS, label])
		elif int(id_counts[insight.id]) > 1 and not reported_duplicates.has(insight.id):
			reported_duplicates[insight.id] = true
			problems.append("%s %s: id repetido %d vezes no projeto." % [CROSS, label, id_counts[insight.id]])
		if insight.text_key.is_empty():
			problems.append("%s %s: text_key vazio." % [CROSS, label])
		elif not InsightCatalog.has_translation_key(insight.text_key):
			problems.append("%s %s: text_key \"%s\" não existe no translations.csv." % [CROSS, label, insight.text_key])
		if insight.is_character():
			if insight.head_id == &"":
				problems.append("%s %s: canal de personagem sem head_id." % [CROSS, label])
			elif not head_ids.has(insight.head_id):
				problems.append("%s %s: head_id \"%s\" não corresponde a nenhuma cabeça." % [CROSS, label, insight.head_id])
		for flag: StringName in insight.required_flags:
			if not granted_flags.has(flag):
				problems.append("%s %s: porta morta — a flag \"%s\" não é concedida por nenhum insight." % [CROSS, label, flag])

	for head: HeadData in heads:
		if head.display_name_key.is_empty():
			problems.append("%s cabeça %s: display_name_key vazio." % [CROSS, head.id])
		elif not InsightCatalog.has_translation_key(head.display_name_key):
			problems.append("%s cabeça %s: display_name_key \"%s\" não existe no translations.csv."
				% [CROSS, head.id, head.display_name_key])

	if problems.is_empty():
		lines.append("  %s Nenhum problema encontrado." % CHECK)
	else:
		for problem: String in problems:
			lines.append("  %s" % problem)
	return "\n".join(lines)


# Uma linha de diagnóstico de um insight: ✓ quando ele é o que apareceria agora, ✗ com o motivo
# exato quando não. É a única saída que separa as cinco portas umas das outras.
static func _insight_line(insight: InsightData, winners: Dictionary) -> String:
	var channel_text: String = ("PERSONAGEM/%s" % insight.head_id) if insight.is_character() else "AMBIENTE"
	var reason: String = _closed_reason(insight)
	if not reason.is_empty():
		return "%s %s — %s — %s" % [CROSS, insight.id, channel_text, reason]

	var winner_key: StringName = insight.head_id if insight.is_character() else &""
	var winner: InsightData = winners.get(winner_key, null) as InsightData
	if winner == insight:
		var freshness: String = "novidade" if InsightDirector.is_new(insight) else "já lido, sem novidade nesta fonte"
		return "%s %s — %s — prioridade %s — VENCEDOR (%s)" % [
			CHECK, insight.id, channel_text, _priority_text(insight.priority), freshness
		]
	if not InsightDirector.is_new(insight):
		return "%s %s — %s — já lido (one_shot)" % [CROSS, insight.id, channel_text]
	return "%s %s — %s — perdeu para %s (%s)" % [
		CROSS, insight.id, channel_text,
		winner.id if winner != null else "?",
		_priority_text(winner.priority) if winner != null else "?"
	]


# Motivo pelo qual as portas do insight estão fechadas, ou string vazia quando estão abertas. A
# ordem das checagens é a ordem em que o Director as aplica, para o relatório nunca acusar uma porta
# diferente da que de fato barrou.
static func _closed_reason(insight: InsightData) -> String:
	if InsightDirector.is_ignoring_gates():
		return ""
	if insight.is_character() and not HeadRegistry.has_head(insight.head_id):
		return "cabeça \"%s\" não desbloqueada" % insight.head_id
	for flag: StringName in insight.required_flags:
		if not InsightJournal.has_flag(flag):
			return "falta a flag \"%s\"" % flag
	for flag: StringName in insight.blocked_by_flags:
		if InsightJournal.has_flag(flag):
			return "bloqueado pela flag \"%s\"" % flag
	return ""


# Quem venceria a disputa agora, em cada canal desta fonte: um vencedor para o ambiente e um por
# cabeça. É o mesmo cálculo que o Director usa em jogo, para o relatório não poder discordar dele.
static func _winners_of(source: InsightSource) -> Dictionary:
	var winners: Dictionary = {}
	winners[&""] = InsightDirector.pick_environment(source)
	for insight: InsightData in source.insights:
		if insight == null or not insight.is_character() or winners.has(insight.head_id):
			continue
		winners[insight.head_id] = _pick_character_winner(source, insight.head_id)
	return winners


# Melhor insight de uma cabeça específica dentro da fonte. Repete a regra do Director (novidade
# ganha de relido, depois prioridade) porque o Director expõe a escolha por canal, não por cabeça.
static func _pick_character_winner(source: InsightSource, head_id: StringName) -> InsightData:
	var best_new: InsightData = null
	var best_read: InsightData = null
	for insight: InsightData in source.insights:
		if insight == null or not insight.is_character() or insight.head_id != head_id:
			continue
		if not InsightDirector.is_open(insight):
			continue
		if InsightDirector.is_new(insight):
			if best_new == null or insight.priority > best_new.priority:
				best_new = insight
		elif best_read == null or insight.priority > best_read.priority:
			best_read = insight
	return best_new if best_new != null else best_read


# Nome legível da prioridade, para o relatório dizer "ALTA" em vez de 10.
static func _priority_text(priority: InsightData.Priority) -> String:
	match priority:
		InsightData.Priority.LOW:
			return "BAIXA"
		InsightData.Priority.HIGH:
			return "ALTA"
		_:
			return "NORMAL"
