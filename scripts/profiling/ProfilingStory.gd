## ProfilingStory - a história por trás de UMA emoção de um NPC: o texto com lacunas, a solução e o
## texto que substitui tudo quando o jogador acerta.
##
## COMO USAR: um .tres por história em res://resources/profiling/historias/, apontado na lista
## "Stories" do perfil do NPC (ver NPCProfile.gd). Uma história por emoção do NPC — a emoção aqui é
## o que liga a história ao slot certo na tela do espírito.
##
## O TEXTO COM LACUNAS: fica no CSV, nunca aqui, e as lacunas são escritas como {0}, {1}, {2}...
## Exemplo de valor no translations.csv:
##
##     {0} {1} queria {2} {3} morta, e então {4} {5} envenenou o {6} e escondeu a chave numa {7}
##
## O ÍNDICE É PROPOSITAL, e não um "preenche na ordem": em inglês a ordem das palavras da frase muda,
## e com índice a tradução reordena as lacunas sem mexer na solução. A lacuna {3} sempre espera a
## quarta palavra de "Solution", em qualquer idioma.
##
## Quebra de linha no CSV é "\n" — a página do profiling do GDD tem parágrafos separados.
##
## A SOLUÇÃO é a lista de palavras esperadas, na ordem dos índices: solution[0] é a palavra da lacuna
## {0}. A quantidade de lacunas do texto e o tamanho desta lista TÊM que bater, e o campo "resumo"
## aqui embaixo acusa quando não batem.
##
## MÚSICA: o GDD pede uma música curta quando a história é acertada. Não há música no projeto ainda,
## então o ponto onde ela tocaria está marcado em ProfilingScreen.gd (procure por "MÚSICA") — nada
## aqui.
##
## DIÁRIO: o GDD manda a história resolvida pro diário do jogador. O diário também não existe ainda;
## o campo journal_entry_key já guarda o texto que vai pra lá, e o gancho é
## ProfilingJournal.mark_story_solved (ver docs/sistema_de_profiling.md, "O que ainda não existe").
##
## O guia completo está em docs/sistema_de_profiling.md.
@tool
class_name ProfilingStory
extends Resource

## Espaço para constantes

# Uma lacuna no texto: "{0}", "{12}". O parser roda a cada montagem de página e a cada resumo do
# Inspector, sempre com este mesmo padrão.
const BLANK_PATTERN: String = "\\{(\\d+)\\}"

## Espaço para variáveis exportadas

## Identificador estável da história. É a chave do progresso no save (quais lacunas estão
## preenchidas, se já foi resolvida), então MUDAR ESTE ID DESCARTA O PROGRESSO de quem já jogou.
@export var id: StringName = &"":
	set(value):
		id = value
		_refresh_summary()

## A emoção a que esta história pertence. É o que faz a história aparecer atrás do INVESTIGAR da
## emoção certa na tela do espírito — e é por isso que o sistema não precisa de "história 1" e
## "história 2": ele compara com as emoções que o NPC tem (ver NPCDefinition.get_emotion).
@export var emotion: EmotionDefinition:
	set(value):
		emotion = value
		_refresh_summary()

@export_group("Texto")

## Chave do texto com lacunas, em translations/translations.csv. Ver o bloco "O TEXTO COM LACUNAS".
@export var template_key: String = "":
	set(value):
		template_key = value
		_refresh_summary()

## Chave do texto que SUBSTITUI o texto com lacunas quando o jogador acerta tudo: a mesma história,
## contada em detalhe, narrada pelo NPC.
@export var resolved_text_key: String = "":
	set(value):
		resolved_text_key = value
		_refresh_summary()

## Chave do resumo que vai pro diário do jogador quando a história é resolvida. O diário ainda não
## existe: hoje isto só aparece no log, no instante do acerto.
@export var journal_entry_key: String = ""

@export_group("Solução")

## As palavras esperadas, na ordem dos índices das lacunas.
@export var solution: Array[GlossaryWord] = []:
	set(value):
		solution = value
		_refresh_summary()

@export_group("")

## Só leitura: as lacunas, a solução e o que está faltando. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

func _init() -> void:
	_refresh_summary()


func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

# Quantas lacunas esta história tem. A SOLUÇÃO é a autoridade, e não o texto: o texto muda de idioma
# e pode estar sem tradução carregada (dentro do editor, por exemplo), enquanto a solução é a mesma
# em qualquer lugar. É este número que dimensiona o progresso no save.
func get_blank_count() -> int:
	return solution.size()


# A palavra esperada numa lacuna, ou null se o índice não existe.
func get_expected_word(index: int) -> GlossaryWord:
	if index < 0 or index >= solution.size():
		return null
	return solution[index]


# O id da palavra esperada numa lacuna, ou vazio. É o que a avaliação compara — ela trabalha com
# ids, nunca com recursos, porque id é o que sobrevive ao save.
func get_expected_word_id(index: int) -> StringName:
	var word: GlossaryWord = get_expected_word(index)
	if word == null:
		return &""
	return word.id


# O texto com lacunas, traduzido.
func get_template_text() -> String:
	if template_key.is_empty():
		return ""
	return tr(template_key)


# O texto da história resolvida, traduzido.
func get_resolved_text() -> String:
	if resolved_text_key.is_empty():
		return ""
	return tr(resolved_text_key)


# Quebra o texto traduzido em pedaços pra a página montar: cada pedaço é um trecho de texto ou uma
# lacuna. O formato é { "blank": int, "text": String }, com blank = -1 nos trechos de texto.
#
# A página precisa desta lista, e o resumo do Inspector precisa do mesmo parser pra contar lacunas —
# duas leituras da mesma coisa, então o parser vive aqui e não dentro da tela.
func build_segments(text: String = "") -> Array[Dictionary]:
	var source: String = text if not text.is_empty() else get_template_text()
	var segments: Array[Dictionary] = []
	if source.is_empty():
		return segments

	var regex: RegEx = RegEx.create_from_string(BLANK_PATTERN)
	var cursor: int = 0
	for found: RegExMatch in regex.search_all(source):
		if found.get_start() > cursor:
			segments.append({ "blank": -1, "text": source.substr(cursor, found.get_start() - cursor) })
		segments.append({ "blank": int(found.get_string(1)), "text": "" })
		cursor = found.get_end()
	if cursor < source.length():
		segments.append({ "blank": -1, "text": source.substr(cursor) })

	return segments


# Os índices de lacuna que o texto traduzido realmente usa, na ordem em que aparecem. Serve pra
# validação: lacuna repetida, lacuna faltando e lacuna além do tamanho da solução são erros que só
# aparecem quando alguém compara esta lista com a solução.
func get_template_blank_indices(text: String = "") -> PackedInt32Array:
	var indices: PackedInt32Array = []
	for segment: Dictionary in build_segments(text):
		var blank: int = int(segment.get("blank", -1))
		if blank >= 0:
			indices.append(blank)
	return indices


# Problemas de preenchimento, uma frase por problema. Compartilhado entre o resumo do Inspector e a
# validação em lote do menu de debug.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []

	if id == &"":
		issues.append("Sem id.")
	if emotion == null:
		issues.append("Sem emoção: a história não apareceria atrás de nenhum INVESTIGAR.")
	if template_key.is_empty():
		issues.append("Sem chave do texto com lacunas (template_key).")
	if resolved_text_key.is_empty():
		issues.append("Sem chave do texto resolvido (resolved_text_key): acertar tudo não revelaria nada.")
	if solution.is_empty():
		issues.append("Sem solução: nenhuma lacuna esperada.")

	for index: int in solution.size():
		if solution[index] == null:
			issues.append("A palavra da lacuna {%d} está vazia." % index)

	# A comparação com o TEXTO só faz sentido quando há texto traduzido pra ler. Dentro do editor as
	# traduções do jogo não estão carregadas e tr() devolve a própria chave, então este bloco só roda
	# quando o texto de fato veio.
	var template: String = get_template_text()
	if not template.is_empty() and template != template_key:
		var used: Dictionary = {}
		for blank: int in get_template_blank_indices(template):
			if used.has(blank):
				issues.append("A lacuna {%d} aparece duas vezes no texto." % blank)
			elif blank >= solution.size():
				issues.append("O texto usa a lacuna {%d}, mas a solução só tem %d palavra(s)."
					% [blank, solution.size()])
			used[blank] = true
		for index: int in solution.size():
			if not used.has(index):
				issues.append("A solução tem a palavra %d, mas o texto não usa a lacuna {%d}."
					% [index + 1, index])

	return issues


func _refresh_summary() -> void:
	var lines: PackedStringArray = []
	lines.append("História \"%s\" · emoção: %s" % [
		id, emotion.id if emotion != null else "NENHUMA"])
	lines.append("%d lacuna(s) na solução" % solution.size())
	lines.append("")

	for index: int in solution.size():
		var word: GlossaryWord = solution[index]
		lines.append("  {%d} -> %s" % [index, word.id if word != null else "VAZIO"])

	var issues: PackedStringArray = collect_issues()
	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()
