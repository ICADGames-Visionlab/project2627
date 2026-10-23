## TopDown - a matemática do chão top-down 45°, num lugar só. Direção -> direção encarada, direção
## encarada -> nome de animação, direção -> velocidade de tela.
##
## Não é um Node e não guarda estado: são funções estáticas puras, chamadas por qualquer agente
## que ande no chão do jogo (`Player`, `NPC`, e o que vier).
##
## COMO USAR:
##
##     velocity = TopDown.screen_velocity(direction, speed, vertical_factor)
##     var facing: TopDown.Facing = TopDown.facing_from_direction(direction)
##     sprite.play(TopDown.animation_name(&"run", facing))
##
## POR QUE EXISTE SEPARADO DO PLAYER: o número de sensação (`vertical_speed_factor`) é balanceamento
## de cada agente e continua exposto com @export lá; a CONTA que consome esse número é a mesma para
## todo mundo e não pode divergir. Duas cópias da mesma conta é a garantia de que um dia o NPC vai
## andar num chão levemente diferente do chão do Player.
class_name TopDown
extends RefCounted

## Espaço para enums

# As 8 direções que um personagem pode encarar, nomeadas pelo rumo na tela e ordenadas a partir
# do leste no sentido horário — a mesma varredura que Vector2.angle() faz (no Godot o eixo Y
# cresce pra baixo, então ângulo positivo vai pro sul). Essa ordem não é decorativa: o valor de
# cada item é exatamente o ângulo da direção dividido por 45°, o que deixa a conversão de direção
# em animação ser uma conta só, sem cadeia de ifs (ver facing_from_direction).
enum Facing { E, SE, S, SW, W, NW, N, NE }

## Espaço para constantes

# Sufixo do nome da animação de cada Facing, na mesma ordem do enum — o valor do enum é o índice
# nesta lista.
const DIRECTION_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## Espaço para funções personalizadas

# Descobre qual das 8 direções um vetor representa, fatiando o círculo em setores de 45° e
# arredondando pro setor mais próximo. As 8 combinações de teclas caem exatamente no centro de um
# setor. Como o enum está na mesma ordem do ângulo, o índice do setor já é o valor do enum.
static func facing_from_direction(direction: Vector2) -> Facing:
	var sector: int = roundi(direction.angle() / (PI / 4.0))
	return posmod(sector, DIRECTION_SUFFIXES.size()) as Facing


# Monta o nome da animação a partir do prefixo (parado/andando/correndo) e do sufixo da direção. Os
# nomes montados aqui precisam existir na SpriteFrames do AnimatedSprite2D: idle_e, idle_se, ...,
# walk_e, walk_se, ..., run_e, run_se, ... — as 8 direções do spritesheet (ver
# res://resources/player_sprite_frames.tres).
static func animation_name(prefix: StringName, facing: Facing) -> StringName:
	return StringName("%s_%s" % [prefix, DIRECTION_SUFFIXES[facing]])


# Converte uma direção (do teclado, ou o deslocamento até um ponto do caminho) na velocidade final,
# em pixels de tela por segundo.
#
# O chão top-down não é achatado: a direção na tela é a própria direção pedida, e W+D anda a 45°.
# O que a câmera inclinada a 45° muda é só o MÓDULO: o fundo do chão está encurtado na tela, então
# vertical_factor interpola conforme o quanto a direção é vertical — horizontal puro anda a speed,
# vertical puro a speed * vertical_factor, e as diagonais no meio. A normalização deixa o módulo sob
# controle desse parâmetro só, seja a direção unitária (teclado) ou uma distância (caminho).
static func screen_velocity(direction: Vector2, speed: float, vertical_factor: float) -> Vector2:
	var screen_direction: Vector2 = direction.normalized()
	var verticality: float = absf(screen_direction.y)
	return screen_direction * speed * lerpf(1.0, vertical_factor, verticality)


# Quanto tempo, em segundos, um agente leva pra percorrer um caminho de tela a partir de `from`, andando
# como andaria de verdade: cada trecho na velocidade que o screen_velocity dá pra aquela direção (mais
# devagar quanto mais vertical). É a MESMA conta do movimento, chamada em vez de reescrita, pelo motivo de
# este arquivo existir: duas cópias da conta é a garantia de elas divergirem. Serve pra calcular quando um
# NPC chega a um ponto sem precisar simular a caminhada (ver NPCRoutineException.TravelTimes).
static func walk_seconds(from: Vector2, path: PackedVector2Array, speed: float, vertical_factor: float) -> float:
	var seconds: float = 0.0
	var cursor: Vector2 = from
	for point: Vector2 in path:
		var delta: Vector2 = point - cursor
		var velocity: Vector2 = screen_velocity(delta, speed, vertical_factor)
		if delta != Vector2.ZERO and velocity.length() > 0.0:
			seconds += delta.length() / velocity.length()
		cursor = point
	return seconds
