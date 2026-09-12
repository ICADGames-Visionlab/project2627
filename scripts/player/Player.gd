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

# Achatamento do eixo Y que alinha a DIREÇÃO do movimento aos eixos do losango isométrico. Não
# mexe na velocidade (quem cuida disso é vertical_speed_factor, logo abaixo): o que ele decide é
# o ângulo das diagonais.
#
# 0.5 é a razão do losango do tile (64 / 128, ver o TileSet em main.tscn) e faz W+D andar em cima
# da diagonal do grid — a direção em que as ruas correm. A 1.0 as diagonais saem a 45° na tela,
# ignorando o grid (movimento puro top-down). Campo de balanceamento: ajuste no Inspector.
@export_range(0.5, 1.0, 0.01) var isometric_y_ratio: float = 0.5

# Velocidade na tela do movimento puramente vertical, como fração da velocidade do movimento
# puramente horizontal.
#
# Este é o botão de sensação, e não tem valor "certo": as duas pontas estão erradas de jeitos
# opostos, porque chão achatado 2:1 e personagem desenhado sem achatamento são incompatíveis.
#
#   0.5  geometricamente correto — subir e descer percorre a mesma distância em TILES que andar
#        pros lados. Parece lento: o sprite do personagem não é achatado e o olho usa ele de régua.
#   1.0  uniforme em PIXELS DE TELA. Parece rápido, por dois motivos que se somam: o chão passa ao
#        dobro de tiles por segundo, e a tela 16:9 é atravessada na vertical em 2.4s contra 4.27s
#        na horizontal.
#
# O padrão fica no meio dos dois. Ajuste no Inspector com o jogo rodando até parar de incomodar.
@export_range(0.5, 1.0, 0.01) var vertical_speed_factor: float = 0.75

# Distância da tela até o ponto clicado abaixo da qual o destino é considerado alcançado. Não é
# variável de balanceamento: é a folga técnica que impede o personagem de ficar oscilando em
# volta do alvo por nunca cair exatamente em cima dele.
const CLICK_ARRIVAL_DISTANCE: float = 8.0

# Fração de speed abaixo da qual o personagem indo até um ponto clicado é considerado travado.
# Ver _cancel_click_target_if_blocked().
const BLOCKED_SPEED_FRACTION: float = 0.1

var _is_moving: bool = false
var _facing_direction: FacingDirection = FacingDirection.S

# Ponto do mundo pra onde o personagem está indo no esquema de clique, e se existe um destino
# ativo. O par (bool + Vector2) evita ter que reservar alguma coordenada como "sem destino".
var _click_target: Vector2 = Vector2.ZERO
var _has_click_target: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	movement_state_changed.connect(_on_movement_state_changed)
	print("[Player] - Controlador inicializado na posição %s" % [global_position])


func _physics_process(_delta: float) -> void:
	var input_direction: Vector2 = _get_movement_direction()
	velocity = _to_screen_velocity(input_direction)
	move_and_slide()
	_cancel_click_target_if_blocked()
	_update_movement_state(input_direction)


# Marca o destino do esquema de clique. Roda em _unhandled_input (e não em _input) de propósito:
# assim um clique consumido pela interface — um botão, um menu aberto por cima do jogo — não faz
# o personagem sair andando pra trás da UI.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.movement_scheme != GameManager.MovementScheme.CLICK:
		return

	if event.is_action_pressed(&"move_click"):
		_click_target = get_global_mouse_position()
		_has_click_target = true


# Devolve a direção cartesiana do movimento deste frame, vinda da fonte que o jogador escolheu
# nas configurações. Os dois esquemas são exclusivos: no modo clique o teclado não anda, e
# vice-versa. Daqui pra frente o resto do script não sabe (nem precisa saber) de onde veio a
# direção — achatamento isométrico e escolha de animação são iguais nos dois casos.
func _get_movement_direction() -> Vector2:
	if GameManager.movement_scheme == GameManager.MovementScheme.CLICK:
		return _get_click_direction()

	# Voltou pro teclado com um destino pendente: descarta, senão ele seria retomado do nada se o
	# jogador trocasse de esquema outra vez.
	_has_click_target = false
	return _get_input_direction()


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Converte o destino clicado na mesma direção cartesiana que o teclado produziria pra ir até lá.
# Devolve ZERO quando não há destino ativo ou quando ele já foi alcançado.
func _get_click_direction() -> Vector2:
	if not _has_click_target:
		return Vector2.ZERO

	var to_target: Vector2 = _click_target - global_position

	# Raio de chegada: o maior entre a folga fixa e o quanto o personagem anda num frame, pra ele
	# não passar do alvo e voltar em looping quando speed for alto.
	var arrival_distance: float = maxf(CLICK_ARRIVAL_DISTANCE, speed * get_physics_process_delta_time())
	if to_target.length() <= arrival_distance:
		_has_click_target = false
		return Vector2.ZERO

	# to_target é uma distância medida na tela, onde o chão já está achatado; _to_screen_velocity()
	# logo em seguida espera receber uma direção cartesiana, como a que vem do teclado. Desfazer o
	# achatamento aqui faz as duas contas se cancelarem no eixo Y, e o personagem anda em linha
	# reta até o ponto clicado (vertical_speed_factor muda só a rapidez do trajeto, não o rumo).
	return Vector2(to_target.x, to_target.y / isometric_y_ratio).normalized()


# Desiste do destino clicado quando o personagem trava no caminho. O movimento por clique é em
# linha reta, sem pathfinding: sem isso, um prédio entre o jogador e o ponto clicado deixaria o
# personagem empurrando a parede pra sempre.
func _cancel_click_target_if_blocked() -> void:
	if not _has_click_target:
		return

	if get_real_velocity().length() < speed * BLOCKED_SPEED_FRACTION:
		_has_click_target = false
		print("[Player] - Destino do clique descartado: caminho bloqueado")


# Converte a direção cartesiana do input na velocidade final, em pixels de tela por segundo.
#
# Três etapas com responsabilidades separadas, e vale manter assim porque cada uma resolve um
# problema diferente:
#
#   1. O achatamento em Y decide a DIREÇÃO — é ele que faz W+D andar em cima da diagonal do grid
#      isométrico (onde correm as ruas) em vez de a 45° na tela.
#   2. A normalização tira o corte de velocidade que o achatamento causaria de tabela, deixando o
#      módulo sob controle de um parâmetro só, em vez de ser efeito colateral da geometria.
#   3. vertical_speed_factor decide o MÓDULO, interpolando conforme o quanto a direção é vertical
#      na tela: horizontal puro anda a speed, vertical puro a speed * vertical_speed_factor, e as
#      diagonais no meio.
func _to_screen_velocity(direction: Vector2) -> Vector2:
	var screen_direction: Vector2 = Vector2(direction.x, direction.y * isometric_y_ratio).normalized()
	var verticality: float = absf(screen_direction.y)
	return screen_direction * speed * lerpf(1.0, vertical_speed_factor, verticality)


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
