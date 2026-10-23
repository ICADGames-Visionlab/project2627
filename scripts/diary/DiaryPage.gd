## DiaryPage - uma página (um par de folhas aberto) do diário: o que ela mostra, e nada sobre como.
##
## O diário é um livro folheado em sequência, na ordem em que o GDD pede:
##
##     capa -> sumário -> pessoas -> [pessoa: geral -> evidências -> rotina] x cada pessoa conhecida
##          -> anotações pessoais -> coro -> cidade -> cidade distorcida -> memórias
##
## Quem monta essa lista é o Diary (Diary.get_pages), a partir dos fatos da partida: cada pessoa
## que o jogador conheceu acrescenta as três páginas dela, e uma seção que não cabe numa página só
## (muitas pessoas, muitas evidências, muitas anotações) vira várias, numeradas por "chunk".
##
## Não é Resource nem Node: é só um endereço. A tela que desenha cada tipo é uma cena própria (ver
## DiaryBook.gd), e a página é refeita do zero sempre que o conteúdo muda — por isso ela não guarda
## estado de tela nenhum.
##
## O guia completo está em docs/diary.md.
class_name DiaryPage
extends RefCounted

## Espaço para enums

enum Kind { COVER, CONTENTS, PEOPLE, PERSON, PERSON_EVIDENCE, PERSON_ROUTINE, NOTES_INDEX, NOTES }

## Espaço para variáveis

var kind: Kind = Kind.COVER
# PERSON, PERSON_EVIDENCE e PERSON_ROUTINE: de quem é a página.
var npc_id: StringName = &""
# NOTES: o subtópico (um DiaryNote.Topic).
var topic: int = -1
# Qual pedaço da seção, quando ela não cabe numa página só (0 = a primeira).
var chunk: int = 0

## Espaço para funções nativas

func _init(p_kind: Kind = Kind.COVER, p_npc_id: StringName = &"", p_topic: int = -1, p_chunk: int = 0) -> void:
	kind = p_kind
	npc_id = p_npc_id
	topic = p_topic
	chunk = p_chunk

## Espaço para funções personalizadas

# Endereço estável da página. É o que o diário guarda como "página atual": conteúdo novo entrando no
# meio do livro muda os índices, mas não as chaves, e o jogador continua na página que estava lendo.
func get_key() -> String:
	return make_key(kind, npc_id, topic, chunk)


static func make_key(p_kind: Kind, p_npc_id: StringName = &"", p_topic: int = -1, p_chunk: int = 0) -> String:
	match p_kind:
		Kind.CONTENTS:
			return "contents"
		Kind.PEOPLE:
			return "people:%d" % p_chunk
		Kind.PERSON:
			return "person:%s" % p_npc_id
		Kind.PERSON_EVIDENCE:
			return "person:%s:evidence:%d" % [p_npc_id, p_chunk]
		Kind.PERSON_ROUTINE:
			return "person:%s:routine" % p_npc_id
		Kind.NOTES_INDEX:
			return "notes"
		Kind.NOTES:
			return "notes:%d:%d" % [p_topic, p_chunk]
		_:
			return "cover"


func _to_string() -> String:
	return "DiaryPage(%s)" % get_key()
