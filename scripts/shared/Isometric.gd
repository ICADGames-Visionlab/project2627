## Isometric - a matemática do chão isométrico, num lugar só. Direção de input -> direção
## encarada, direção encarada -> nome de animação, direção de input -> velocidade de tela.
##
## Não é um Node e não guarda estado: são funções estáticas puras, chamadas por qualquer agente
## que ande no chão do jogo (`Player`, `NPC`, e o que vier).
##
## COMO USAR:
##
##     velocity = Isometric.screen_velocity(input_dir, speed, y_ratio, vertical_factor)
##     var facing: Isometric.Facing = Isometric.facing_from_direction(input_dir)
##     sprite.play(Isometric.animation_name(&"run", facing))
##
## POR QUE EXISTE SEPARADO DO PLAYER: os números de achatamento (`isometric_y_ratio`) e de
## sensação (`vertical_speed_factor`) são balanceamento de cada agente e continuam expostos com
## @export lá; a CONTA que consome esses números é a mesma para todo mundo e não pode divergir.
## Duas cópias da mesma conta é a garantia de que um dia o NPC vai andar num chão levemente
## diferente do chão do Player.
class_name Isometric
extends RefCounted

## Espaço para enums

# As 8 direções que um personagem pode encarar, nomeadas pelo rumo na tela e ordenadas a partir
# do leste no sentido horário — a mesma varredura que Vector2.angle() faz (no Godot o eixo Y
# cresce pra baixo, então ângulo positivo vai pro sul). Essa ordem não é decorativa: o valor de
# cada item é exatamente o ângulo do input dividido por 45°, o que deixa a conversão de direção
# em animação ser uma conta só, sem cadeia de ifs (ver facing_from_direction).
enum Facing { E, SE, S, SW, W, NW, N, NE }

## Espaço para constantes

# Sufixo do nome da animação de cada Facing, na mesma ordem do enum — o valor do enum é o índice
# nesta lista.
const DIRECTION_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## Espaço para funções personalizadas

# Descobre qual das 8 direções um vetor representa, fatiando o círculo em setores de 45° e
# arredondando pro setor mais próximo.
#
# Espera o vetor CARTESIANO (o que o teclado produz), não a velocidade já achatada: no cartesiano
# as 8 combinações de teclas caem exatamente no centro de um setor, enquanto no vetor achatado as
# diagonais caem perto da fronteira entre dois setores e a animação poderia oscilar. Como o enum
# está na mesma ordem do ângulo, o índice do setor já é o valor do enum.
static func facing_from_direction(direction: Vector2) -> Facing:
	var sector: int = roundi(direction.angle() / (PI / 4.0))
	return posmod(sector, DIRECTION_SUFFIXES.size()) as Facing


# Monta o nome da animação a partir do prefixo (correndo/parado) e do sufixo da direção. Os nomes
# montados aqui precisam existir na SpriteFrames do AnimatedSprite2D: idle_e, idle_se, ..., run_e,
# run_se, ... — as 8 direções do spritesheet (ver res://resources/player_sprite_frames.tres).
static func animation_name(prefix: StringName, facing: Facing) -> StringName:
	return StringName("%s_%s" % [prefix, DIRECTION_SUFFIXES[facing]])


# Converte a direção cartesiana do input na velocidade final, em pixels de tela por segundo.
#
# Três etapas com responsabilidades separadas, e vale manter assim porque cada uma resolve um
# problema diferente:
#
#   1. O achatamento em Y decide a DIREÇÃO — é ele que faz W+D andar em cima da diagonal do grid
#      isométrico (onde correm as ruas) em vez de a 45° na tela.
#   2. A normalização tira o corte de velocidade que o achatamento causaria de tabela, deixando o
#      módulo sob controle de um parâmetro só, em vez de ser efeito colateral da geometria.
#   3. vertical_factor decide o MÓDULO, interpolando conforme o quanto a direção é vertical na
#      tela: horizontal puro anda a speed, vertical puro a speed * vertical_factor, e as
#      diagonais no meio.
static func screen_velocity(direction: Vector2, speed: float, y_ratio: float, vertical_factor: float) -> Vector2:
	var screen_direction: Vector2 = Vector2(direction.x, direction.y * y_ratio).normalized()
	var verticality: float = absf(screen_direction.y)
	return screen_direction * speed * lerpf(1.0, vertical_factor, verticality)


# Desfaz o achatamento: recebe um deslocamento medido na TELA (a distância até um ponto do
# caminho, por exemplo) e devolve a direção cartesiana que o teclado produziria pra ir até lá.
#
# É a inversa de screen_velocity no eixo Y, e serve justamente pra encadear as duas: aplicar esta
# aqui e depois screen_velocity faz as contas se cancelarem no Y, e o agente anda em linha reta
# até o ponto (o vertical_factor muda só a rapidez do trajeto, não o rumo).
static func to_cartesian(screen_delta: Vector2, y_ratio: float) -> Vector2:
	return Vector2(screen_delta.x, screen_delta.y / y_ratio).normalized()


# Quanto tempo, em segundos, um agente leva pra percorrer um caminho de tela a partir de `from`, andando
# como andaria de verdade: cada trecho na velocidade que o screen_velocity dá pra aquela direção (mais
# devagar quanto mais vertical). É a MESMA conta do movimento, chamada em vez de reescrita, pelo motivo de
# este arquivo existir: duas cópias da conta é a garantia de elas divergirem. Serve pra calcular quando um
# NPC chega a um ponto sem precisar simular a caminhada (ver NPCRoutineException.TravelTimes).
static func walk_seconds(from: Vector2, path: PackedVector2Array, speed: float, y_ratio: float,
		vertical_factor: float) -> float:
	var seconds: float = 0.0
	var cursor: Vector2 = from
	for point: Vector2 in path:
		var delta: Vector2 = point - cursor
		var velocity: Vector2 = screen_velocity(to_cartesian(delta, y_ratio), speed, y_ratio, vertical_factor)
		if delta != Vector2.ZERO and velocity.length() > 0.0:
			seconds += delta.length() / velocity.length()
		cursor = point
	return seconds
