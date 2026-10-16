## EvidenceViewer - a evidência de perto: a tela escurece, a evidência aparece no centro com o texto
## dela, e o jogador colhe as palavras sublinhadas para o glossário.
##
## COMO USAR: não se põe em cena nenhuma. Quem abre é o Interactable de evidência (ver
## Interactable._show_evidence): instancia scenes/ui/EvidenceViewer.tscn, adiciona à cena atual e
## chama open(). Fechar libera o nó sozinho.
##
## REGRAS DA TAREFA:
##   - roda do mouse dá zoom; arrastar com o botão esquerdo (fora das palavras) mexe a evidência um
##     pouco. Os dois com limite (max_zoom, max_pan): é para examinar, não para perder a evidência.
##   - só fecha (botão ou Esc) depois de colher todas as palavras marcadas no texto
##     (ClickableWordText.all_words_collected). Nada a guardar aqui: a regra é recalculada do texto e
##     do ProfilingJournal, então reabrir a evidência depois de recarregar a partida continua certo.
##   - ao fechar, a evidência vai para o diário (Diary.add_evidence). Ela NÃO sai do mundo: clicar de
##     novo reabre, já com as palavras colhidas e o fechar liberado.
##
## Pausa o jogo enquanto está aberta, como o Diário: o jogador está lendo, o mundo espera. O aviso
## de palavra nova (WordDiscoveryToast) já anima com a árvore pausada.
class_name EvidenceViewer
extends CanvasLayer

## Espaço para constantes

# Quanto um passo da roda do mouse multiplica o zoom.
const ZOOM_STEP: float = 1.1

## Espaço para variáveis exportadas

@export_range(0.5, 1.0, 0.05) var min_zoom: float = 0.8
@export_range(1.0, 4.0, 0.1) var max_zoom: float = 2.0
# Quanto a evidência pode sair do centro, em pixels de tela, em cada eixo.
@export var max_pan: float = 200.0

## Espaço para variáveis

var _item: ItemData
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
# Só true quando foi o próprio viewer quem pausou a árvore (mesma regra do Diary.close_diary).
var _paused_by_viewer: bool = false

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _card: Control = $Root/Card
@onready var _image: TextureRect = %Image
@onready var _text: ClickableWordText = %Text
@onready var _close_button: Button = %CloseButton

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.gui_input.connect(_on_root_gui_input)
	_card.resized.connect(_apply_transform)
	_root.resized.connect(_apply_transform)
	_close_button.pressed.connect(close)
	EventBus.glossary_word_discovered.connect(_on_glossary_word_discovered)


func _unhandled_input(event: InputEvent) -> void:
	# O Diário aberto por cima (tecla J) é quem responde ao Esc.
	if not event.is_action_pressed(&"ui_cancel") or Diary.is_open():
		return
	# Consumido mesmo sem poder fechar: o Esc seguiria para o menu de pausa, que despausaria o jogo
	# por baixo da evidência ao fechar.
	get_viewport().set_input_as_handled()
	close()

## Espaço para funções personalizadas

func open(item: ItemData) -> void:
	_item = item
	_image.texture = item.icon
	_text.set_marked_text(tr(item.description_key))
	_update_close_button()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_viewer = true
	print("[Evidence] - Evidência \"%s\" aberta" % item.id)


# Fecha a evidência, se o jogador já colheu todas as palavras dela, e a põe no diário.
func close() -> void:
	if not _can_close():
		return
	Diary.add_evidence(_item)
	if _paused_by_viewer:
		get_tree().paused = false
	print("[Evidence] - Evidência \"%s\" fechada e enviada ao diário" % _item.id)
	queue_free()


func _can_close() -> bool:
	return _item != null and ClickableWordText.all_words_collected(tr(_item.description_key))


func _update_close_button() -> void:
	_close_button.disabled = not _can_close()


func _on_glossary_word_discovered(_npc_id: StringName, _word_id: StringName) -> void:
	_update_close_button()


# Zoom pela roda e arrasto com o botão esquerdo. Chega aqui o que a carta e o texto não consumiram
# (os dois deixam o evento passar): o clique numa palavra é colhido pelo texto e, no máximo, começa
# um arrasto de distância zero.
func _on_root_gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP when button.pressed:
				_zoom = minf(_zoom * ZOOM_STEP, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN when button.pressed:
				_zoom = maxf(_zoom / ZOOM_STEP, min_zoom)
			MOUSE_BUTTON_LEFT:
				_dragging = button.pressed
		_apply_transform()
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		# O soltar do clique numa palavra é consumido pelo texto e não chega aqui. Sem o botão
		# segurado de verdade, o arrasto já acabou: senão a evidência seguiria o mouse solto.
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			return
		_pan = (_pan + motion.relative).clamp(Vector2(-max_pan, -max_pan), Vector2(max_pan, max_pan))
		_apply_transform()


# Centraliza a carta na tela, mais o deslocamento do arrasto, com o zoom em volta do centro dela.
# Feito à mão, e não com um CenterContainer: um container reescreve a posição e a escala do filho a
# cada rearranjo, e desfaria o zoom e o arrasto.
func _apply_transform() -> void:
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2.ONE * _zoom
	_card.position = (_root.size - _card.size) / 2.0 + _pan
