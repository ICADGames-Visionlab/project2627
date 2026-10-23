## DiaryEvidencePage - as evidências de uma pessoa: as que o jogador já leu e que têm no texto alguma
## palavra do glossário dela (ver Diary.get_evidence_for_npc). Clicar numa evidência a amplia no
## centro da tela, escurecendo o fundo.
##
## Cada folha tem uma coluna de cartões (imagem + legenda), alternando o lado da imagem como no
## rascunho do GDD; o par de folhas mostra Diary.evidence_per_spread evidências, e as que sobram vão
## pra próxima página.
class_name DiaryEvidencePage
extends DiaryPageView

## Espaço para variáveis exportadas

## A cena de um cartão de evidência (DiaryEvidenceCard.tscn).
@export var card_scene: PackedScene

## Espaço para variáveis onready

@onready var _person_label: Label = %Person
@onready var _left_list: Container = %LeftList
@onready var _right_list: Container = %RightList
@onready var _empty: Label = %Empty

## Espaço para funções personalizadas

func show_page(page: DiaryPage) -> void:
	clear_children(_left_list)
	clear_children(_right_list)

	var definition: NPCDefinition = Diary.get_definition(page.npc_id)
	_person_label.text = definition.get_display_name() if definition != null else ""

	var items: Array[ItemData] = Diary.get_evidence_for_npc(page.npc_id)
	var per_spread: int = Diary.evidence_per_spread
	var per_sheet: int = maxi(ceili(per_spread / 2.0), 1)
	var start: int = page.chunk * per_spread
	_empty.visible = items.is_empty()

	for index: int in range(start, mini(start + per_spread, items.size())):
		var local: int = index - start
		var card: DiaryEvidenceCard = card_scene.instantiate() as DiaryEvidenceCard
		(_left_list if local < per_sheet else _right_list).add_child(card)
		var item: ItemData = items[index]
		card.configure(item, local % 2 == 1)
		card.pressed.connect(book.show_evidence.bind(item))
