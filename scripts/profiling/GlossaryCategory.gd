## GlossaryCategory - uma categoria de palavra do glossário (nome, arma, ação, objeto...).
##
## COMO USAR: crie um .tres em res://resources/profiling/categorias/ por categoria e aponte ele no
## campo "Category" de cada palavra (ver GlossaryWord.gd). A cor daqui é o que pinta o retângulo da
## palavra no glossário — é ela que deixa o jogador agrupar palavras de olho, sem ler.
##
## POR QUE É UM RECURSO E NÃO UM ENUM: é a mesma decisão de EmotionDefinition.gd. Categoria é
## conteúdo: o design cria uma categoria nova arrastando um arquivo, escolhendo a cor no Inspector, e
## nenhum script do profiling precisa ser aberto. Um enum obrigaria uma edição de código (e um
## match com a cor hardcoded) por categoria nova.
##
## AS CATEGORIAS DO GDD: verde = nome, vermelho = arma, azul = ação, amarelo = objeto (objetos que
## NÃO são armas). Elas são o ponto de partida, não o limite.
##
## O guia completo está em docs/sistema_de_profiling.md.
@tool
class_name GlossaryCategory
extends Resource

## Espaço para variáveis exportadas

## Identificador estável da categoria. Usado em log, no menu de debug e no save. Não é texto
## exibido ao jogador.
@export var id: StringName = &""

## Chave de tradução do nome da categoria, em translations/translations.csv (ex.: GLOSSARY_CATEGORY_NAME).
## Nunca escreva o nome direto aqui: nome de categoria aparece no filtro do glossário, então é texto
## de jogador.
@export var name_key: StringName = &""

## Cor do retângulo da palavra no glossário. É a informação mais usada da categoria: o jogador
## reconhece "nome" pelo verde muito antes de ler a legenda.
@export var color: Color = Color.WHITE

## Ordem em que a categoria aparece no glossário quando o filtro "Categoria" está ligado. Menor
## primeiro. Empate cai na ordem alfabética do id, pra a lista não mudar de forma entre execuções.
@export var sort_order: int = 0

## Espaço para funções personalizadas

# Nome traduzido, com o id como último recurso pra nunca aparecer vazio em log e debug.
func get_display_name() -> String:
	if name_key == &"":
		return String(id)
	return tr(name_key)


# Cor do texto que se lê em cima de color. O retângulo da categoria é preenchido com a cor dela, e
# uma palavra em branco sobre o amarelo do objeto seria ilegível — então a escolha é feita pelo
# brilho da cor, e não à mão em cada categoria.
func get_contrast_color() -> Color:
	return Color.BLACK if color.get_luminance() > 0.55 else Color.WHITE


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "GlossaryCategory(%s)" % id
