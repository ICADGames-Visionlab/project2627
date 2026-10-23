## DiaryRoutinePage - a rotina de uma pessoa, numa tabela que ocupa as duas folhas: uma linha por
## emoção e tipo de dia, as horas do dia na horizontal, e uma linha vertical no horário atual.
##
## Só aparece o que o jogador VIU (ver Diary._observe_routines); o resto da linha fica cinza com "?".
class_name DiaryRoutinePage
extends DiaryPageView

## Espaço para variáveis onready

@onready var _person_label: Label = %Person
@onready var _chart: DiaryRoutineChart = %Chart

## Espaço para funções personalizadas

func show_page(page: DiaryPage) -> void:
	var definition: NPCDefinition = Diary.get_definition(page.npc_id)
	_person_label.text = definition.get_display_name() if definition != null else ""
	_chart.configure(definition)
