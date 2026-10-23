## DiaryContentsPage - o sumário. Na folha da esquerda, o título e os dois tópicos do diário
## (Pessoas e Anotações pessoais), clicáveis. Na da direita, o primeiro grupo de pessoas
## (Diary.people_on_contents), pra o par de folhas não ficar com uma página vazia.
class_name DiaryContentsPage
extends DiaryPageView

## Espaço para variáveis exportadas

## A cena de um cartão de pessoa (DiaryPersonCard.tscn).
@export var card_scene: PackedScene

## Espaço para variáveis onready

@onready var _people_link: Button = %PeopleLink
@onready var _notes_link: Button = %NotesLink
@onready var _people_grid: GridContainer = %PeopleGrid
@onready var _people_empty: Label = %PeopleEmpty

## Espaço para funções nativas

func _ready() -> void:
	_people_link.pressed.connect(_on_people_pressed)
	_notes_link.pressed.connect(_navigate.bind(DiaryPage.make_key(DiaryPage.Kind.NOTES_INDEX)))

## Espaço para funções personalizadas

func show_page(_page: DiaryPage) -> void:
	clear_children(_people_grid)
	var people: Array[StringName] = Diary.get_people()
	_people_empty.visible = people.is_empty()
	_people_link.disabled = people.is_empty()
	for index: int in mini(Diary.people_on_contents, people.size()):
		DiaryPeoplePage.add_card(_people_grid, card_scene, people[index], index % 2 == 1, book)


# As pessoas já estão na folha ao lado: o link leva pra dentro da seção, na primeira pessoa.
func _on_people_pressed() -> void:
	var people: Array[StringName] = Diary.get_people()
	if not people.is_empty():
		_navigate(DiaryPage.make_key(DiaryPage.Kind.PERSON, people[0]))


func _navigate(key: String) -> void:
	book.navigate(key)
