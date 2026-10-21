## DiaryPeoplePage - "Pessoas": as pessoas que o jogador conheceu, em grupos de 4 por folha.
##
## O PRIMEIRO GRUPO fica na folha da direita do sumário (Diary.people_on_contents), pra o sumário não
## ter uma folha vazia; esta página só existe quando sobram pessoas depois dele, e continua a lista dali.
##
## Cada folha é uma grade de duas colunas: na coluna da esquerda o cartão tem o nome antes do retrato,
## na da direita o retrato antes do nome — os dois retratos ficam virados pro meio da folha. Clicar
## num cartão abre a página daquela pessoa.
class_name DiaryPeoplePage
extends DiaryPageView

## Espaço para variáveis exportadas

## A cena de um cartão de pessoa (DiaryPersonCard.tscn).
@export var card_scene: PackedScene

## Espaço para variáveis onready

@onready var _left_grid: GridContainer = %LeftGrid
@onready var _right_grid: GridContainer = %RightGrid
@onready var _empty: Label = %Empty

## Espaço para funções personalizadas

func show_page(page: DiaryPage) -> void:
	clear_children(_left_grid)
	clear_children(_right_grid)

	var people: Array[StringName] = Diary.get_people()
	var per_spread: int = Diary.people_per_spread
	@warning_ignore("integer_division")
	var per_sheet: int = maxi(per_spread / 2, 1)
	var start: int = Diary.people_on_contents + page.chunk * per_spread
	_empty.visible = people.size() <= start

	for index: int in range(start, mini(start + per_spread, people.size())):
		var local: int = index - start
		add_card(_left_grid if local < per_sheet else _right_grid, card_scene, people[index], local % 2 == 1, book)


# Põe o cartão de uma pessoa numa grade. Compartilhado com o sumário, que mostra o primeiro grupo.
static func add_card(grid: GridContainer, scene: PackedScene, npc_id: StringName, mirrored: bool,
		diary_book: DiaryBook) -> void:
	var card: DiaryPersonCard = scene.instantiate() as DiaryPersonCard
	grid.add_child(card)
	card.configure(Diary.get_definition(npc_id), mirrored)
	card.pressed.connect(diary_book.navigate.bind(DiaryPage.make_key(DiaryPage.Kind.PERSON, npc_id)))
