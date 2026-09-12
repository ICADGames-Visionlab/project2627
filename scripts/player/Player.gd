class_name Player
extends CharacterBody2D

# Emitido só quando o estado de movimento (parado/andando, direção encarada) muda — não a cada
# frame. Emissor e ouvinte são o próprio Player (relação direta e permanente com o seu
# AnimatedSprite2D), por isso é um Signal direto e não um evento no EventBus; se no futuro outro
# sistema precisar reagir a isso (som de passo, poeira ao correr), dá pra escutar esse mesmo sinal
# sem mexer aqui.
signal movement_state_changed(is_moving: bool, facing_direction: FacingDirection)

# As 8 direções que o personagem pode encarar, nomeadas pelo rumo na tela e ordenadas a partir do
# leste no sentido horário — a mesma varredura que Vector2.angle() faz (no Godot o eixo Y cresce
# pra baixo, então ângulo positivo vai pro sul). Essa ordem não é decorativa: o valor de cada
# item é exatamente o ângulo do input dividido por 45°, o que deixa a conversão de direção em
# animação ser uma conta só, sem cadeia de ifs (ver _get_facing_direction).
enum FacingDirection { E, SE, S, SW, W, NW, N, NE }

# Sufixo do nome da animação de cada FacingDirection, na mesma ordem do enum — o valor do enum é
# o índice nesta lista.
const DIRECTION_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

@export var speed: float = 300.0

# Quanto o eixo Y da velocidade é achatado pra que o personagem ande sobre o plano isométrico do
# chão. O teclado não sabe que o mundo é isométrico e entrega um input cartesiano; sem achatar
# nada, andar pra cima/baixo cobriria o dobro de tiles que andar pros lados.
#
# 0.5 é o valor geometricamente correto: é a razão do losango do tile (64 / 128, ver o TileSet em
# main.tscn) e faz as 8 direções percorrerem a mesma distância em tiles por segundo. O problema é
# que o sprite do personagem é desenhado de cima, sem achatamento nenhum, e o olho usa ele de
# régua — então a 0.5 subir e descer *parece* metade da velocidade mesmo estando certo. Valores
# mais altos trocam exatidão geométrica por sensação: a 1.0 não há achatamento (movimento puro de
# tela, como era no top-down). Campo de balanceamento — ajuste no Inspector até ficar bom.
@export_range(0.5, 1.0, 0.01) var isometric_y_ratio: float = 0.5

var _is_moving: bool = false
var _facing_direction: FacingDirection = FacingDirection.S

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	movement_state_changed.connect(_on_movement_state_changed)
	print("[Player] - Controlador inicializado na posição %s" % [global_position])


func _physics_process(_delta: float) -> void:
	var input_direction: Vector2 = _get_input_direction()
	velocity = _to_isometric(input_direction) * speed
	move_and_slide()
	_update_movement_state(input_direction)


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Projeta uma direção cartesiana do input no plano isométrico do chão, achatando o eixo Y.
# De propósito não normaliza de novo depois de achatar: renormalizar devolveria a velocidade
# vertical que o achatamento tirou e o personagem voltaria a cruzar tiles mais rápido indo pra
# cima/baixo do que indo pros lados, que é justo o que essa conta existe pra corrigir.
func _to_isometric(direction: Vector2) -> Vector2:
	return Vector2(direction.x, direction.y * isometric_y_ratio)


# Calcula o estado de movimento (parado/andando + direção encarada) a partir do input deste
# frame. Sem input, mantém a última direção encarada. Só emite movement_state_changed quando
# esse estado é diferente do frame anterior — a troca de animação não precisa (e não deve) rodar
# a cada frame, só quando muda.
func _update_movement_state(input_direction: Vector2) -> void:
	var is_moving: bool = input_direction != Vector2.ZERO
	var facing_direction: FacingDirection = _facing_direction

	if is_moving:
		facing_direction = _get_facing_direction(input_direction)

	if is_moving == _is_moving and facing_direction == _facing_direction:
		return

	_is_moving = is_moving
	_facing_direction = facing_direction
	movement_state_changed.emit(_is_moving, _facing_direction)


# Descobre qual das 8 direções o input representa, fatiando o círculo em setores de 45° e
# arredondando pro setor mais próximo. Usa o input cartesiano e não a velocidade já achatada de
# propósito: no input as 8 combinações de teclas caem exatamente no centro de um setor, enquanto
# no vetor achatado as diagonais caem perto da fronteira entre dois setores e a animação poderia
# oscilar. Como o enum está na mesma ordem do ângulo, o índice do setor já é o valor do enum.
func _get_facing_direction(input_direction: Vector2) -> FacingDirection:
	var sector: int = roundi(input_direction.angle() / (PI / 4.0))
	return posmod(sector, DIRECTION_SUFFIXES.size()) as FacingDirection


# Reage à mudança de estado de movimento tocando a animação correspondente. Só roda quando
# movement_state_changed é emitido (ou seja, quando o estado muda de verdade), não a cada frame.
func _on_movement_state_changed(is_moving: bool, facing_direction: FacingDirection) -> void:
	_animated_sprite.play(_get_animation_name(facing_direction, is_moving))


# Monta o nome da animação a partir do prefixo (correndo/parado) e do sufixo da direção. Os nomes
# montados aqui precisam existir na SpriteFrames do AnimatedSprite2D: idle_e, idle_se, ..., run_e,
# run_se, ... — as 8 direções do spritesheet, que já vêm desenhadas e por isso dispensam o flip_h
# que o placeholder anterior, de 4 direções, precisava.
func _get_animation_name(facing_direction: FacingDirection, is_moving: bool) -> StringName:
	var prefix: StringName = &"run" if is_moving else &"idle"
	return StringName("%s_%s" % [prefix, DIRECTION_SUFFIXES[facing_direction]])
