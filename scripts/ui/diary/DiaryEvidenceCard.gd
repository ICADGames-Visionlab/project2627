## DiaryEvidenceCard - uma evidência em miniatura: a imagem e o nome dela. Usado na página de
## evidências da pessoa e no pop-up das palavras do glossário.
##
## mirrored = true põe a imagem à esquerda da legenda. O tamanho da imagem e a fonte estão na cena.
class_name DiaryEvidenceCard
extends Button

## Espaço para variáveis

var item: ItemData

## Espaço para variáveis onready

@onready var _row: BoxContainer = %Row
@onready var _caption: Label = %Caption
@onready var _image: TextureRect = %Image
@onready var _frame: Control = %Frame

## Espaço para funções personalizadas

func configure(p_item: ItemData, mirrored: bool = false) -> void:
	item = p_item
	_caption.text = tr(item.display_name_key)
	_image.texture = item.icon
	_row.move_child(_frame, 0 if mirrored else _row.get_child_count() - 1)
