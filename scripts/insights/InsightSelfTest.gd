# InsightSelfTest.gd — Autoteste da regra de escolha dos insights.
#
# A validação em lote (InsightDebugReport) confere o CONTEÚDO: ids, chaves, cabeças, portas mortas.
# Isto confere a LÓGICA: novidade ganha de relido, prioridade desempata, porta fechada não desenha
# orbe. É a parte mais sujeita a regressão silenciosa — uma mudança errada no InsightDirector não
# quebra nada visível, só faz um orbe sumir numa cena que ninguém está olhando.
#
# Roda contra o InsightDirector de verdade (pick_best, is_open, is_new, candidate_beats), e não contra
# uma cópia da regra. Para isso usa o diário real: guarda o estado antes, monta o estado de cada caso
# com from_dict() e devolve o original no fim. Os insights de teste são criados em memória, com ids
# prefixados por "__selftest_", e nunca tocam o disco nem a cena.
#
# Duas portas de entrada: a ação "Autoteste da escolha" no menu de debug (F4) e o script de linha de
# comando tests/run_insight_self_test.gd, que sai com código de erro quando algo falha.
#
# Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao jogador — ver
# docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
class_name InsightSelfTest
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"
const TEST_PREFIX: String = "__selftest_"
# Cabeça que não existe em nenhum .tres: has_head() é falso para ela mesmo com "Desbloquear todas as
# cabeças" ligado, então serve de cabeça bloqueada garantida.
const LOCKED_HEAD_ID: StringName = &"__selftest_locked_head"

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()


# Roda todos os casos e devolve o jogo ao estado em que estava. Pode ser chamado de novo: cada
# execução começa zerada.
func run() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()

	var journal_snapshot: Dictionary = InsightJournal.to_dict()
	var was_autosaving: bool = InsightJournal.autosave_enabled
	var was_ignoring_gates: bool = InsightDirector.is_ignoring_gates()
	# Autosave desligado por garantia: nenhum caso deveria gravar, mas um caso novo que conceda flag
	# pelo caminho normal escreveria o estado de teste no save do jogador.
	InsightJournal.autosave_enabled = false
	InsightDirector.set_ignoring_gates(false)

	_test_selection()
	_test_gates()
	_test_novelty()
	_test_offer_tiebreak()

	InsightJournal.from_dict(journal_snapshot)
	InsightJournal.autosave_enabled = was_autosaving
	InsightDirector.set_ignoring_gates(was_ignoring_gates)


# Relatório da última execução, pronto para print(): o resumo na primeira linha e um ✓/✗ por caso.
func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[Insights] - Autoteste da escolha: %d ok, %d falha(s)" % [passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# Regra de escolha entre insights disponíveis na mesma fonte.
func _test_selection() -> void:
	var high: InsightData = _make_insight("high", InsightData.Priority.HIGH)
	var low: InsightData = _make_insight("low", InsightData.Priority.LOW)
	var normal: InsightData = _make_insight("normal", InsightData.Priority.NORMAL)
	var environment: InsightData.Channel = InsightData.Channel.ENVIRONMENT

	_set_state([high.id], [])
	_expect_pick("Novidade ganha de relido, mesmo com prioridade menor",
		InsightDirector.pick_best(_list([high, low]), environment, &""), low)

	_set_state([], [])
	_expect_pick("Entre novidades, ganha a prioridade mais alta",
		InsightDirector.pick_best(_list([normal, high]), environment, &""), high)

	_set_state([high.id, low.id], [])
	_expect_pick("Entre relidos, ganha a prioridade mais alta",
		InsightDirector.pick_best(_list([low, high]), environment, &""), high)

	_set_state([], [])
	var character: InsightData = _make_insight("character", InsightData.Priority.HIGH, InsightData.Channel.CHARACTER)
	character.head_id = LOCKED_HEAD_ID
	_expect_pick("Canal errado e entrada vazia na lista são ignorados",
		InsightDirector.pick_best(_list([null, character]), environment, &""), null)

	var unlocked_head: StringName = _first_unlocked_head()
	if unlocked_head == &"":
		_skip("No canal de personagem, só a cabeça pedida conta", "nenhuma cabeça desbloqueada")
		return
	var spoken: InsightData = _make_insight("spoken", InsightData.Priority.NORMAL, InsightData.Channel.CHARACTER)
	spoken.head_id = unlocked_head
	_expect_pick("No canal de personagem, só a cabeça pedida conta",
		InsightDirector.pick_best(_list([spoken]), InsightData.Channel.CHARACTER, LOCKED_HEAD_ID), null)
	_expect_pick("No canal de personagem, a cabeça pedida é encontrada",
		InsightDirector.pick_best(_list([spoken]), InsightData.Channel.CHARACTER, unlocked_head), spoken)


# Portas: flags exigidas, flags que bloqueiam, cabeças e o bypass de debug.
func _test_gates() -> void:
	var environment: InsightData.Channel = InsightData.Channel.ENVIRONMENT
	var required_flag: StringName = StringName(TEST_PREFIX + "required_flag")
	var blocking_flag: StringName = StringName(TEST_PREFIX + "blocking_flag")

	var gated: InsightData = _make_insight("gated", InsightData.Priority.HIGH)
	gated.required_flags = [required_flag]
	var open: InsightData = _make_insight("open", InsightData.Priority.LOW)

	_set_state([], [])
	_expect_pick("Porta fechada nunca vence, nem com prioridade maior",
		InsightDirector.pick_best(_list([gated, open]), environment, &""), open)
	_expect_pick("Fonte só com portas fechadas não desenha orbe",
		InsightDirector.pick_best(_list([gated]), environment, &""), null)

	_set_state([], [required_flag])
	_expect_pick("Flag concedida abre a porta",
		InsightDirector.pick_best(_list([gated, open]), environment, &""), gated)

	var blocked: InsightData = _make_insight("blocked", InsightData.Priority.NORMAL)
	blocked.blocked_by_flags = [blocking_flag]
	_set_state([], [])
	_expect_true("Sem a flag que bloqueia, a porta está aberta", InsightDirector.is_open(blocked))
	_set_state([], [blocking_flag])
	_expect_true("blocked_by_flags fecha a porta", not InsightDirector.is_open(blocked))

	var locked_character: InsightData = _make_insight("locked_character", InsightData.Priority.NORMAL, InsightData.Channel.CHARACTER)
	locked_character.head_id = LOCKED_HEAD_ID
	_set_state([], [])
	_expect_true("Cabeça bloqueada fecha o canal de personagem", not InsightDirector.is_open(locked_character))

	var unlocked_head: StringName = _first_unlocked_head()
	if unlocked_head == &"":
		_skip("Cabeça desbloqueada abre o canal de personagem", "nenhuma cabeça desbloqueada")
	else:
		var unlocked_character: InsightData = _make_insight("unlocked_character", InsightData.Priority.NORMAL, InsightData.Channel.CHARACTER)
		unlocked_character.head_id = unlocked_head
		_expect_true("Cabeça desbloqueada abre o canal de personagem", InsightDirector.is_open(unlocked_character))

	_set_state([], [])
	InsightDirector.set_ignoring_gates(true)
	_expect_true("\"Ignorar portas\" abre porta de flag e de cabeça",
		InsightDirector.is_open(gated) and InsightDirector.is_open(locked_character))
	InsightDirector.set_ignoring_gates(false)


# Novidade: one_shot e leitura.
func _test_novelty() -> void:
	var one_shot: InsightData = _make_insight("one_shot", InsightData.Priority.NORMAL)
	var repeatable: InsightData = _make_insight("repeatable", InsightData.Priority.NORMAL)
	repeatable.one_shot = false
	var closed: InsightData = _make_insight("closed", InsightData.Priority.NORMAL)
	closed.required_flags = [StringName(TEST_PREFIX + "missing_flag")]

	_set_state([], [])
	_expect_true("Insight nunca lido é novidade", InsightDirector.is_new(one_shot))
	_expect_true("Insight fechado nunca é novidade", not InsightDirector.is_new(closed))

	_set_state([one_shot.id, repeatable.id], [])
	_expect_true("one_shot lido deixa de ser novidade", not InsightDirector.is_new(one_shot))
	_expect_true("Sem one_shot, continua novidade depois de lido", InsightDirector.is_new(repeatable))


# Desempate entre ofertas da mesma cabeça na órbita.
func _test_offer_tiebreak() -> void:
	var high: InsightData = _make_insight("offer_high", InsightData.Priority.HIGH)
	var low: InsightData = _make_insight("offer_low", InsightData.Priority.LOW)
	var first_by_id: InsightData = _make_insight("offer_a", InsightData.Priority.NORMAL)
	var second_by_id: InsightData = _make_insight("offer_b", InsightData.Priority.NORMAL)

	var new_low: InsightOffer = InsightOffer.new(LOCKED_HEAD_ID, low, null, true)
	var read_high: InsightOffer = InsightOffer.new(LOCKED_HEAD_ID, high, null, false)
	_expect_true("Oferta nova ganha de relida com prioridade maior",
		InsightDirector.candidate_beats(new_low, read_high) and not InsightDirector.candidate_beats(read_high, new_low))

	var new_high: InsightOffer = InsightOffer.new(LOCKED_HEAD_ID, high, null, true)
	_expect_true("Entre ofertas novas, ganha a prioridade mais alta",
		InsightDirector.candidate_beats(new_high, new_low) and not InsightDirector.candidate_beats(new_low, new_high))

	var offer_a: InsightOffer = InsightOffer.new(LOCKED_HEAD_ID, first_by_id, null, true)
	var offer_b: InsightOffer = InsightOffer.new(LOCKED_HEAD_ID, second_by_id, null, true)
	_expect_true("Empate total é resolvido pelo id, igual nos dois sentidos",
		InsightDirector.candidate_beats(offer_a, offer_b) and not InsightDirector.candidate_beats(offer_b, offer_a))


# Monta um insight de teste em memória. Nunca é salvo: existe só durante o caso.
func _make_insight(suffix: String, priority: InsightData.Priority,
		channel: InsightData.Channel = InsightData.Channel.ENVIRONMENT) -> InsightData:
	var insight: InsightData = InsightData.new()
	insight.id = StringName(TEST_PREFIX + suffix)
	insight.channel = channel
	insight.priority = priority
	return insight


# Converte uma lista solta no Array tipado que pick_best() recebe. Aceita null de propósito: a lista
# de insights de uma fonte pode ter entrada vazia, e a regra precisa sobreviver a isso.
func _list(items: Array) -> Array[InsightData]:
	var result: Array[InsightData] = []
	for item: Variant in items:
		result.append(item as InsightData)
	return result


# Define exatamente quais insights estão lidos e quais flags estão concedidas. Pelo from_dict(), e
# não por mark_read()/grant_flag(), para o estado de cada caso ser total — nada sobra do caso anterior
# — e para não imprimir uma linha de "flag concedida" por caso no meio do relatório.
func _set_state(read_ids: Array[StringName], flags: Array[StringName]) -> void:
	var read_list: Array[String] = []
	for insight_id: StringName in read_ids:
		read_list.append(String(insight_id))
	var flag_list: Array[String] = []
	for flag: StringName in flags:
		flag_list.append(String(flag))
	InsightJournal.from_dict({ InsightJournal.READ_KEY: read_list, InsightJournal.FLAGS_KEY: flag_list })


# Primeira cabeça que o jogador tem agora, ou vazio. Os casos de cabeça desbloqueada dependem do
# elenco do projeto, então viram "pulado" em vez de falha quando não há nenhuma.
func _first_unlocked_head() -> StringName:
	var unlocked: Array[StringName] = HeadRegistry.get_unlocked_ids()
	return unlocked[0] if not unlocked.is_empty() else &""


# Confere o insight escolhido pela regra.
func _expect_pick(label: String, actual: InsightData, expected: InsightData) -> void:
	_record(label, actual == expected, "esperado %s, veio %s" % [_describe(expected), _describe(actual)])


# Confere uma condição.
func _expect_true(label: String, condition: bool) -> void:
	_record(label, condition, "condição falsa")


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


# Id do insight para a mensagem de falha, sem o prefixo de teste.
func _describe(insight: InsightData) -> String:
	if insight == null:
		return "nenhum"
	return "\"%s\"" % String(insight.id).trim_prefix(TEST_PREFIX)
