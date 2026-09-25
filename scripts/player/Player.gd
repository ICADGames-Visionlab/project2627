class_name Player
extends CharacterBody2D

# Emitido só quando o estado de movimento (parado/andando, direção encarada) muda — não a cada
# frame. Emissor e ouvinte são o próprio Player (relação direta e permanente com o seu
# AnimatedSprite2D), por isso é um Signal direto e não um evento no EventBus; se no futuro outro
# sistema precisar reagir a isso (som de passo, poeira ao correr), dá pra escutar esse mesmo sinal
# sem mexer aqui.
signal movement_state_changed(is_moving: bool, facing_direction: Isometric.Facing)

# Emitido quando start_conversation_approach() chega ao destino (ou desiste por bloqueio). Quem
# chama dá await nele — ver NPCInteraction._start_conversation.
signal conversation_approach_arrived

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

# Quanto tempo ele precisa ficar travado antes de o caminho ser descartado. Existe porque roçar
# numa quina derruba a velocidade por um ou dois frames, e antes disso bastava um único frame
# lento pra jogar fora um trajeto inteiro que estava indo bem.
const BLOCKED_GRACE_SECONDS: float = 0.25

# Mesma ideia de BLOCKED_GRACE_SECONDS, mas pra aproximação de conversa (ver
# start_conversation_approach()): mais tolerante, porque desistir aqui abre o diálogo um pouco
# longe demais do NPC, em vez de só descartar um trajeto e parar.
const APPROACH_BLOCKED_GRACE_SECONDS: float = 1.0

var _is_moving: bool = false
var _facing_direction: Isometric.Facing = Isometric.Facing.S

# Verdadeiro enquanto uma conversa está aberta: nenhum esquema de movimento responde (SPEC §11.5).
var _is_input_locked: bool = false

# Caminho que o personagem está percorrendo no esquema de clique, e em qual ponto dele está. Vem
# pronto do Pathfinder (ou é um ponto só, quando não há Pathfinder na cena). Caminho vazio
# significa "sem destino", então não precisa de bandeira separada.
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0

# Há quanto tempo ele está travado indo até o ponto atual. Ver _cancel_click_target_if_blocked().
var _blocked_time: float = 0.0

# Trilha própria da aproximação de conversa — não é _path/_path_index de propósito: aqueles somem
# numa troca de esquema de movimento (ver _get_movement_direction()), e a aproximação precisa
# sobreviver a isso, já que ela nem é um dos dois esquemas.
var _approach_path: PackedVector2Array = PackedVector2Array()
var _approach_index: int = 0
var _is_approaching: bool = false
var _approach_blocked_time: float = 0.0

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	movement_state_changed.connect(_on_movement_state_changed)
	EventBus.conversation_approach_started.connect(_on_conversation_started)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.conversation_ended.connect(_on_conversation_ended)
	print("[Player] - Controlador inicializado na posição %s" % [global_position])


func _physics_process(delta: float) -> void:
	var input_direction: Vector2 = _get_movement_direction()
	velocity = _to_screen_velocity(input_direction)
	move_and_slide()
	_cancel_click_target_if_blocked(delta)
	_cancel_approach_if_blocked(delta)
	_update_movement_state(input_direction)


# Marca o destino do esquema de clique. Roda em _unhandled_input (e não em _input) de propósito:
# assim um clique consumido pela interface — um botão, um menu aberto por cima do jogo — não faz
# o personagem sair andando pra trás da UI.
func _unhandled_input(event: InputEvent) -> void:
	if _is_input_locked:
		return
	if GameManager.movement_scheme != GameManager.MovementScheme.CLICK:
		return

	if event.is_action_pressed(&"move_click"):
		_set_click_destination(get_global_mouse_position())


# Devolve a direção cartesiana do movimento deste frame, vinda da fonte que o jogador escolheu
# nas configurações. Os dois esquemas são exclusivos: no modo clique o teclado não anda, e
# vice-versa. Daqui pra frente o resto do script não sabe (nem precisa saber) de onde veio a
# direção — achatamento isométrico e escolha de animação são iguais nos dois casos.
#
# A aproximação de conversa vem ANTES de tudo isso, inclusive de _is_input_locked: é justamente
# por estar travado que o personagem só anda pela aproximação (script), nunca por input do
# jogador, enquanto ela dura.
func _get_movement_direction() -> Vector2:
	if _is_approaching:
		return _get_approach_direction()
	if _is_input_locked:
		return Vector2.ZERO
	if GameManager.movement_scheme == GameManager.MovementScheme.CLICK:
		return _get_click_direction()

	# Voltou pro teclado com um caminho pendente: descarta, senão ele seria retomado do nada se o
	# jogador trocasse de esquema outra vez.
	_clear_path()
	return _get_input_direction()


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Traça o caminho até o ponto clicado e começa a percorrê-lo.
#
# O Pathfinder é procurado por grupo, e não guardado numa referência exportada, pra que o Player
# funcione igual numa cena que não tenha nenhum: sem Pathfinder o caminho vira o ponto clicado
# sozinho, que é exatamente o comportamento em linha reta de antes.
func _set_click_destination(destination: Vector2) -> void:
	var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP) as Pathfinder

	if pathfinder == null:
		_path = PackedVector2Array([destination])
	else:
		# O proprio RID vai junto: a linha de visao do Pathfinder e raycast, e sem se excluir o
		# personagem bate no proprio colisor e nunca enxerga destino nenhum.
		_path = pathfinder.find_path(global_position, destination, [get_rid()])

	_path_index = 0
	if _path.is_empty():
		print("[Player] - Sem caminho até %s" % destination)


# Converte o ponto atual do caminho na mesma direção cartesiana que o teclado produziria pra ir
# até lá, avançando pro ponto seguinte conforme chega. Devolve ZERO quando o caminho acabou.
func _get_click_direction() -> Vector2:
	# Raio de chegada: o maior entre a folga fixa e o quanto o personagem anda num frame, pra ele
	# não passar do ponto e ficar voltando em looping quando speed for alto.
	var arrival_distance: float = maxf(CLICK_ARRIVAL_DISTANCE, speed * get_physics_process_delta_time())

	# Laço, e não if: com os pontos do caminho próximos entre si, um único frame pode vencer mais
	# de um de uma vez.
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) <= arrival_distance:
		_path_index += 1

	if _path_index >= _path.size():
		_clear_path()
		return Vector2.ZERO

	var to_waypoint: Vector2 = _path[_path_index] - global_position

	# to_waypoint é uma distância medida na tela, onde o chão já está achatado, e o resto do fluxo
	# espera uma direção cartesiana como a que vem do teclado (ver Isometric.to_cartesian).
	return Isometric.to_cartesian(to_waypoint, isometric_y_ratio)


# Desiste do caminho quando o personagem trava. Com o Pathfinder o traçado já desvia da geometria
# estática, então travar aqui quer dizer que apareceu algo que o grafo não conhece — outro corpo no
# caminho, ou cenário que mudou desde o último rebuild(). Sem isso o personagem empurraria o
# obstáculo pra sempre.
func _cancel_click_target_if_blocked(delta: float) -> void:
	if _path.is_empty():
		_blocked_time = 0.0
		return

	# Andando: zera o cronômetro. Só conta como travado o tempo CONTÍNUO parado — roçar numa quina
	# custa um ou dois frames lentos e não pode custar o trajeto inteiro.
	if get_real_velocity().length() >= speed * BLOCKED_SPEED_FRACTION:
		_blocked_time = 0.0
		return

	_blocked_time += delta
	if _blocked_time >= BLOCKED_GRACE_SECONDS:
		_clear_path()
		print("[Player] - Caminho descartado: passagem bloqueada")


func _clear_path() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_blocked_time = 0.0


# Anda até "target" ignorando o esquema de movimento ativo e _is_input_locked (ver
# _get_movement_direction()) — usado para abordar um NPC (NPCInteraction._start_conversation).
# Emite conversation_approach_arrived ao chegar. _is_input_locked já precisa estar true antes de
# chamar (quem inicia a abordagem trava o input via conversation_approach_started); este método só
# cuida do caminho.
func start_conversation_approach(target: Vector2) -> void:
	var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP) as Pathfinder

	if pathfinder == null:
		_approach_path = PackedVector2Array([target])
	else:
		_approach_path = pathfinder.find_path(global_position, target, [get_rid()])

	_approach_index = 0
	_approach_blocked_time = 0.0
	_is_approaching = not _approach_path.is_empty()

	if not _is_approaching:
		# Sem caminho (NPC cercado): adiado por call_deferred, senão o sinal dispararia antes de
		# quem chamou ter a chance de dar await nele (mesmo cuidado do DialogueRunner._emit_step).
		print("[Player] - Sem caminho até %s; abrindo diálogo daqui mesmo" % target)
		call_deferred("_deferred_approach_arrived")


# Só o corpo do adiamento acima — ver o comentário em start_conversation_approach().
func _deferred_approach_arrived() -> void:
	conversation_approach_arrived.emit()


# Mesma mecânica de _get_click_direction, mas sobre _approach_path (ver o comentário dela lá em
# cima pra saber por que ela é separada de _path).
func _get_approach_direction() -> Vector2:
	var arrival_distance: float = maxf(CLICK_ARRIVAL_DISTANCE, speed * get_physics_process_delta_time())

	while _approach_index < _approach_path.size() and global_position.distance_to(_approach_path[_approach_index]) <= arrival_distance:
		_approach_index += 1

	if _approach_index >= _approach_path.size():
		_is_approaching = false
		conversation_approach_arrived.emit()
		return Vector2.ZERO

	var to_waypoint: Vector2 = _approach_path[_approach_index] - global_position
	return Isometric.to_cartesian(to_waypoint, isometric_y_ratio)


# Desiste da aproximação se o personagem travar por tempo demais (NPC cercado, cenário mudou desde
# o último rebuild do Pathfinder). Sem isto um caminho impossível deixaria o input congelado para
# sempre — pior que abrir o diálogo um pouco mais longe do NPC do que o previsto.
func _cancel_approach_if_blocked(delta: float) -> void:
	if not _is_approaching:
		_approach_blocked_time = 0.0
		return

	if get_real_velocity().length() >= speed * BLOCKED_SPEED_FRACTION:
		_approach_blocked_time = 0.0
		return

	_approach_blocked_time += delta
	if _approach_blocked_time >= APPROACH_BLOCKED_GRACE_SECONDS:
		_is_approaching = false
		print("[Player] - Aproximação de conversa travada; abrindo diálogo daqui mesmo")
		conversation_approach_arrived.emit()


func _on_conversation_started(_conversation_id: StringName, _initiator_id: StringName) -> void:
	_is_input_locked = true
	_clear_path()


func _on_conversation_ended(_conversation_id: StringName, _end_node_id: StringName) -> void:
	_is_input_locked = false


# Converte a direção cartesiana do input na velocidade final, em pixels de tela por segundo. A
# conta em si mora em Isometric porque é a mesma para todo agente que anda neste chão (o NPC usa
# a mesma); o que é do Player são os três números que entram nela.
func _to_screen_velocity(direction: Vector2) -> Vector2:
	return Isometric.screen_velocity(direction, speed, isometric_y_ratio, vertical_speed_factor)


# Calcula o estado de movimento (parado/andando + direção encarada) a partir do input deste
# frame. Sem input, mantém a última direção encarada. Só emite movement_state_changed quando
# esse estado é diferente do frame anterior — a troca de animação não precisa (e não deve) rodar
# a cada frame, só quando muda.
func _update_movement_state(input_direction: Vector2) -> void:
	var is_moving: bool = input_direction != Vector2.ZERO
	var facing_direction: Isometric.Facing = _facing_direction

	if is_moving:
		facing_direction = Isometric.facing_from_direction(input_direction)

	if is_moving == _is_moving and facing_direction == _facing_direction:
		return

	_is_moving = is_moving
	_facing_direction = facing_direction
	movement_state_changed.emit(_is_moving, _facing_direction)


# Reage à mudança de estado de movimento tocando a animação correspondente. Só roda quando
# movement_state_changed é emitido (ou seja, quando o estado muda de verdade), não a cada frame.
func _on_movement_state_changed(is_moving: bool, facing_direction: Isometric.Facing) -> void:
	var prefix: StringName = &"run" if is_moving else &"idle"
	_animated_sprite.play(Isometric.animation_name(prefix, facing_direction))
