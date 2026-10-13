## ProfilingEmotionOption - uma das emoções na tela do espírito: o nome da emoção, o retângulo que
## enche enquanto o jogador segura, o checkmark de história resolvida e o botão INVESTIGAR.
##
## COMO USAR: o layout está em scenes/profiling/ProfilingEmotionOption.tscn — moldura, moldura de
## destaque, barra que enche, posição do INVESTIGAR e fontes. As opções já estão instanciadas na
## ProfilingScreen.tscn (filhas do nó Emotions), cada uma posicionada à mão, e a tela chama
## configure() em cada uma com uma emoção do NPC. O "Emoção" escrito na cena é só pra ver a opção no
## editor: configure() sempre troca pelo nome da emoção. A opção não muda emoção nem abre história:
## ela avisa por signal.
##
## OS DOIS GESTOS, como o GDD pede:
##
##   segurar o botão esquerdo -> o nome cresce, o retângulo em volta enche, e quando enche a emoção
##                               do NPC passa a ser esta (a partir do dia seguinte). Soltar antes
##                               de encher cancela, sem efeito nenhum.
##   passar o mouse           -> aparece o botão INVESTIGAR logo embaixo, que abre a história.
##
## NO CONTROLE os mesmos dois gestos, com o foco no lugar do mouse: a opção com foco mostra o
## INVESTIGAR (o D-pad pra baixo chega nele, e o A aperta), e SEGURAR o A em cima da opção enche o
## retângulo. Tirar o foco da opção no meio cancela, como tirar o mouse de cima. A opção só aceita
## foco com o controle em uso, para o clique do mouse não deixar contorno de foco pra trás.
##
## Segurar é gesto de mudar o mundo, e clicar é gesto de investigar: são intenções diferentes, e é
## por isso que o GDD separa uma no tempo de pressão e a outra num botão. Um clique curto em cima da
## emoção, por isso, não faz nada — e não deve fazer.
##
## AS CORES SÃO DA EMOÇÃO: o que este script faz é tingir (self_modulate) as peças da cena com
## EmotionDefinition.tint. Não há cor de emoção escrita em lugar nenhum do código.
##
## O TREMOR DA TELA e o filtro de cor não estão aqui: eles são da tela inteira, e quem os faz é a
## ProfilingScreen, escutando hold_changed.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingEmotionOption
extends Control

## Espaço para sinais

## Emitido a cada quadro em que o jogador está segurando, com o progresso de 0 a 1. Sai uma última
## vez com 0 quando ele solta antes do fim ou tira o mouse de cima.
signal hold_changed(slot: int, progress: float)

## Emitido quando o retângulo enche: é o pedido de trocar a emoção do NPC.
signal hold_completed(slot: int)

## Emitido no clique em INVESTIGAR.
signal investigate_requested(slot: int)

## Espaço para constantes

# PLACEHOLDER: o checkmark de história resolvida, até existir ícone de arte.
const SOLVED_GLYPH: String = "✓"

## Espaço para variáveis exportadas

## Quanto tempo o jogador precisa segurar pra trocar a emoção, em segundos. É a variável de
## balanceamento do gesto: curto demais troca a emoção sem querer, longo demais irrita.
@export var hold_seconds: float = 1.1

## Quanto o nome da emoção cresce no fim do gesto (1.0 = não cresce).
@export var hold_max_scale: float = 1.35

## Opacidade da moldura da emoção que não é a vigente nem a escolhida.
@export_range(0.0, 1.0, 0.01) var idle_frame_opacity: float = 0.45

## Espaço para variáveis

var slot: int = NPCDefinition.EmotionSlot.NEUTRAL

var _emotion: EmotionDefinition
var _is_holding: bool = false
var _hold_time: float = 0.0
# O gesto de segurar em curso veio do A (foco), e não do mouse: aí quem cancela é perder o foco, e não
# o mouse estar fora da opção (no controle o cursor nem está lá).
var _is_holding_with_focus: bool = false

## Espaço para variáveis onready

@onready var _frame: Panel = $Frame
@onready var _frame_highlight: Panel = $FrameHighlight
@onready var _fill: ColorRect = $Fill
@onready var _label: Label = $EmotionName
@onready var _status: Label = $Status
@onready var _investigate: Button = $InvestigateButton

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_investigate.pressed.connect(_on_investigate_pressed)
	_investigate.hide()
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)
	EventBus.input_device_changed.connect(_on_input_device_changed)
	_apply_focus_mode()


# O processo fica sempre ligado por dois motivos: o gesto de segurar precisa contar tempo, e a
# visibilidade do INVESTIGAR é decidida pela posição do mouse.
#
# A posição do mouse, e não os sinais mouse_entered/mouse_exited: o botão INVESTIGAR fica FORA do
# retângulo da opção (o GDD pede ele "logo embaixo"), e mover o mouse da emoção pro botão dispara um
# mouse_exited na opção. Com os sinais, o botão desapareceria no caminho, antes de o jogador chegar
# nele.
func _process(delta: float) -> void:
	var mouse: Vector2 = get_global_mouse_position()
	var over_option: bool = get_global_rect().has_point(mouse)
	# No controle, o foco faz o papel do mouse em cima: na opção ou no próprio INVESTIGAR.
	var focused: bool = has_focus() or _investigate.has_focus()
	_investigate.visible = over_option or _investigate.get_global_rect().has_point(mouse) or focused

	if _is_holding and not (has_focus() if _is_holding_with_focus else over_option):
		# Arrastar o mouse pra fora (ou tirar o foco) enquanto segura cancela o gesto: sem isso, o
		# jogador trocaria a emoção sem estar mais olhando pra ela.
		_stop_hold()

	if not _is_holding:
		return

	_hold_time += delta
	var progress: float = clampf(_hold_time / maxf(hold_seconds, 0.01), 0.0, 1.0)
	_apply_progress(progress)
	hold_changed.emit(slot, progress)

	if progress >= 1.0:
		_stop_hold()
		print("[Profiling] - Emoção do slot %d escolhida por pressão" % slot)
		hold_completed.emit(slot)


func _gui_input(event: InputEvent) -> void:
	# Controle (e Enter, com a opção focada): segurar o A é segurar o botão esquerdo.
	if event.is_action_pressed(&"ui_accept"):
		accept_event()
		_start_hold(true)
		return
	if event.is_action_released(&"ui_accept"):
		accept_event()
		_stop_hold()
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	accept_event()
	if mouse_button.pressed:
		_start_hold(false)
	else:
		_stop_hold()

## Espaço para funções personalizadas

# Põe uma emoção na opção.
#
#   is_current   -> é a emoção que o NPC está sentindo hoje
#   is_scheduled -> é a que o jogador já escolheu neste sonho, e que vale a partir de amanhã
#   is_solved    -> a história desta emoção já foi acertada (o checkmark do GDD)
#   has_story    -> existe história escrita pra esta emoção; sem ela, não há INVESTIGAR
func configure(emotion: EmotionDefinition, p_slot: int, is_current: bool, is_scheduled: bool,
		is_solved: bool, has_story: bool) -> void:
	_emotion = emotion
	slot = p_slot

	_label.text = emotion.get_display_name() if emotion != null else ""
	_label.modulate = _get_tint()

	# O estado vira texto, e não só cor: "a emoção de hoje" e "a emoção de amanhã" são a informação
	# que o jogador precisa pra decidir, e cor sozinha não conta isso (nem resolve daltonismo).
	if is_scheduled:
		_status.text = tr("PROFILING_EMOTION_TOMORROW")
	elif is_current:
		_status.text = tr("PROFILING_EMOTION_TODAY")
	else:
		_status.text = ""
	if is_solved:
		# O checkmark vem antes do estado, e não no lugar dele: "resolvida" e "é a de hoje" são
		# informações diferentes, e a emoção pode ser as duas coisas ao mesmo tempo.
		if _status.text.is_empty():
			_status.text = SOLVED_GLYPH
		else:
			_status.text = "%s %s" % [SOLVED_GLYPH, _status.text]

	_investigate.hide()
	_investigate.disabled = not has_story
	# Emoção sem história escrita continua podendo ser escolhida (mudar a emoção do NPC muda a
	# cidade, o que é útil por si), então o aviso é no botão, não na opção inteira.
	_investigate.text = "PROFILING_INVESTIGATE" if has_story else "PROFILING_NO_STORY"

	_apply_tint(is_current or is_scheduled)
	_apply_progress(0.0)
	_on_focus_changed()


# A emoção desta opção. A tela usa pra pintar o filtro de cor com o tint dela.
func get_emotion() -> EmotionDefinition:
	return _emotion


# Começa o gesto de segurar. with_focus diz se ele veio do A (foco) ou do mouse — muda o que cancela.
func _start_hold(with_focus: bool) -> void:
	_is_holding = true
	_is_holding_with_focus = with_focus
	_hold_time = 0.0


# Para o gesto e devolve tudo ao lugar. Chamado ao soltar, ao sair com o mouse e ao completar — em
# todos os casos o retângulo esvazia, porque o que ficou pronto virou escolha e não precisa mais do
# desenho do gesto.
func _stop_hold() -> void:
	if not _is_holding:
		return
	_is_holding = false
	_is_holding_with_focus = false
	_hold_time = 0.0
	_apply_progress(0.0)
	hold_changed.emit(slot, 0.0)


# Desenha o progresso do gesto: o retângulo enchendo e o nome crescendo.
func _apply_progress(progress: float) -> void:
	if _fill == null or _label == null:
		return
	_fill.size = Vector2(size.x * progress, size.y)
	var scale_value: float = lerpf(1.0, hold_max_scale, progress)
	# O pivô no centro é o que faz o nome crescer no lugar, em vez de escorregar pra direita.
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2(scale_value, scale_value)


# Tinge as peças da cena com a cor da emoção. A moldura de destaque (mais grossa, também da cena) é
# a que marca a emoção vigente ou escolhida — é a mesma linguagem dos filtros do glossário, onde o
# retângulo preenchido é o que está ligado.
func _apply_tint(highlighted: bool) -> void:
	var tint: Color = _get_tint()
	_frame.self_modulate = Color(tint.r, tint.g, tint.b, idle_frame_opacity)
	_frame_highlight.self_modulate = tint
	_frame_highlight.visible = highlighted
	_fill.color = Color(tint.r, tint.g, tint.b, _fill.color.a)


# A cor da emoção, do recurso dela.
func _get_tint() -> Color:
	if _emotion == null:
		return Color.WHITE
	return _emotion.tint


func _on_investigate_pressed() -> void:
	investigate_requested.emit(slot)


# A opção só aceita foco com o controle em uso (ver MenuFocus.apply_joypad_focus_mode). O INVESTIGAR
# é um Button e aceita foco sempre, como os outros botões do jogo.
func _apply_focus_mode() -> void:
	MenuFocus.apply_joypad_focus_mode(self)


# O jogador pegou (ou largou) o controle: a opção passa a aceitar (ou recusar) o foco.
func _on_input_device_changed(_device: int) -> void:
	_apply_focus_mode()


# O destaque do foco: a moldura da opção fica opaca, como a de uma emoção escolhida, mas sem a
# moldura grossa — essa continua sendo só da emoção vigente/escolhida.
func _on_focus_changed() -> void:
	if _frame == null:
		return
	var tint: Color = _get_tint()
	_frame.self_modulate = Color(tint.r, tint.g, tint.b, 1.0 if has_focus() else idle_frame_opacity)
