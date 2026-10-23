## DiaryPersonCard - o cartão de uma pessoa na página "Pessoas": nome sublinhado e retrato num quadro.
##
## mirrored = true troca a ordem (retrato antes do nome), pro cartão da coluna da direita. O layout
## (tamanhos, moldura, fonte) está na cena.
class_name DiaryPersonCard
extends Button

## Espaço para variáveis onready

@onready var _row: BoxContainer = %Row
@onready var _name_block: Control = %NameBlock
@onready var _name_label: Label = %Name
@onready var _portrait: TextureRect = %Portrait

## Espaço para funções personalizadas

func configure(definition: NPCDefinition, mirrored: bool) -> void:
	if definition == null:
		return
	_name_label.text = definition.get_display_name()
	_portrait.texture = definition.portrait
	_row.move_child(_name_block, _row.get_child_count() - 1 if mirrored else 0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT
