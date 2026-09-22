## ProfilingEmotionOption - uma das emoções na tela do espírito: o nome da emoção, o retângulo que
## enche enquanto o jogador segura, o checkmark de história resolvida e o botão INVESTIGAR.
##
## COMO USAR: ninguém instancia isto à mão. A ProfilingScreen cria uma opção por emoção do NPC e
## chama configure(). A opção não muda emoção nem abre história: ela avisa por signal.
##
## OS DOIS GESTOS, como o GDD pede:
##
##   segurar o botão esquerdo -> o nome cresce, o retângulo em volta enche, e quando enche a emoção
##                               do NPC passa a ser esta (a partir do dia seguinte). Soltar antes
##                               de encher cancela, sem efeito nenhum.
##   passar o mouse           -> aparece o botão INVESTIGAR logo embaixo, que abre a história.
##
## Segurar é gesto de mudar o mundo, e clicar é gesto de investigar: são intenções diferentes, e é
## por isso que o GDD separa uma no tempo de pressão e a outra num botão. Um clique curto em cima da
## emoção, por isso, não faz nada — e não deve fazer.
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

## Tamanho da fonte do nome da emoção.
@export var emotion_font_size: int = 34

## Espaço para variáveis

var slot: int = NPCDefinition.EmotionSlot.NEUTRAL

var _emotion: EmotionDefinition
var _is_holding: bool = false
var _hold_time: float = 0.0

var _frame: Panel
var _fill: ColorRect
var _label: Label
var _status: Label
var _investigate: Button

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(260.0, 110.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


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
	_investigate.visible = over_option or _investigate.get_global_rect().has_point(mouse)

	if _is_holding and not over_option:
		# Arrastar o mouse pra fora enquanto segura cancela o gesto: sem isso, o jogador trocaria a
		# emoção sem estar mais olhando pra ela.
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
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	accept_event()
	if mouse_button.pressed:
		_start_hold()
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
	_label.add_theme_color_override("font_color", _get_tint())

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

	_investigate.visible = false
	_investigate.disabled = not has_story
	# Emoção sem história escrita continua podendo ser escolhida (mudar a emoção do NPC muda a
	# cidade, o que é útil por si), então o aviso é no botão, não na opção inteira.
	_investigate.text = "PROFILING_INVESTIGATE" if has_story else "PROFILING_NO_STORY"

	_apply_progress(0.0)
	_refresh_frame(is_current or is_scheduled)


# A emoção desta opção. A tela usa pra pintar o filtro de cor com o tint dela.
func get_emotion() -> EmotionDefinition:
	return _emotion


func _start_hold() -> void:
	_is_holding = true
	_hold_time = 0.0


# Para o gesto e devolve tudo ao lugar. Chamado ao soltar, ao sair com o mouse e ao completar — em
# todos os casos o retângulo esvazia, porque o que ficou pronto virou escolha e não precisa mais do
# desenho do gesto.
func _stop_hold() -> void:
	if not _is_holding:
		return
	_is_holding = false
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


# A moldura da opção. Emoção vigente (ou escolhida) ganha borda cheia; as outras ficam vazadas — é a
# mesma linguagem dos filtros do glossário, onde o retângulo preenchido é o que está ligado.
func _refresh_frame(highlighted: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var tint: Color = _get_tint()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.16 if highlighted else 0.05)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.95 if highlighted else 0.45)
	style.set_border_width_all(3 if highlighted else 2)
	style.set_corner_radius_all(8)
	_frame.add_theme_stylebox_override("panel", style)


# A cor da emoção, do recurso dela. É por isso que a tela não tem "vermelho pra raiva, azul pra
# tristeza" escrito em lugar nenhum: a cor é conteúdo, e mora em EmotionDefinition.tint.
func _get_tint() -> Color:
	if _emotion == null:
		return Color.WHITE
	return _emotion.tint


func _build() -> void:
	_frame = Panel.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_fill = ColorRect.new()
	_fill.color = Color(1.0, 1.0, 1.0, 0.22)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# O nome da emoção já vem traduzido de EmotionDefinition.get_display_name().
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.add_theme_font_size_override("font_size", emotion_font_size)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.modulate = Color(1.0, 1.0, 1.0, 0.8)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	_investigate = Button.new()
	# Ancorado embaixo da opção, e não dentro dela: o GDD pede o botão "logo embaixo" da emoção.
	_investigate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_investigate.offset_top = 8.0
	_investigate.offset_bottom = 48.0
	_investigate.pressed.connect(_on_investigate_pressed)
	add_child(_investigate)


func _on_investigate_pressed() -> void:
	investigate_requested.emit(slot)
