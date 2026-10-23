## DiaryNotesIndexPage - "Anotações pessoais": os subtópicos (coro, cidade, cidade distorcida,
## memórias) com quantas anotações cada um tem, e a última anotação do diário na outra folha.
class_name DiaryNotesIndexPage
extends DiaryPageView

## Espaço para variáveis exportadas

## A cena de um link de subtópico (DiaryTopicLink.tscn).
@export var link_scene: PackedScene
## A cena de uma anotação (DiaryNoteEntry.tscn).
@export var entry_scene: PackedScene

## Espaço para variáveis onready

@onready var _topics: Container = %Topics
@onready var _latest: Container = %Latest
@onready var _latest_empty: Label = %LatestEmpty

## Espaço para funções personalizadas

func show_page(_page: DiaryPage) -> void:
	clear_children(_topics)
	clear_children(_latest)

	for topic: int in DiaryNote.Topic.values():
		var link: Button = link_scene.instantiate() as Button
		link.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		link.text = tr(&"DIARY_TOPIC_WITH_COUNT") % [DiaryNote.get_topic_name(topic), Diary.get_notes(topic).size()]
		link.pressed.connect(book.navigate.bind(DiaryPage.make_key(DiaryPage.Kind.NOTES, &"", topic)))
		_topics.add_child(link)

	var notes: Array[Dictionary] = Diary.get_notes()
	_latest_empty.visible = notes.is_empty()
	if not notes.is_empty():
		var entry: DiaryNoteEntry = entry_scene.instantiate() as DiaryNoteEntry
		_latest.add_child(entry)
		entry.configure(notes.back()["note"], int(notes.back()["day"]), true)
