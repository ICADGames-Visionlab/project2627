# InsightMarker.gd — O orbe: desenha um ponto clicável e nada mais.
#
# Não decide cor, não decide se existe e não sabe o que vai ser lido: recebe a cor pronta de quem o
# criou (verde do canal de ambiente, ou a cor da cabeça que está falando) e devolve o clique por um
# signal local. É o que permite uma cabeça nova ser um .tres novo, sem tocar em código de marcador.
#
# Estados que o orbe precisa comunicar à distância, porque não há tecla para revelar nada e tudo
# fica sempre na tela:
#   cheio = tem novidade      vazado = já lido
#
# E o que ele comunica de perto, quando o mouse passa por cima ou o controle o seleciona:
#   cresce e mostra a mãozinha   = o clique vai abrir
#   anel branco em volta         = é o orbe que a tecla/botão de interagir vai acionar
#
# Não existe alcance de clique: o orbe abre de qualquer distância. Quem limita o que aparece é a
# fonte (portas e, no canal de personagem, o raio), nunca o marcador.
#
# Toda a animação (pulsação, destaque, flash) é desenhada, e não aplicada ao scale do nó: a forma de
# colisão é filha do nó, e encolher o nó na pulsação encolheria também a área de clique — com o
# mouse parado na borda, o orbe entraria e sairia do hover a cada batida.
#
# O orbe vive na camada de física "insight_orbs" (16), só dele. Na camada do mundo, qualquer Area2D
# futura que escute area_entered passaria a detectar orbes.
#
# PLACEHOLDER: o orbe é desenhado em código (círculo e glifo). A arte final substitui _draw() sem
# mexer no resto — ver a issue de substituição de placeholder.
class_name InsightMarker
extends Area2D

# Emitido no acionamento — clique ou tecla de interagir. Signal local, e não evento de bus: o ouvinte
# é sempre quem instanciou o marcador (a fonte ou a órbita), relação direta e permanente — ver
# docs/event_bus.md.
signal clicked
# Emitido quando o orbe entra ou sai de destaque (mouse em cima ou foco do controle). A órbita usa
# para ligar o orbe de cabeça à fonte de que ele está falando.
signal highlight_changed(is_highlighted: bool)
# Emitido quando um orbe que estava vazado volta a ter novidade — uma flag abriu um insight novo no
# mesmo lugar. Quem instanciou sabe dizer qual orbe foi, e é quem imprime o log.
signal rekindled

@export_group("Aparência")
@export var radius: float = 16.0
# Raio da área de clique. Maior que o desenho de propósito: o orbe é pequeno, pulsa, e o de cabeça
# anda junto com o jogador. Ninguém percebe a folga, só percebe que o clique "pega".
@export var hit_radius: float = 26.0
@export var outline_width: float = 3.0
@export var halo_scale: float = 1.7
# Opacidade de um orbe já lido. Baixa o bastante para o olho separar lido de não lido de longe, alta
# o bastante para o orbe continuar sendo um convite.
@export var read_alpha: float = 0.5
@export var glyph_font_size: int = 18

@export_group("Destaque")
# Quanto o orbe cresce com o mouse em cima ou com o foco do controle.
@export var highlight_scale: float = 1.25
# Tempo, em segundos, para crescer até o tamanho de destaque (e para voltar).
@export var highlight_time: float = 0.08
# Tamanho do anel de foco do controle, em múltiplos do raio.
@export var focus_ring_scale: float = 2.0
# Distância entre o topo do halo e o texto de dica.
@export var hint_gap: float = 6.0
@export var hint_font_size: int = 16

@export_group("Animação")
# Amplitude da pulsação do orbe com novidade, em fração do tamanho. Zero desliga a animação.
@export var pulse_amplitude: float = 0.08
@export var pulse_speed: float = 2.5
# Duração do flash de quando um orbe vazado volta a ter novidade.
@export var rekindle_duration: float = 0.7
# Até onde o anel do flash se expande, em múltiplos do raio.
@export var rekindle_ring_scale: float = 3.5

# Orbes com o mouse em cima que pediram a mãozinha. Estático porque o cursor é um só para o jogo
# inteiro: com dois orbes sobrepostos, sair de um não pode devolver a seta enquanto o mouse ainda
# está sobre o outro.
static var _pointer_owners: Dictionary = {}    # int(instance_id) -> true

var _color: Color = Color.WHITE
var _glyph: String = ""
var _hover_text_key: String = ""
var _is_read: bool = false
var _is_hovered: bool = false
var _is_focused: bool = false
var _was_highlighted: bool = false
var _pulse_time: float = 0.0
# 0 = tamanho normal, 1 = tamanho de destaque. Interpolado, para o crescimento não ser um salto.
var _highlight_amount: float = 0.0
var _rekindle_left: float = 0.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _glyph_label: Label = $Glyph
@onready var _hint_label: Label = $Hint


func _ready() -> void:
	input_pickable = true
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_apply_appearance()


func _exit_tree() -> void:
	# Orbe liberado com o mouse em cima (o jogador leu o último insight dali) não recebe
	# mouse_exited: sem isto, a mãozinha ficaria presa no cursor.
	_set_pointer_owner(false)


func _notification(what: int) -> void:
	# Clicar num orbe de cabeça pausa o jogo com o mouse ainda em cima dele. Soltar o hover aqui
	# garante que a tela de diálogo não herda a mãozinha, sem depender de a engine emitir
	# mouse_exited para um objeto pausado.
	if what == NOTIFICATION_PAUSED and _is_hovered:
		_is_hovered = false
		_apply_appearance()


func _process(delta: float) -> void:
	if _should_pulse():
		_pulse_time += delta * pulse_speed
	var step: float = delta / maxf(highlight_time, 0.001)
	_highlight_amount = move_toward(_highlight_amount, _highlight_target(), step)
	_rekindle_left = maxf(_rekindle_left - delta, 0.0)
	_update_animated_state()
	_update_processing()


func _draw() -> void:
	var rekindle_progress: float = _rekindle_progress()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _visual_scale())
	draw_circle(Vector2.ZERO, radius * halo_scale, Color(_color, 0.18))
	if _rekindle_left > 0.0:
		# Anel que se expande e some: é o que chama o olho para um orbe que acendeu longe da atenção.
		var ring_radius: float = radius * lerpf(1.0, rekindle_ring_scale, rekindle_progress)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, Color(_color, 1.0 - rekindle_progress), outline_width, true)
	if _is_focused:
		draw_arc(Vector2.ZERO, radius * focus_ring_scale, 0.0, TAU, 40, Color(Color.WHITE, 0.85), 2.0, true)
	if _is_read:
		# Vazado: o contorno sozinho é o que se lê de longe como "já li isto".
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _color, outline_width, true)
		return
	var fill_color: Color = _color.lightened(0.6 * (1.0 - rekindle_progress)) if _rekindle_left > 0.0 else _color
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _color.lightened(0.35), outline_width * 0.6, true)


# Define quem este orbe representa: a cor de quem fala e o glifo que o identifica sem depender de
# cor. Chamado por quem instancia o marcador, nunca decidido aqui dentro.
func configure(color: Color, glyph: String) -> void:
	_color = color
	_glyph = glyph
	if is_node_ready():
		_apply_appearance()


# Define o texto mostrado sobre o orbe em destaque (o nome da cabeça, no canal de personagem).
# Recebe a chave, nunca o texto: tr() é chamado na exibição.
func set_hover_text_key(text_key: String) -> void:
	_hover_text_key = text_key
	if is_node_ready():
		_update_hint()


# Diz ao orbe se o que ele representa já foi lido. Muda o desenho (cheio/vazado) e desliga a
# pulsação — orbe lido não pede atenção. Voltar de lido para novo dispara o flash.
func set_read(is_read: bool) -> void:
	if _is_read == is_read:
		return
	var is_rekindling: bool = _is_read and not is_read
	_is_read = is_read
	if is_rekindling:
		_rekindle_left = rekindle_duration
		rekindled.emit()
	if is_node_ready():
		_apply_appearance()


# Liga ou desliga o foco do teclado/controle. Quem decide qual orbe tem foco é o InsightInteractor;
# o orbe só desenha o anel e entra em destaque.
func set_focused(is_focused: bool) -> void:
	if _is_focused == is_focused:
		return
	_is_focused = is_focused
	if is_node_ready():
		_apply_appearance()


# Aciona o orbe como um clique. É o único caminho até o signal clicked, usado pelo clique do mouse e
# pela tecla de interagir — a fonte e a órbita não sabem, e não precisam saber, qual dos dois foi.
func activate() -> void:
	clicked.emit()


# Diz se um evento de mouse caiu dentro da área de clique deste orbe. Existe para quem precisa saber
# disso ANTES do physics picking (a caixa de texto, em _unhandled_input): a regra de acerto fica aqui,
# junto da forma de colisão, e não copiada em outro script.
func is_mouse_event_inside(event: InputEventMouse) -> bool:
	var local_event: InputEventMouse = make_input_local(event) as InputEventMouse
	return local_event.position.length() <= maxf(hit_radius, radius)


# Aplica cor, glifo, opacidade, dica, cursor e estado da animação de uma vez só. Ponto único de
# decisão visual: separar isso em vários lugares é como um estado acaba desenhado pela metade.
func _apply_appearance() -> void:
	var circle_shape: CircleShape2D = _collision_shape.shape as CircleShape2D
	if circle_shape == null:
		circle_shape = CircleShape2D.new()
		_collision_shape.shape = circle_shape
	circle_shape.radius = maxf(hit_radius, radius)

	_glyph_label.text = _glyph
	_glyph_label.visible = not _glyph.is_empty()
	_glyph_label.add_theme_font_size_override(&"font_size", glyph_font_size)
	# Orbe cheio pede texto escuro; orbe vazado não tem fundo, então o glifo assume a cor do orbe.
	_glyph_label.add_theme_color_override(&"font_color", _color if _is_read else Color(0.08, 0.08, 0.1))
	modulate.a = read_alpha if _is_read else 1.0

	_update_hint()
	_set_pointer_owner(_is_hovered)
	_update_highlight_signal()
	_update_animated_state()
	_update_processing()


# Atualiza o que muda a cada quadro de animação: a escala do glifo e o desenho.
func _update_animated_state() -> void:
	_glyph_label.pivot_offset = _glyph_label.size * 0.5
	_glyph_label.scale = Vector2.ONE * _visual_scale()
	queue_redraw()


# Mostra, esconde e posiciona o texto sobre o orbe em destaque.
func _update_hint() -> void:
	_hint_label.visible = _is_highlighted() and not _hover_text_key.is_empty()
	if not _hint_label.visible:
		return
	_hint_label.text = tr(_hover_text_key)
	_hint_label.add_theme_font_size_override(&"font_size", hint_font_size)
	var halo_top: float = radius * halo_scale * highlight_scale + hint_gap
	_hint_label.position.y = -halo_top - _hint_label.size.y


# Liga o processamento só enquanto há algo animando. Um mundo de orbes lidos e parados não precisa
# gastar _process nenhum.
func _update_processing() -> void:
	var is_settling: bool = not is_equal_approx(_highlight_amount, _highlight_target())
	set_process(_should_pulse() or is_settling or _rekindle_left > 0.0)


# Emite highlight_changed só na transição, e não a cada atualização de aparência.
func _update_highlight_signal() -> void:
	var is_highlighted: bool = _is_highlighted()
	if is_highlighted == _was_highlighted:
		return
	_was_highlighted = is_highlighted
	highlight_changed.emit(is_highlighted)


# Registra (ou retira) este orbe como dono da mãozinha do cursor e aplica o cursor resultante. Só
# mexe no cursor quando a posse muda, para não sobrescrever a cada quadro um cursor que outro
# sistema tenha definido.
func _set_pointer_owner(wants_pointer: bool) -> void:
	var key: int = get_instance_id()
	if _pointer_owners.has(key) == wants_pointer:
		return
	if wants_pointer:
		_pointer_owners[key] = true
	else:
		_pointer_owners.erase(key)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if _pointer_owners.is_empty() else Input.CURSOR_POINTING_HAND)


# Diz se o orbe está em destaque: mouse em cima ou foco do controle.
func _is_highlighted() -> bool:
	return _is_hovered or _is_focused


# Tamanho de destaque desejado agora.
func _highlight_target() -> float:
	return 1.0 if _is_highlighted() else 0.0


# Diz se o orbe deve pulsar. Só o orbe com novidade pulsa: um mundo inteiro de orbes lidos pulsando
# junto seria ruído puro.
func _should_pulse() -> bool:
	return not _is_read and pulse_amplitude > 0.0


# Escala visual combinada da pulsação e do destaque.
func _visual_scale() -> float:
	var pulse: float = 1.0 + sin(_pulse_time) * pulse_amplitude if _should_pulse() else 1.0
	return pulse * lerpf(1.0, highlight_scale, _highlight_amount)


# Progresso do flash de reacender, de 0 (começou) a 1 (terminou).
func _rekindle_progress() -> float:
	if rekindle_duration <= 0.0:
		return 1.0
	return 1.0 - _rekindle_left / rekindle_duration


# Aceita o clique esquerdo e consome o evento. Sem set_input_as_handled(), o mesmo clique continua
# viajando para quem estiver atrás do orbe — e isso reaparece semanas depois como bug intermitente
# caro de achar. Na cidade, o InsightInteractor resolve o clique antes (para ele não virar movimento)
# e este caminho nem chega a rodar; ele continua valendo em qualquer cena sem o Player.
func _on_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	activate()


# Entrada do mouse na área de clique.
func _on_mouse_entered() -> void:
	_is_hovered = true
	_apply_appearance()


# Saída do mouse da área de clique.
func _on_mouse_exited() -> void:
	_is_hovered = false
	_apply_appearance()
