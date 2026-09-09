class_name Player
extends CharacterBody2D

# Emitido só quando o estado de movimento (parado/andando, direção encarada) muda — não a cada
# frame. Emissor e ouvinte são o próprio Player (relação direta e permanente com o seu
# AnimatedSprite2D), por isso é um Signal direto e não um evento no EventBus; se no futuro outro
# sistema precisar reagir a isso (som de passo, poeira ao correr), dá pra escutar esse mesmo sinal
# sem mexer aqui.
signal movement_state_changed(is_moving: bool, facing_direction: FacingDirection, facing_right: bool)

enum FacingDirection { DOWN, UP, SIDE } #maquina de estado para direção do player

@export var speed: float = 300.0

var _is_moving: bool = false
var _facing_direction: FacingDirection = FacingDirection.DOWN
var _facing_right: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	movement_state_changed.connect(_on_movement_state_changed)
	print("[Player] - Controlador inicializado na posição %s" % [global_position])


func _physics_process(_delta: float) -> void:
	var input_direction: Vector2 = _get_input_direction()
	velocity = input_direction * speed
	move_and_slide()
	_update_movement_state(input_direction)


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Calcula o estado de movimento (parado/andando + direção encarada) a partir do input deste
# frame. Como o placeholder só tem 4 direções visuais, diagonais usam o eixo com maior magnitude
# pra decidir entre cima/baixo e lado. Sem input, mantém a última direção encarada. Só emite
# movement_state_changed quando esse estado é diferente do frame anterior — a troca de animação
# não precisa (e não deve) rodar a cada frame, só quando muda.
func _update_movement_state(input_direction: Vector2) -> void:
	var is_moving: bool = input_direction != Vector2.ZERO
	var facing_direction: FacingDirection = _facing_direction
	var facing_right: bool = _facing_right

	if is_moving:
		if absf(input_direction.x) > absf(input_direction.y):
			facing_direction = FacingDirection.SIDE
			facing_right = input_direction.x > 0.0
		elif input_direction.y < 0.0:
			facing_direction = FacingDirection.UP
		else:
			facing_direction = FacingDirection.DOWN

	if is_moving == _is_moving and facing_direction == _facing_direction and facing_right == _facing_right:
		return

	_is_moving = is_moving
	_facing_direction = facing_direction
	_facing_right = facing_right
	movement_state_changed.emit(_is_moving, _facing_direction, _facing_right)


# Reage à mudança de estado de movimento tocando a animação correspondente. Só roda quando
# movement_state_changed é emitido (ou seja, quando o estado muda de verdade), não a cada frame.
func _on_movement_state_changed(is_moving: bool, facing_direction: FacingDirection, facing_right: bool) -> void:
	# O sprite "Side" do placeholder olha pra esquerda por padrão; espelha só quando andando
	# pra direita. Mantido também parado, pra não "virar" o personagem ao soltar a tecla.
	_animated_sprite.flip_h = facing_direction == FacingDirection.SIDE and facing_right
	_animated_sprite.play(_get_animation_name(facing_direction, is_moving))


# Traduz a direção encarada pro nome da animação correspondente na SpriteFrames do
# AnimatedSprite2D — de corrida enquanto o jogador se move, de parado (idle) quando não.
func _get_animation_name(facing_direction: FacingDirection, is_moving: bool) -> StringName:
	match facing_direction:
		FacingDirection.UP:
			return &"run_up" if is_moving else &"idle_up"
		FacingDirection.SIDE:
			return &"run_side" if is_moving else &"idle_side"
		_:
			return &"run_down" if is_moving else &"idle_down"
