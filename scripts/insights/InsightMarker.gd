# InsightMarker.gd — O orbe: desenha um ponto clicável e nada mais.
#
# Não decide cor, não decide se existe e não sabe o que vai ser lido: recebe a cor pronta de quem o
# criou (verde do canal de ambiente, ou a cor da cabeça que está falando) e devolve o clique por um
# signal local. É o que permite uma cabeça nova ser um .tres novo, sem tocar em código de marcador.
#
# Estados que o orbe precisa comunicar à distância, porque não há tecla para revelar nada e tudo
# fica sempre na tela:
#   cheio    = tem novidade      vazado = já lido
#   opaco    = dá para clicar    apagado = precisa chegar mais perto
#
# PLACEHOLDER: o orbe é desenhado em código (círculo e glifo). A arte final substitui _draw() sem
# mexer no resto — ver a issue de substituição de placeholder.
class_name InsightMarker
extends Area2D

# Emitido no clique válido. Signal local, e não evento de bus: o ouvinte é sempre quem instanciou o
# marcador (a fonte ou a órbita), relação direta e permanente — ver docs/event_bus.md.
signal clicked

@export_group("Aparência")
@export var radius: float = 16.0
@export var outline_width: float = 3.0
@export var halo_scale: float = 1.7
# Opacidade de um orbe já lido. Baixa o bastante para o olho separar lido de não lido de longe, alta
# o bastante para o orbe continuar sendo um convite.
@export var read_alpha: float = 0.5
# Opacidade de um orbe fora do alcance de clique. Ele continua visível de propósito: é o convite
# para ir até lá.
@export var out_of_range_alpha: float = 0.4
@export var glyph_font_size: int = 18

@export_group("Animação")
# Amplitude da pulsação do orbe com novidade, em fração do tamanho. Zero desliga a animação.
@export var pulse_amplitude: float = 0.08
@export var pulse_speed: float = 2.5

var _color: Color = Color.WHITE
var _glyph: String = ""
var _is_read: bool = false
var _is_clickable: bool = true
var _pulse_time: float = 0.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _glyph_label: Label = $Glyph


func _ready() -> void:
	input_pickable = true
	input_event.connect(_on_input_event)
	_apply_appearance()


func _process(delta: float) -> void:
	# Só o orbe com novidade pulsa: um mundo inteiro de orbes lidos pulsando junto seria ruído puro.
	_pulse_time += delta * pulse_speed
	scale = Vector2.ONE * (1.0 + sin(_pulse_time) * pulse_amplitude)


func _draw() -> void:
	var halo_color: Color = Color(_color, 0.18)
	draw_circle(Vector2.ZERO, radius * halo_scale, halo_color)
	if _is_read:
		# Vazado: o contorno sozinho é o que se lê de longe como "já li isto".
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _color, outline_width, true)
		return
	draw_circle(Vector2.ZERO, radius, _color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _color.lightened(0.35), outline_width * 0.6, true)


# Define quem este orbe representa: a cor de quem fala e o glifo que o identifica sem depender de
# cor. Chamado por quem instancia o marcador, nunca decidido aqui dentro.
func configure(color: Color, glyph: String) -> void:
	_color = color
	_glyph = glyph
	if is_node_ready():
		_apply_appearance()


# Diz ao orbe se o que ele representa já foi lido. Muda o desenho (cheio/vazado) e desliga a
# pulsação — orbe lido não pede atenção.
func set_read(is_read: bool) -> void:
	if _is_read == is_read:
		return
	_is_read = is_read
	if is_node_ready():
		_apply_appearance()


# Diz ao orbe se o jogador está perto o bastante para clicar. Fora do alcance ele continua desenhado,
# só apagado: um orbe clicável do outro lado da tela deixaria o personagem irrelevante.
func set_clickable(is_clickable: bool) -> void:
	if _is_clickable == is_clickable:
		return
	_is_clickable = is_clickable
	if is_node_ready():
		_apply_appearance()


# Aplica cor, glifo, opacidade e estado da animação de uma vez só. Ponto único de decisão visual:
# separar isso em vários lugares é como um estado acaba desenhado pela metade.
func _apply_appearance() -> void:
	var circle_shape: CircleShape2D = _collision_shape.shape as CircleShape2D
	if circle_shape == null:
		circle_shape = CircleShape2D.new()
		_collision_shape.shape = circle_shape
	circle_shape.radius = radius

	_glyph_label.text = _glyph
	_glyph_label.visible = not _glyph.is_empty()
	_glyph_label.add_theme_font_size_override(&"font_size", glyph_font_size)
	# Orbe cheio pede texto escuro; orbe vazado não tem fundo, então o glifo assume a cor do orbe.
	_glyph_label.add_theme_color_override(&"font_color", _color if _is_read else Color(0.08, 0.08, 0.1))

	modulate.a = minf(read_alpha if _is_read else 1.0, 1.0 if _is_clickable else out_of_range_alpha)
	var should_pulse: bool = not _is_read and _is_clickable and pulse_amplitude > 0.0
	set_process(should_pulse)
	if not should_pulse:
		scale = Vector2.ONE
	queue_redraw()


# Aceita o clique esquerdo dentro do alcance e consome o evento. Sem set_input_as_handled(), o mesmo
# clique continua viajando para quem estiver atrás do orbe — e isso reaparece semanas depois como
# bug intermitente caro de achar.
func _on_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _is_clickable:
		return
	get_viewport().set_input_as_handled()
	clicked.emit()
