# ProfilingSelfTest.gd — Autoteste da lógica do profiling: a correção da página, o parser do texto
# com lacunas, as regras do diário e o agrupamento das palavras em conjunto.
#
# A parte que dá bug num sistema como este não é a tela: é a aritmética silenciosa. Uma palavra que
# fica em duas lacunas ao mesmo tempo, um "duas ou menos erradas" que dispara com três, uma emoção
# escolhida no sonho que entra em vigor no mesmo dia. Nada disso quebra nada visível — só deixa o
# jogo errado. Este autoteste confere essas regras sem abrir tela e sem tocar em arquivo do design.
#
# COMO O ESTADO DO JOGADOR É PROTEGIDO: os casos que mexem no ProfilingJournal usam o diário DE
# VERDADE (é a regra real que interessa, não uma cópia dela), então o autoteste guarda o estado
# antes, desliga o autosave e devolve o original no fim. Os ids de teste são prefixados por
# "__selftest_" e não existem em nenhum .tres.
#
# Duas portas de entrada: a ação "Autoteste do profiling" no menu de debug (F4) e o script de linha
# de comando tests/run_profiling_self_test.gd, que sai com código de erro quando algo falha.
#
# Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao jogador — ver
# docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
class_name ProfilingSelfTest
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"
const SKIP: String = "—"

const TEST_PREFIX: String = "__selftest_"

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()


# Roda todos os casos e devolve o diário ao estado em que estava. Pode ser chamado de novo: cada
# execução começa zerada.
func run() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()

	var snapshot: Dictionary = ProfilingJournal.to_dict()
	var was_autosaving: bool = ProfilingJournal.autosave_enabled
	# Autosave desligado por garantia: nenhum caso deveria gravar, mas um caso novo que resolva uma
	# história pelo caminho normal escreveria o estado de teste no save do jogador.
	ProfilingJournal.autosave_enabled = false

	_test_evaluation()
	_test_evaluation_limits()
	_test_template_parser()
	_test_story_issues()
	_test_blanks()
	_test_marks()
	_test_scheduled_emotion()
	_test_pairs()
	_test_markup_groups()

	ProfilingJournal.from_dict(snapshot)
	ProfilingJournal.autosave_enabled = was_autosaving


# Relatório da última execução, pronto para print(): o resumo na primeira linha e um ✓/✗ por caso.
func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[Profiling] - Autoteste do profiling: %d ok, %d falha(s)" % [
		passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# ------------------------------------------------------------------------------------
# A correção da página
# ------------------------------------------------------------------------------------

# As três mensagens do GDD e a página incompleta.
func _test_evaluation() -> void:
	var story: ProfilingStory = _make_story(4)

	var incomplete: ProfilingEvaluation = ProfilingEvaluation.evaluate(story,
		_fills(["w0", "w1", "w2", ""]))
	_expect_equal("Lacuna vazia deixa a página incompleta",
		incomplete.result, ProfilingEvaluation.Result.INCOMPLETE)
	_expect("Página incompleta não tem mensagem", incomplete.get_message_key().is_empty())
	_expect_equal("Página incompleta conta as preenchidas", incomplete.get_filled_count(), 3)

	var correct: ProfilingEvaluation = ProfilingEvaluation.evaluate(story,
		_fills(["w0", "w1", "w2", "w3"]))
	_expect_equal("Tudo certo", correct.result, ProfilingEvaluation.Result.ALL_CORRECT)
	_expect("Tudo certo resolve a história", correct.is_solved())

	var one_wrong: ProfilingEvaluation = ProfilingEvaluation.evaluate(story,
		_fills(["w0", "w1", "w2", "outra"]))
	_expect_equal("Uma errada é \"duas ou menos\"",
		one_wrong.result, ProfilingEvaluation.Result.FEW_WRONG)

	# Duas palavras certas trocadas de lugar são DUAS erradas: a correção é por lacuna, e não por
	# "usou as palavras certas".
	var swapped: ProfilingEvaluation = ProfilingEvaluation.evaluate(story,
		_fills(["w1", "w0", "w2", "w3"]))
	_expect_equal("Duas palavras trocadas de lugar são duas erradas",
		swapped.wrong_indices.size(), 2)
	_expect_equal("Duas erradas é \"duas ou menos\"",
		swapped.result, ProfilingEvaluation.Result.FEW_WRONG)

	var many: ProfilingEvaluation = ProfilingEvaluation.evaluate(story,
		_fills(["x", "y", "z", "w3"]))
	_expect_equal("Três erradas é \"várias incorretas\"",
		many.result, ProfilingEvaluation.Result.MANY_WRONG)
	_expect("A lacuna certa é reconhecida no meio das erradas", many.is_blank_correct(3))
	_expect("A lacuna errada não é reconhecida como certa", not many.is_blank_correct(0))


# Os casos de borda da correção: história vazia, lista de preenchimento fora de tamanho e limite de
# "poucas erradas" mexido pelo balanceamento.
func _test_evaluation_limits() -> void:
	var empty_story: ProfilingStory = _make_story(0)
	_expect_equal("História sem lacuna nunca está correta",
		ProfilingEvaluation.evaluate(empty_story, _fills([])).result,
		ProfilingEvaluation.Result.INCOMPLETE)

	var story: ProfilingStory = _make_story(3)
	_expect_equal("Lista de preenchimento menor que a história conta como lacuna vazia",
		ProfilingEvaluation.evaluate(story, _fills(["w0"])).result,
		ProfilingEvaluation.Result.INCOMPLETE)
	_expect_equal("Lista de preenchimento maior que a história ignora a sobra",
		ProfilingEvaluation.evaluate(story, _fills(["w0", "w1", "w2", "sobra"])).result,
		ProfilingEvaluation.Result.ALL_CORRECT)

	_expect_equal("Com limite 0, uma errada já é \"várias incorretas\"",
		ProfilingEvaluation.evaluate(story, _fills(["w0", "w1", "errada"]), 0).result,
		ProfilingEvaluation.Result.MANY_WRONG)


# ------------------------------------------------------------------------------------
# O texto com lacunas
# ------------------------------------------------------------------------------------

# O parser do texto: onde estão as lacunas e onde está o texto.
func _test_template_parser() -> void:
	var story: ProfilingStory = _make_story(3)
	var text: String = "{0} {1} matou o {2} na festa"

	# "{0}" + " " + "{1}" + " matou o " + "{2}" + " na festa" = 6 pedaços: três lacunas e três
	# trechos de texto.
	var segments: Array[Dictionary] = story.build_segments(text)
	_expect_equal("O texto vira trechos e lacunas", segments.size(), 6)
	_expect_equal("A primeira lacuna é a {0}", int(segments[0].get("blank", -1)), 0)
	_expect_equal("Entre duas lacunas fica o trecho de texto",
		String(segments[1].get("text", "")), " ")

	var indices: PackedInt32Array = story.get_template_blank_indices(text)
	_expect_equal("As três lacunas são encontradas", indices.size(), 3)
	_expect_equal("As lacunas saem na ordem do texto", "%s" % [indices], "[0, 1, 2]")

	# A ordem das lacunas no TEXTO não precisa ser a da solução: é isso que deixa a tradução
	# reordenar a frase sem mexer no conteúdo.
	var reordered: PackedInt32Array = story.get_template_blank_indices("The {2} killed {0} {1}")
	_expect_equal("A tradução pode reordenar as lacunas", "%s" % [reordered], "[2, 0, 1]")

	_expect_equal("Texto sem lacuna não vira lacuna nenhuma",
		story.get_template_blank_indices("nada aqui").size(), 0)


# O que o resumo do Inspector acusa numa história mal preenchida.
func _test_story_issues() -> void:
	var story: ProfilingStory = ProfilingStory.new()
	var issues: PackedStringArray = story.collect_issues()
	_expect("História vazia acusa problemas", issues.size() >= 4)
	_expect("História vazia acusa a falta de emoção", _has_issue(issues, "Sem emoção"))
	_expect("História vazia acusa a falta de solução", _has_issue(issues, "Sem solução"))

	var filled: ProfilingStory = _make_story(2)
	filled.solution[1] = null
	_expect("Palavra vazia na solução é acusada",
		_has_issue(filled.collect_issues(), "lacuna {1} está vazia"))


# ------------------------------------------------------------------------------------
# O diário
# ------------------------------------------------------------------------------------

# As regras das lacunas: preencher, mover, esvaziar e achar onde uma palavra está.
func _test_blanks() -> void:
	var story_id: StringName = StringName(TEST_PREFIX + "story_blanks")

	ProfilingJournal.set_blank(story_id, 0, &"faca", 3)
	ProfilingJournal.set_blank(story_id, 2, &"vinho", 3)
	_expect_equal("A palavra fica na lacuna em que foi solta",
		ProfilingJournal.get_fills(story_id, 3)[0], "faca")
	_expect_equal("A lacuna não preenchida volta vazia",
		ProfilingJournal.get_fills(story_id, 3)[1], "")
	_expect_equal("A lacuna de uma palavra é encontrada pelo id",
		ProfilingJournal.find_blank_with_word(story_id, &"vinho", 3), 2)

	# A mesma palavra não pode estar em duas lacunas: soltar de novo MOVE.
	ProfilingJournal.set_blank(story_id, 1, &"faca", 3)
	_expect_equal("Soltar a mesma palavra em outra lacuna a move",
		ProfilingJournal.find_blank_with_word(story_id, &"faca", 3), 1)
	_expect_equal("A lacuna de onde ela saiu fica vazia",
		ProfilingJournal.get_fills(story_id, 3)[0], "")

	ProfilingJournal.clear_blank(story_id, 1, 3)
	_expect_equal("Esvaziar a lacuna tira a palavra dela",
		ProfilingJournal.find_blank_with_word(story_id, &"faca", 3), -1)

	# Uma história que ganhou lacunas depois de alguém já ter jogado não pode quebrar a página.
	_expect_equal("O progresso antigo cabe numa história que cresceu",
		ProfilingJournal.get_fills(story_id, 5).size(), 5)

	var npc_id: StringName = StringName(TEST_PREFIX + "npc_solved")
	ProfilingJournal.mark_story_solved(npc_id, story_id)
	_expect("A história marcada fica resolvida", ProfilingJournal.is_story_solved(story_id))
	_expect("NPC sem perfil nunca está completo", not ProfilingJournal.is_profile_complete(npc_id))


# As marcas de lixo e estrela, e o clique que as remove.
func _test_marks() -> void:
	var npc_id: StringName = StringName(TEST_PREFIX + "npc_marks")
	var word_id: StringName = StringName(TEST_PREFIX + "word")

	_expect_equal("Palavra sem marca volta NONE",
		ProfilingJournal.get_mark(npc_id, word_id), GlossaryMark.Kind.NONE)

	ProfilingJournal.set_mark(npc_id, word_id, GlossaryMark.Kind.TRASH)
	_expect_equal("A marca de lixo é guardada",
		ProfilingJournal.get_mark(npc_id, word_id), GlossaryMark.Kind.TRASH)

	ProfilingJournal.set_mark(npc_id, word_id, GlossaryMark.Kind.STAR)
	_expect_equal("A estrela substitui o lixo",
		ProfilingJournal.get_mark(npc_id, word_id), GlossaryMark.Kind.STAR)

	ProfilingJournal.set_mark(npc_id, word_id, GlossaryMark.Kind.STAR)
	_expect_equal("Escolher a mesma marca de novo a remove",
		ProfilingJournal.get_mark(npc_id, word_id), GlossaryMark.Kind.NONE)


# A emoção escolhida no sonho só vale a partir do dia seguinte.
#
# O teste NÃO mexe no relógio: ele monta o diário com from_dict, dizendo em que dia a escolha começa
# a valer, e pergunta a emoção vigente. Assim o caso roda igual às 03:00 de um sonho e às 14:00 de
# uma terça, sem disparar evento de virada de dia em cima do jogo.
func _test_scheduled_emotion() -> void:
	var npc_id: String = TEST_PREFIX + "npc_emotion"
	var definition: NPCDefinition = NPCDefinition.new()
	definition.id = StringName(npc_id)
	definition.starting_slot = NPCDefinition.EmotionSlot.NEUTRAL

	var snapshot: Dictionary = ProfilingJournal.to_dict()
	var today: int = GameClock.time.get_day()

	# Escolha que ainda não venceu: hoje ele continua como estava.
	ProfilingJournal.from_dict({
		ProfilingJournal.EMOTIONS_KEY: {
			npc_id: {
				ProfilingJournal.NEXT_SLOT_KEY: NPCDefinition.EmotionSlot.SECOND,
				ProfilingJournal.NEXT_DAY_KEY: today + 1,
			}
		}
	})
	_expect_equal("A emoção escolhida hoje não vale hoje",
		ProfilingJournal.resolve_emotion_slot(definition), NPCDefinition.EmotionSlot.NEUTRAL)
	_expect_equal("A escolha pendente é visível na tela do espírito",
		ProfilingJournal.get_scheduled_slot(StringName(npc_id)), NPCDefinition.EmotionSlot.SECOND)

	# O dia chegou: a escolha entra em vigor e deixa de estar pendente.
	ProfilingJournal.from_dict({
		ProfilingJournal.EMOTIONS_KEY: {
			npc_id: {
				ProfilingJournal.NEXT_SLOT_KEY: NPCDefinition.EmotionSlot.FIRST,
				ProfilingJournal.NEXT_DAY_KEY: today,
			}
		}
	})
	_expect_equal("No dia seguinte o NPC acorda na emoção escolhida",
		ProfilingJournal.resolve_emotion_slot(definition), NPCDefinition.EmotionSlot.FIRST)
	_expect_equal("A escolha aplicada deixa de estar pendente",
		ProfilingJournal.get_scheduled_slot(StringName(npc_id)), -1)
	_expect_equal("A emoção aplicada continua valendo nos dias seguintes",
		ProfilingJournal.resolve_emotion_slot(definition), NPCDefinition.EmotionSlot.FIRST)

	# Sem escolha nenhuma, vale a emoção inicial do .tres.
	ProfilingJournal.from_dict({})
	definition.starting_slot = NPCDefinition.EmotionSlot.SECOND
	_expect_equal("Sem escolha, vale a emoção inicial do NPC",
		ProfilingJournal.resolve_emotion_slot(definition), NPCDefinition.EmotionSlot.SECOND)

	ProfilingJournal.from_dict(snapshot)


# Palavras em conjunto: descobrir uma traz a outra. O caso roda contra o conteúdo do projeto, porque
# é o par DE VERDADE que interessa — se nenhuma palavra do projeto tem par, não há o que conferir.
func _test_pairs() -> void:
	var paired: GlossaryWord = null
	for word: GlossaryWord in ProfilingCatalog.load_all_words():
		if not word.paired_words.is_empty() and word.paired_words[0] != null:
			paired = word
			break

	if paired == null:
		_skip("Palavras em conjunto: nenhuma palavra do projeto tem par")
		return

	var owners: Array[NPCProfile] = ProfilingCatalog.find_profiles_with_word(paired.id)
	if owners.is_empty():
		_skip("Palavras em conjunto: a palavra com par não está no pool de nenhum NPC")
		return

	var npc_id: StringName = owners[0].npc_id
	var partner: GlossaryWord = paired.paired_words[0]
	ProfilingJournal.from_dict({})

	_expect("Descobrir uma palavra em conjunto funciona",
		ProfilingJournal.discover_word(paired.id, npc_id))
	_expect("A palavra em conjunto traz o par junto",
		ProfilingJournal.is_word_discovered(npc_id, partner.id))
	_expect("Descobrir a mesma palavra de novo não é novidade",
		not ProfilingJournal.discover_word(paired.id, npc_id))
	_expect("As duas palavras contam no \"23/36\"",
		ProfilingJournal.count_discovered_words(npc_id) >= 2)


# O agrupamento da marcação do GDD: "[A]/[B]" é um clique só, "[A] e [B]" são dois.
func _test_markup_groups() -> void:
	var regex: RegEx = RegEx.create_from_string(ClickableWordText.MARKUP_PATTERN)

	var grouped: String = "[MARCOS]/[CASTRO] chegou"
	var grouped_payloads: PackedStringArray = ClickableWordText.build_payloads(
		grouped, regex.search_all(grouped))
	_expect_equal("Duas marcações juntas viram um clique só",
		grouped_payloads[0], "marcos|castro")
	_expect_equal("As duas metades do par têm o mesmo clique",
		grouped_payloads[0], grouped_payloads[1])

	var apart: String = "achei uma [FACA] e uma [TESOURA]"
	var apart_payloads: PackedStringArray = ClickableWordText.build_payloads(
		apart, regex.search_all(apart))
	_expect_equal("Marcações soltas são cliques separados", apart_payloads[0], "faca")
	_expect_equal("Cada marcação solta descobre só a sua", apart_payloads[1], "tesoura")

	var trio: String = "[A]/[B]/[C]"
	var trio_payloads: PackedStringArray = ClickableWordText.build_payloads(
		trio, regex.search_all(trio))
	_expect_equal("Um grupo pode ter mais de duas palavras", trio_payloads[2], "a|b|c")


# ------------------------------------------------------------------------------------
# Ferramentas dos casos
# ------------------------------------------------------------------------------------

# Uma história em memória, com N lacunas e a solução "w0", "w1"... Nenhum arquivo é tocado, e os ids
# não existem em nenhum .tres do projeto.
func _make_story(blank_count: int) -> ProfilingStory:
	var story: ProfilingStory = ProfilingStory.new()
	story.id = StringName(TEST_PREFIX + "story_%d" % blank_count)
	story.template_key = TEST_PREFIX + "template"
	story.resolved_text_key = TEST_PREFIX + "resolved"

	var solution: Array[GlossaryWord] = []
	for index: int in blank_count:
		var word: GlossaryWord = GlossaryWord.new()
		word.id = StringName("w%d" % index)
		solution.append(word)
	story.solution = solution
	return story


# Converte uma lista de ids num PackedStringArray de preenchimento, no formato que a correção espera.
func _fills(values: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		result.append(str(value))
	return result


# Diz se alguma das frases de problema contém um trecho. Os textos são de ferramenta e podem ser
# reescritos, então o caso procura o miolo da frase, não a frase inteira.
func _has_issue(issues: PackedStringArray, fragment: String) -> bool:
	for issue: String in issues:
		if issue.contains(fragment):
			return true
	return false


func _expect(label: String, condition: bool) -> void:
	if condition:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
	else:
		failed_count += 1
		_lines.append("  %s %s" % [CROSS, label])


# Compara dois valores e, na falha, MOSTRA os dois: um "✗ duas erradas" sem os números obriga quem
# está consertando a reabrir o caso pra descobrir o que veio.
func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
	else:
		failed_count += 1
		_lines.append("  %s %s (veio %s, esperado %s)" % [CROSS, label, actual, expected])


# Caso que não pôde rodar por falta de conteúdo no projeto. Não conta como falha (o código está
# certo; o que falta é conteúdo), mas aparece no relatório pra ninguém achar que ele passou.
func _skip(label: String) -> void:
	_lines.append("  %s %s (caso pulado)" % [SKIP, label])
