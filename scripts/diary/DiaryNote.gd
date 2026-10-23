## DiaryNote - uma anotação pessoal do diário: um texto curto, com imagens, num dos subtópicos
## (coro, cidade, cidade distorcida, memórias).
##
## COMO USAR: um .tres por anotação em res://resources/diary/notas/ (direto na pasta, sem subpasta: é
## ali que o DiaryNoteCatalog procura). Preencha o id, o subtópico, a chave do texto no CSV, as
## imagens e o gatilho. Nenhum script precisa ser aberto pra pôr uma anotação nova no jogo.
##
## O GATILHO decide QUANDO a anotação aparece no diário (o Diary escuta os eventos e procura aqui):
##
##     MANUAL                 só quando algum código chama Diary.add_note(id) (ou o menu de debug)
##     DREAM_ENTERED          o jogador entra no mundo dos sonhos
##     INSIGHT_READ           o jogador lê um dos insights de trigger_ids
##     CONVERSATION_STARTED   abre uma das conversas de trigger_ids
##
## Cada anotação entra UMA vez, com a data do dia de jogo em que entrou (ver Diary.format_date). O que
## vai pro save é só o id e o dia; o texto e as imagens moram aqui e no CSV.
##
## O guia completo está em docs/diary.md.
class_name DiaryNote
extends Resource

## Espaço para enums

# Os subtópicos de "Anotações pessoais", na ordem em que aparecem no livro.
enum Topic { CHORUS, CITY, DISTORTED_CITY, MEMORIES }

enum Trigger { MANUAL, DREAM_ENTERED, INSIGHT_READ, CONVERSATION_STARTED }

## Espaço para constantes

# Nome de cada subtópico no CSV, na ordem do enum Topic.
const TOPIC_NAME_KEYS: Array[StringName] = [
	&"DIARY_TOPIC_CHORUS", &"DIARY_TOPIC_CITY", &"DIARY_TOPIC_DISTORTED_CITY", &"DIARY_TOPIC_MEMORIES"]

## Espaço para variáveis exportadas

## Identificador estável da anotação. É o que vai pro save: mudar depois some com a anotação de quem
## já a tinha.
@export var id: StringName = &""

## Em que subtópico ela aparece.
@export var topic: Topic = Topic.CITY

## Chave do texto em translations/translations.csv. Nunca o texto direto aqui.
@export var text_key: StringName = &""

## Imagens mostradas embaixo do texto, na ordem da lista. Vazio é normal.
@export var images: Array[Texture2D] = []

@export_group("Gatilho")

@export var trigger: Trigger = Trigger.MANUAL

## INSIGHT_READ: ids de insight (InsightData.id). CONVERSATION_STARTED: ids de conversa (nome do .dlg).
## Qualquer um da lista dispara. Ignorado em MANUAL e DREAM_ENTERED.
@export var trigger_ids: Array[StringName] = []

## Espaço para funções personalizadas

# Diz se um fato do jogo dispara esta anotação.
func matches(p_trigger: Trigger, trigger_id: StringName = &"") -> bool:
	if trigger != p_trigger or trigger == Trigger.MANUAL:
		return false
	if trigger == Trigger.DREAM_ENTERED:
		return true
	return trigger_ids.has(trigger_id)


static func get_topic_name(p_topic: int) -> String:
	if p_topic < 0 or p_topic >= TOPIC_NAME_KEYS.size():
		return ""
	return TranslationServer.translate(TOPIC_NAME_KEYS[p_topic])


# Problemas de preenchimento, uma frase por problema. Usado pela validação do menu de debug.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	if id == &"":
		issues.append("Anotação sem id.")
	if text_key == &"":
		issues.append("Anotação \"%s\" sem chave de texto." % id)
	if (trigger == Trigger.INSIGHT_READ or trigger == Trigger.CONVERSATION_STARTED) and trigger_ids.is_empty():
		issues.append("Anotação \"%s\" tem gatilho por id, mas a lista trigger_ids está vazia." % id)
	for index: int in images.size():
		if images[index] == null:
			issues.append("Anotação \"%s\": a imagem %d está vazia." % [id, index])
	return issues
