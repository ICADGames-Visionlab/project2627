## NPCProfile - o que o jogador pode descobrir sobre UM NPC: as histórias das emoções dele e todas
## as palavras que existem no glossário dele.
##
## COMO USAR: um .tres por NPC em res://resources/profiling/npcs/, com o "Npc Id" igual ao id do
## NPCDefinition (res://resources/npcs/). Não existe lista central pra manter: o catálogo varre a
## pasta e acha o perfil pelo id (ver ProfilingCatalog), do mesmo jeito que os insights.
##
## POR QUE NÃO ESTÁ DENTRO DO NPCDefinition: o NPC existe no mundo acordado sem saber que existe
## profiling. NPC sem perfil simplesmente não tem espírito no sonho, e um NPC novo entra na cidade
## sem obrigar ninguém a preencher história nenhuma. É a mesma separação dos insights, que também não
## moram dentro do objeto que os carrega.
##
## UMA HISTÓRIA POR EMOÇÃO: a tela do espírito mostra as emoções que o NPCDefinition dá ao NPC
## (emotion_first e emotion_second hoje) e procura, aqui, a história de cada uma. O GDD fala de três
## emoções por NPC; o projeto usa emoções modulares em slots, então a quantidade é a que o NPC
## tiver — quando aparecer um terceiro slot, este arquivo não muda.
##
## O RETRATO DO NPC NÃO ESTÁ AQUI: ele é a cara do NPC, não conteúdo de profiling, e o diário e a
## tela de diálogo vão querer o mesmo arquivo. Ele mora em NPCDefinition.portrait
## (res://resources/npcs/), junto do nome e da cor.
##
## O POOL DE PALAVRAS ("Glossary Words") é o total do glossário: é o "36" do "23/36" que o jogador
## vê. Ele contém as palavras da solução das histórias E as palavras que não resolvem nada (pista
## falsa é conteúdo, não bug). Palavra que está numa solução mas não está no pool é erro de
## preenchimento, e o resumo acusa: o jogador nunca teria como preenchê-la.
##
## O guia completo está em docs/sistema_de_profiling.md.
@tool
class_name NPCProfile
extends Resource

## Espaço para variáveis exportadas

## O id do NPC a que este perfil pertence. Tem que ser igual ao id do NPCDefinition — a validação em
## lote do menu de debug compara os dois e acusa perfil órfão.
@export var npc_id: StringName = &"":
	set(value):
		npc_id = value
		_refresh_summary()

## As histórias deste NPC, uma por emoção.
@export var stories: Array[ProfilingStory] = []:
	set(value):
		stories = value
		_refresh_summary()

## Todas as palavras que o glossário deste NPC pode chegar a ter. Ver o bloco "O POOL DE PALAVRAS".
@export var glossary_words: Array[GlossaryWord] = []:
	set(value):
		glossary_words = value
		_refresh_summary()

@export_group("Mundo dos sonhos")

## SUPORTE AO FUTURO: o GDD diz que o espírito do NPC só aparece no sonho depois de o jogador ter
## conversado com ele no mundo real. O sistema de diálogo está sendo feito em outra branch, então
## nada marca esse encontro ainda e ProfilingJournal.has_met() responde sim pra todo mundo (ver a
## constante ASSUME_MET_UNTIL_DIALOGUE_EXISTS lá). Deixar o campo ligado aqui é o que faz a regra
## valer sozinha no dia em que o diálogo começar a marcar o encontro.
@export var requires_real_world_meeting: bool = true

@export_group("")

## Só leitura: histórias, palavras e o que está faltando. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

func _init() -> void:
	_refresh_summary()


func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

# A história de uma emoção, ou null se este NPC não tem história pra ela. É a consulta que a tela do
# espírito faz por emoção do NPC: sem história, a emoção aparece sem o botão INVESTIGAR.
#
# A comparação é por ID da emoção, e não pelo recurso: o mesmo arquivo de emoção carregado de dois
# caminhos diferentes (o que acontece com .tres.remap na build exportada) daria duas instâncias
# distintas, e a história desapareceria na build sem nunca falhar no editor.
func find_story_for_emotion(emotion: EmotionDefinition) -> ProfilingStory:
	if emotion == null:
		return null
	for story: ProfilingStory in stories:
		if story != null and story.emotion != null and story.emotion.id == emotion.id:
			return story
	return null


# A história de um id, ou null. Usada pelo save (que guarda progresso por id de história) e pelos
# comandos do menu de debug.
func find_story(story_id: StringName) -> ProfilingStory:
	for story: ProfilingStory in stories:
		if story != null and story.id == story_id:
			return story
	return null


# A palavra de um id dentro do pool deste NPC, ou null. É por aqui que o glossário reconstrói a
# palavra a partir do id que veio do save.
func find_word(word_id: StringName) -> GlossaryWord:
	for word: GlossaryWord in glossary_words:
		if word != null and word.id == word_id:
			return word
	return null


# Quantas palavras o glossário deste NPC tem no total — o "36" do "23/36".
func get_total_word_count() -> int:
	var seen: Dictionary = {}
	for word: GlossaryWord in glossary_words:
		if word != null and word.id != &"":
			seen[word.id] = true
	return seen.size()


# Quantas histórias este NPC tem de verdade (posição vazia na lista não conta). É o denominador do
# "acertou o NPC inteiro", que é o que faz o jogador acordar do sonho.
func get_story_count() -> int:
	var count: int = 0
	for story: ProfilingStory in stories:
		if story != null:
			count += 1
	return count


# Problemas de preenchimento, uma frase por problema. Compartilhado entre o resumo do Inspector e a
# validação em lote do menu de debug.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []

	if npc_id == &"":
		issues.append("Sem id de NPC: o catálogo não acha este perfil.")
	if stories.is_empty():
		issues.append("Sem histórias: o espírito abriria sem nada pra investigar.")
	if glossary_words.is_empty():
		issues.append("Sem palavras no pool: o glossário nasceria vazio.")

	var word_ids: Dictionary = {}
	for word: GlossaryWord in glossary_words:
		if word == null:
			issues.append("Há uma posição vazia no pool de palavras.")
			continue
		if word_ids.has(word.id):
			issues.append("Palavra repetida no pool: \"%s\"." % word.id)
		word_ids[word.id] = true
		for issue: String in word.collect_issues():
			issues.append(issue)

	var story_ids: Dictionary = {}
	var emotion_ids: Dictionary = {}
	for story: ProfilingStory in stories:
		if story == null:
			issues.append("Há uma posição vazia na lista de histórias.")
			continue
		if story_ids.has(story.id):
			issues.append("História repetida: \"%s\"." % story.id)
		story_ids[story.id] = true

		if story.emotion != null:
			# Duas histórias na mesma emoção fariam uma delas nunca aparecer: a tela do espírito
			# pergunta pela emoção e recebe só a primeira.
			if emotion_ids.has(story.emotion.id):
				issues.append("Duas histórias na emoção \"%s\"." % story.emotion.id)
			emotion_ids[story.emotion.id] = true

		for issue: String in story.collect_issues():
			issues.append("História \"%s\": %s" % [story.id, issue])

		# A palavra da solução TEM que estar no pool, senão a lacuna é impossível: ela nunca chegaria
		# ao glossário do jogador.
		for index: int in story.solution.size():
			var expected: GlossaryWord = story.solution[index]
			if expected != null and not word_ids.has(expected.id):
				issues.append("História \"%s\": a palavra \"%s\" (lacuna {%d}) não está no pool do NPC."
					% [story.id, expected.id, index])

	return issues


func _refresh_summary() -> void:
	var lines: PackedStringArray = []
	lines.append("Perfil de \"%s\" · %d história(s) · %d palavra(s) no glossário" % [
		npc_id, get_story_count(), get_total_word_count()])
	lines.append("")

	for story: ProfilingStory in stories:
		if story == null:
			continue
		lines.append("  %-24s emoção: %-12s %d lacuna(s)" % [
			story.id,
			story.emotion.id if story.emotion != null else "NENHUMA",
			story.get_blank_count()])

	var per_category: Dictionary = {}
	for word: GlossaryWord in glossary_words:
		if word == null:
			continue
		var key: String = String(word.get_category_id())
		if key.is_empty():
			key = "sem categoria"
		per_category[key] = int(per_category.get(key, 0)) + 1

	if not per_category.is_empty():
		lines.append("")
		var categories: Array = per_category.keys()
		categories.sort()
		for category: String in categories:
			lines.append("  %-16s %d palavra(s)" % [category, int(per_category[category])])

	var issues: PackedStringArray = collect_issues()
	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()
