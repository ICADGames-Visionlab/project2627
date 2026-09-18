# DialoguePortrait.gd — O retrato do NPC ao lado da coluna de diálogo: fundo, imagem e moldura.
#
# Desenha tudo em _draw. Sem arte (NPCDefinition.portrait vazio), mostra uma silhueta na cor de
# diálogo do NPC. PLACEHOLDER até a arte final: no mesmo espírito do DialoguePlaceholderAudio, o
# jogo avisa no log, uma vez por NPC, quando cai na silhueta.
class_name DialoguePortrait
extends Control

# Geometria da silhueta, em fração do tamanho do retrato. É desenho de placeholder, não "look" do
# diálogo: por isso mora aqui e não no DialogueStyle.
const _HEAD_CENTER_Y: float = 0.38
const _HEAD_RADIUS: float = 0.17
const _SHOULDER_HALF_WIDTH: float = 0.38
const _SHOULDER_HEIGHT: float = 0.32
const _SHOULDER_STEPS: int = 24

static var _warned_placeholder: Dictionary = {}

var _style: DialogueStyle
var _texture: Texture2D
var _tint: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_npc(npc: NPCDefinition, style: DialogueStyle) -> void:
	_style = style
	_texture = npc.portrait
	_tint = npc.dialogue_color
	if _texture == null and not _warned_placeholder.has(npc.id):
		_warned_placeholder[npc.id] = true
		print("[Dialogue] - PLACEHOLDER: NPC \"%s\" sem portrait; o diálogo usa uma silhueta (NPCDefinition, grupo Diálogo)" % npc.id)
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, _style.portrait_bg_color)
	if _texture != null:
		_draw_texture_cover(rect)
	else:
		_draw_placeholder(rect)
	# draw_rect sem preenchimento centra o traço na borda: recuar meia largura mantém a moldura
	# inteira dentro do retrato.
	draw_rect(rect.grow(-_style.portrait_frame_width * 0.5), _style.portrait_frame_color, false,
		_style.portrait_frame_width)


# Preenche o retrato inteiro sem distorcer a imagem. O corte que sobra vem de baixo: num busto, o
# rosto está no alto.
func _draw_texture_cover(rect: Rect2) -> void:
	var texture_size: Vector2 = _texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var fit: float = maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var source_size: Vector2 = rect.size / fit
	var source_position := Vector2((texture_size.x - source_size.x) * 0.5, 0.0)
	draw_texture_rect_region(_texture, rect, Rect2(source_position, source_size))


func _draw_placeholder(rect: Rect2) -> void:
	var color := Color(_tint, _style.portrait_placeholder_alpha)
	var center_x: float = rect.size.x * 0.5
	draw_circle(Vector2(center_x, rect.size.y * _HEAD_CENTER_Y), rect.size.y * _HEAD_RADIUS, color)

	# Ombros: meia elipse apoiada na base do retrato, do canto direito ao esquerdo por cima.
	var shoulders := PackedVector2Array()
	for step: int in _SHOULDER_STEPS + 1:
		var angle: float = PI * float(step) / float(_SHOULDER_STEPS)
		shoulders.append(Vector2(
			center_x + cos(angle) * rect.size.x * _SHOULDER_HALF_WIDTH,
			rect.size.y - sin(angle) * rect.size.y * _SHOULDER_HEIGHT))
	draw_colored_polygon(shoulders, color)
