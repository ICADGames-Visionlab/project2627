class_name Player
extends CharacterBody2D

## Controlador do jogador: movimento em 8 direções (teclado AWSD/setinhas e analógico do
## joystick) e troca de animação entre as 4 direções visuais disponíveis no placeholder atual
## (cima, baixo e lado — o lado é espelhado horizontalmente para representar direita/esquerda).
## A câmera do jogador (PhantomCamera2D, filha desta cena) é quem decide o enquadramento; este
## script não sabe nada sobre câmera, apenas sobre movimento e animação.

## As 4 direções visuais disponíveis nos placeholders (images/placeholder/player). Direções
## diagonais de movimento caem na direção visual do eixo dominante (ver _update_animation).
enum FacingDirection { DOWN, UP, SIDE }

@export var speed: float = 300.0

var _facing_direction: FacingDirection = FacingDirection.DOWN
var _facing_right: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	print("[Player] - Controlador inicializado na posição %s" % [global_position])


func _physics_process(_delta: float) -> void:
	var input_direction: Vector2 = _get_input_direction()
	velocity = input_direction * speed
	move_and_slide()
	_update_animation(input_direction)


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Escolhe a animação de corrida correspondente à direção do input, ou volta pro primeiro quadro
# (parado) quando não há input. Como o placeholder só tem 4 direções visuais, diagonais usam o
# eixo com maior magnitude para decidir entre cima/baixo e lado.
func _update_animation(input_direction: Vector2) -> void:
	if input_direction == Vector2.ZERO:
		_animated_sprite.stop()
		return

	if absf(input_direction.x) > absf(input_direction.y):
		_facing_direction = FacingDirection.SIDE
		_facing_right = input_direction.x > 0.0
	elif input_direction.y < 0.0:
		_facing_direction = FacingDirection.UP
	else:
		_facing_direction = FacingDirection.DOWN

	# O sprite "Side" do placeholder olha pra esquerda por padrão; espelha só quando andando
	# pra direita.
	_animated_sprite.flip_h = _facing_direction == FacingDirection.SIDE and _facing_right

	var animation_name: StringName = _get_animation_name()
	if _animated_sprite.animation != animation_name or not _animated_sprite.is_playing():
		_animated_sprite.play(animation_name)


# Traduz o enum de direção atual pro nome da animação correspondente na SpriteFrames do
# AnimatedSprite2D.
func _get_animation_name() -> StringName:
	match _facing_direction:
		FacingDirection.UP:
			return &"run_up"
		FacingDirection.SIDE:
			return &"run_side"
		_:
			return &"run_down"
