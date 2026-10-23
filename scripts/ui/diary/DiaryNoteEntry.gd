## DiaryNoteEntry - uma anotação pessoal na página: a data no canto superior esquerdo, o texto e as
## imagens embaixo. O layout (tamanho das imagens, fontes) está na cena.
class_name DiaryNoteEntry
extends VBoxContainer

## Espaço para variáveis onready

@onready var _date: Label = %Date
@onready var _topic: Label = %Topic
@onready var _text: RichTextLabel = %Text
@onready var _images: Container = %Images
@onready var _image_template: TextureRect = %ImageTemplate

## Espaço para funções personalizadas

# show_topic: na página de índice a anotação aparece fora do subtópico dela, então diz qual é.
func configure(note: DiaryNote, day: int, show_topic: bool = false) -> void:
	_date.text = Diary.format_date(day)
	_topic.visible = show_topic
	_topic.text = DiaryNote.get_topic_name(note.topic)
	_text.text = ClickableWordText.render_plain(tr(note.text_key))

	for child: Node in _images.get_children():
		if child != _image_template:
			child.queue_free()
	_image_template.hide()
	for texture: Texture2D in note.images:
		if texture == null:
			continue
		# A imagem é um nó da cena (o molde, escondido), duplicado por imagem: o tamanho e o filtro
		# ficam na cena, e não aqui.
		var image: TextureRect = _image_template.duplicate() as TextureRect
		image.texture = texture
		image.show()
		_images.add_child(image)
	_images.visible = _images.get_child_count() > 1
