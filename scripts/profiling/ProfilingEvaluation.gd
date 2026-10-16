# ProfilingEvaluation.gd — A correção de uma página de profiling: quantas lacunas estão erradas,
# quais são, e qual das três mensagens do GDD o jogador vê.
#
# É função pura de propósito: recebe a história e as palavras que estão nas lacunas, e devolve o
# resultado sem tocar em tela, save ou evento. Duas razões práticas:
#
#   - a regra ("tudo certo", "duas ou menos erradas", "várias erradas") é o miolo do sistema e é o
#     que o autoteste confere (ver ProfilingSelfTest), e autoteste não abre tela;
#   - a mesma correção é pedida em dois momentos — a cada palavra solta numa lacuna (pra saber se a
#     página já está completa) e no fechamento (pra marcar a história como resolvida).
#
# A PÁGINA SÓ É CORRIGIDA CHEIA. Com uma lacuna vazia o resultado é INCOMPLETE, e a tela não diz
# nada: o GDD é explícito em que TODAS precisam ser preenchidas pra o jogo avisar se está certo.
#
# O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingEvaluation
extends RefCounted

# INCOMPLETE não é um resultado ruim, é a ausência de resultado: ainda falta lacuna pra preencher.
enum Result { INCOMPLETE, ALL_CORRECT, FEW_WRONG, MANY_WRONG }

# Até quantas palavras erradas contam como "duas ou menos" (a mensagem amarela). Acima disso é a
# mensagem vermelha. O valor do GDD é 2; quem quiser balancear passa outro em evaluate(), e é o que
# a página do profiling faz com o @export dela.
const FEW_WRONG_LIMIT: int = 2

# Chaves das três mensagens que aparecem acima da página. Texto de jogador, então chave de CSV.
const MESSAGE_KEYS: Dictionary = {
	Result.ALL_CORRECT: "PROFILING_RESULT_ALL_CORRECT",
	Result.FEW_WRONG: "PROFILING_RESULT_FEW_WRONG",
	Result.MANY_WRONG: "PROFILING_RESULT_MANY_WRONG",
}

var result: Result = Result.INCOMPLETE
# Os índices das lacunas com palavra errada, em ordem. A tela usa pra decidir onde NÃO pôr o
# checkmark verde; o log usa pra dizer o que o jogador errou.
var wrong_indices: PackedInt32Array = []
# Os índices das lacunas ainda vazias, em ordem.
var empty_indices: PackedInt32Array = []
var blank_count: int = 0


# Corrige uma página. "fills" é uma palavra por lacuna, na ordem dos índices, com string vazia na
# lacuna não preenchida — exatamente o formato que o ProfilingJournal guarda e que o save carrega.
#
# Lista de tamanho diferente do da história não é erro: sobra é ignorada e falta conta como lacuna
# vazia. É o que faz um save antigo, de uma época em que a história tinha menos lacunas, abrir
# incompleto em vez de quebrar a tela.
static func evaluate(story: ProfilingStory, fills: PackedStringArray,
		few_wrong_limit: int = FEW_WRONG_LIMIT) -> ProfilingEvaluation:
	var evaluation: ProfilingEvaluation = ProfilingEvaluation.new()
	if story == null:
		return evaluation

	evaluation.blank_count = story.get_blank_count()
	for index: int in evaluation.blank_count:
		var filled: StringName = StringName(fills[index]) if index < fills.size() else &""
		if filled == &"":
			evaluation.empty_indices.append(index)
		elif filled != story.get_expected_word_id(index):
			evaluation.wrong_indices.append(index)

	# Uma história sem lacuna nenhuma não pode ser declarada "toda correta": ela é um erro de
	# preenchimento do design (ProfilingStory.collect_issues acusa), e resolvê-la sozinha daria ao
	# jogador uma emoção de graça.
	if evaluation.blank_count == 0 or not evaluation.empty_indices.is_empty():
		evaluation.result = Result.INCOMPLETE
	elif evaluation.wrong_indices.is_empty():
		evaluation.result = Result.ALL_CORRECT
	elif evaluation.wrong_indices.size() <= few_wrong_limit:
		evaluation.result = Result.FEW_WRONG
	else:
		evaluation.result = Result.MANY_WRONG

	return evaluation


# Diz se a página está cheia — o que, pelo GDD, é a condição pra o jogo avisar qualquer coisa.
func is_complete() -> bool:
	return result != Result.INCOMPLETE


# Diz se a história foi resolvida por esta correção.
func is_solved() -> bool:
	return result == Result.ALL_CORRECT


# Diz se a lacuna tem a palavra certa. A tela pergunta isto por lacuna pra pôr o checkmark verde.
func is_blank_correct(index: int) -> bool:
	return not wrong_indices.has(index) and not empty_indices.has(index)


# A chave da mensagem que aparece acima da página, ou vazia enquanto a página está incompleta
# (nesse caso não há mensagem nenhuma: o GDD só avisa com tudo preenchido).
func get_message_key() -> String:
	return String(MESSAGE_KEYS.get(result, ""))


# Quantas lacunas estão preenchidas. Usada no log e no relatório de debug.
func get_filled_count() -> int:
	return blank_count - empty_indices.size()


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "ProfilingEvaluation(%s, %d/%d preenchidas, %d errada(s))" % [
		Result.keys()[result], get_filled_count(), blank_count, wrong_indices.size()]
