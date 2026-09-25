## EmotionDefinition - uma emoção do catálogo do jogo (raiva, tristeza, euforia...).
##
## COMO USAR: crie um .tres em res://resources/emocoes/ por emoção e aponte ele nos campos
## "Emoção 1" e "Emoção 2" do NPC (ver NPCDefinition.gd). Cada NPC escolhe DUAS do catálogo, e
## elas não precisam ser as mesmas entre NPCs.
##
## POR QUE É UM RECURSO E NÃO UM ENUM: emoção é conteúdo, não estrutura. Como recurso, o design
## cria uma emoção nova arrastando um arquivo, sem edição de código e sem mexer em nada que já
## funciona. O sistema de rotina, por outro lado, nunca pergunta QUAL emoção está vigente — ele
## só olha o SLOT (neutro / emoção 1 / emoção 2), e é isso que faz dois NPCs com emoções
## completamente diferentes rodarem no mesmo código.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name EmotionDefinition
extends Resource

## Espaço para variáveis exportadas

## Identificador estável da emoção. Usado em log, no menu de debug e, no futuro, pelo sistema que
## decide qual emoção fica vigente. Não é texto exibido ao jogador.
@export var id: StringName = &""

## Chave de tradução do nome da emoção, em translations/translations.csv (ex.: EMOTION_ANGER).
## Nunca escreva o nome direto aqui: nome de emoção é texto de jogador.
@export var name_key: StringName = &""

## Cor de identificação. Hoje tinge o nome acima da cabeça do NPC enquanto esta emoção está
## vigente — é o que deixa dar pra ver, olhando a cidade, quem está em qual emoção.
@export var tint: Color = Color.WHITE

## Espaço para funções personalizadas

# Nome traduzido, com o id como último recurso pra nunca aparecer vazio em log e debug.
func get_display_name() -> String:
	if name_key == &"":
		return String(id)
	return tr(name_key)
