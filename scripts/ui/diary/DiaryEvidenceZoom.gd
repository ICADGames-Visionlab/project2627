## DiaryEvidenceZoom - a evidência ampliada no centro da tela, com o fundo escurecido: a imagem, o
## nome e o que está escrito nela (sem as palavras clicáveis: no diário ela já foi colhida).
##
## Fica dentro do DiaryBook, escondida até open(). Clicar em qualquer lugar ou Esc fecha.
class_name DiaryEvidenceZoom
extends Control

## Espaço para variáveis onready

@onready var _image: TextureRect = %Image
@onready var _name: Label = %Name
@onready var _text: RichTextLabel = %Text

## Espaço para funções nativas

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	hide()

## Espaço para funções personalizadas

func open(item: ItemData) -> void:
	_image.texture = item.icon
	_name.text = tr(item.display_name_key)
	_text.text = ClickableWordText.render_plain(tr(item.description_key))
	show()
	print("[Diary] - Evidência \"%s\" ampliada" % item.id)


func close() -> void:
	hide()


func _on_gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()
