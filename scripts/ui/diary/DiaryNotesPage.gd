## DiaryNotesPage - as anotações de um subtópico, como um logbook: cada uma com a data (dia e mês) no
## canto superior esquerdo, o texto e as imagens. Em ordem de entrada; o que não cabe no par de folhas
## (Diary.notes_per_spread) vai pra próxima página.
class_name DiaryNotesPage
extends DiaryPageView

## Espaço para variáveis exportadas

## A cena de uma anotação (DiaryNoteEntry.tscn).
@export var entry_scene: PackedScene

## Espaço para variáveis onready

@onready var _title: Label = %Title
@onready var _left_list: Container = %LeftList
@onready var _right_list: Container = %RightList
@onready var _empty: Label = %Empty

## Espaço para funções personalizadas

func show_page(page: DiaryPage) -> void:
	clear_children(_left_list)
	clear_children(_right_list)
	_title.text = DiaryNote.get_topic_name(page.topic)

	var notes: Array[Dictionary] = Diary.get_notes(page.topic)
	var per_spread: int = Diary.notes_per_spread
	var per_sheet: int = maxi(ceili(per_spread / 2.0), 1)
	var start: int = page.chunk * per_spread
	_empty.visible = notes.is_empty()

	for index: int in range(start, mini(start + per_spread, notes.size())):
		var entry: DiaryNoteEntry = entry_scene.instantiate() as DiaryNoteEntry
		(_left_list if index - start < per_sheet else _right_list).add_child(entry)
		entry.configure(notes[index]["note"], int(notes[index]["day"]))
