## DiaryWordEvidencePopup - o pop-up de uma palavra do glossário: a palavra no centro e, em volta, as
## evidências já lidas que a mencionam, ligadas a ela por um traço. Clicar numa evidência a amplia.
##
## Fica dentro do DiaryBook (por cima das páginas), escondido até open(). Clicar fora do papel ou Esc
## fecha (o Esc é lido pelo DiaryBook).
class_name DiaryWordEvidencePopup
extends Control

## Espaço para sinais

signal evidence_selected(item: ItemData)

## Espaço para variáveis exportadas

@export var card_scene: PackedScene
@export var chip_scene: PackedScene
## Distância do centro até as evidências, em pixels.
@export var radius: Vector2 = Vector2(330.0, 190.0)
@export var line_color: Color = Color(0.97, 0.94, 0.86, 1)
@export var line_width: float = 5.0

## Espaço para variáveis onready

@onready var _dim: Control = %Dim
@onready var _title: Label = %Title
@onready var _graph: Control = %Graph
@onready var _empty: Label = %Empty

## Espaço para funções nativas

func _ready() -> void:
	_dim.gui_input.connect(_on_dim_gui_input)
	_graph.draw.connect(_draw_links)
	_graph.resized.connect(_layout)
	hide()

## Espaço para funções personalizadas

func open(npc_id: StringName, word: GlossaryWord, items: Array[ItemData]) -> void:
	DiaryPageView.clear_children(_graph)
	_title.text = tr(&"DIARY_WORD_EVIDENCE_TITLE") % word.get_display_text()
	_empty.visible = items.is_empty()

	var chip: GlossaryWordChip = chip_scene.instantiate() as GlossaryWordChip
	chip.name = &"Word"
	_graph.add_child(chip)
	chip.configure(word, ProfilingJournal.get_mark(npc_id, word.id), false)

	for item: ItemData in items:
		var card: DiaryEvidenceCard = card_scene.instantiate() as DiaryEvidenceCard
		_graph.add_child(card)
		card.configure(item)
		card.pressed.connect(evidence_selected.emit.bind(item))

	show()
	_layout.call_deferred()


func close() -> void:
	hide()


# A palavra no centro e as evidências numa elipse em volta, começando de cima. Adiado pra depois de
# os nós terem tamanho (o texto decide a largura de cada um).
func _layout() -> void:
	if not visible:
		return
	var center: Vector2 = _graph.size * 0.5
	var cards: Array[Control] = []
	for child: Node in _graph.get_children():
		var control: Control = child as Control
		if control == null:
			continue
		control.reset_size()
		if child.name == &"Word":
			control.position = center - control.size * 0.5
		else:
			cards.append(control)
	for index: int in cards.size():
		var angle: float = -PI * 0.5 + TAU * float(index) / float(cards.size())
		var spot: Vector2 = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		cards[index].position = spot - cards[index].size * 0.5
	_graph.queue_redraw()


func _draw_links() -> void:
	var center: Vector2 = _graph.size * 0.5
	for child: Node in _graph.get_children():
		var control: Control = child as Control
		if control != null and child.name != &"Word":
			_graph.draw_line(center, control.position + control.size * 0.5, line_color, line_width, true)


func _on_dim_gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()
