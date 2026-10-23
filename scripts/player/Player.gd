class_name Player
extends CharacterBody2D

# Emitido só quando o estado de movimento (parado/andando/correndo, direção encarada) muda — não a
# cada frame. Emissor e ouvinte são o próprio Player (relação direta e permanente com o seu
# AnimatedSprite2D), por isso é um Signal direto e não um evento no EventBus; se no futuro outro
# sistema precisar reagir a isso (som de passo, poeira ao correr), dá pra escutar esse mesmo sinal
# sem mexer aqui. is_running só é verdadeiro junto com is_moving: parado nunca está "correndo".
signal movement_state_changed(is_moving: bool, is_running: bool, facing_direction: TopDown.Facing)

# Emitido quando start_conversation_approach() chega ao destino (ou desiste por bloqueio). Quem
# chama dá await nele — ver NPCInteraction._start_conversation.
signal conversation_approach_arrived

# Distância da tela até o ponto clicado abaixo da qual o destino é considerado alcançado. Não é
# variável de balanceamento: é a folga técnica que impede o personagem de ficar oscilando em
# volta do alvo por nunca cair exatamente em cima dele.
const CLICK_ARRIVAL_DISTANCE: float = 8.0

# Fração da velocidade atual abaixo da qual o personagem indo até um ponto clicado é considerado
# travado. Ver _cancel_click_target_if_blocked().
const BLOCKED_SPEED_FRACTION: float = 0.1

# Quanto tempo ele precisa ficar travado antes de o caminho ser descartado. Existe porque roçar
# numa quina derruba a velocidade por um ou dois frames, e antes disso bastava um único frame
# lento pra jogar fora um trajeto inteiro que estava indo bem.
const BLOCKED_GRACE_SECONDS: float = 0.25

# Mesma ideia de BLOCKED_GRACE_SECONDS, mas pra aproximação de conversa (ver
# start_conversation_approach()): mais tolerante, porque desistir aqui abre o diálogo um pouco
# longe demais do NPC, em vez de só descartar um trajeto e parar.
const APPROACH_BLOCKED_GRACE_SECONDS: float = 1.0

# Quanto o mouse precisa se mover no mundo, enquanto o botão está segurado, para o caminho ser
# retraçado antes de o anterior acabar. Folga técnica, não balanceamento: só evita pedir ao
# Pathfinder o mesmo caminho de novo quando a mão do jogador está parada.
const FOLLOW_RETARGET_DISTANCE: float = 4.0

# Seção em que os controles do Player aparecem no menu de debug (F4).
const DEBUG_SECTION: StringName = &"Jogador"

# Autoteste da movimentação, rodado pela ação "Autoteste do clique" do menu de debug.
const SELF_TEST_PATH: String = "res://scripts/player/PlayerMovementSelfTest.gd"

# Velocidade andando, em pixels de tela por segundo, no movimento puramente horizontal (o vertical
# é reduzido por vertical_speed_factor). É a velocidade padrão dos dois esquemas: o teclado anda
# enquanto o SHIFT não está segurado, e o clique simples anda.
@export var walk_speed: float = 225.0

# Velocidade correndo, na mesma unidade de walk_speed. No teclado vale enquanto o SHIFT (ação
# move_run) está segurado; no esquema de clique, depois de um clique duplo (ver ClickMoveGesture).
@export var run_speed: float = 450.0

# Velocidade na tela do movimento puramente vertical, como fração da velocidade do movimento
# puramente horizontal. Não muda a direção (W+D sempre sai a 45° na tela), só a rapidez.
#
# Este é o botão de sensação da câmera a 45°:
#
#   0.71 geometricamente correto (cos 45°) — com a câmera inclinada, o fundo do chão aparece
#        encurtado na tela, e andar a mesma distância no chão cobre menos pixels na vertical.
#   1.0  uniforme em PIXELS DE TELA, como a maioria dos jogos top-down 3/4. Parece um pouco rápido
#        na vertical: a tela 16:9 é atravessada na vertical em 2.4s contra 4.27s na horizontal.
#
# Ajuste no Inspector com o jogo rodando até parar de incomodar.
@export_range(0.5, 1.0, 0.01) var vertical_speed_factor: float = 0.71

@export_group("Esquema de clique")

# Quanto tempo o botão do mouse precisa ficar apertado para deixar de ser um clique e passar a
# "segurar" — o personagem para de ir até o ponto clicado e passa a acompanhar o mouse. Baixo demais
# e cliques normais (que duram ~0.1s) viram "segurar"; alto demais e o acompanhamento demora a pegar.
@export_range(0.1, 1.0, 0.01) var click_hold_seconds: float = 0.25

# Intervalo máximo entre dois cliques para contarem como clique duplo (correr). Não atrasa o clique
# simples — o personagem sai andando no primeiro clique e só troca para corrida no segundo — então o
# único custo de aumentar é dois cliques separados no mesmo lugar virarem corrida sem querer.
@export_range(0.1, 1.0, 0.01) var double_click_seconds: float = 0.4

# Distância máxima, em pixels de tela na resolução base do projeto (1920x1080, a mesma em qualquer
# tamanho de janela, por causa do stretch), entre os dois cliques de um clique duplo. Clicar em dois
# pontos diferentes rapidamente é trocar de destino, não pedir corrida.
@export_range(0.0, 200.0, 1.0) var double_click_distance: float = 24.0

# De quanto em quanto tempo o caminho é retraçado até o mouse enquanto o botão está segurado. Mais
# baixo acompanha curvas rápidas do mouse com mais fidelidade e pede mais buscas ao Pathfinder.
@export_range(0.02, 0.5, 0.01) var follow_repath_seconds: float = 0.1

# Grupo pelo qual o resto do jogo acha o Player (a GameSession, para o save; o NPCInteraction, para a
# abordagem). A cena já marca o grupo; o _enter_tree() garante para quem instanciar o script sem ela.
const GROUP: StringName = &"player"

# Camada 1 ("world" em project.godot): só a geometria do mapa. É a máscara que valida a posição
# restaurada de um save — um NPC parado ali (camada 2, "Agentes") não pode invalidar a posição.
const WORLD_COLLISION_MASK: int = 1

var _is_moving: bool = false
var _facing_direction: TopDown.Facing = TopDown.Facing.S

# Se o movimento atual é corrida. Quem decide depende da fonte: no teclado é o SHIFT, lido a cada
# frame; no clique é o gesto que pediu o trajeto (ver _apply_click_command); na aproximação de
# conversa é herdado de como o jogador vinha se movendo. Só tem efeito enquanto há movimento.
var _is_running: bool = false

# Corrida EFETIVA (em movimento E correndo) do último movement_state_changed emitido. Separada de
# _is_running porque parado com o SHIFT segurado não está correndo: é esta que decide a animação e
# o log de "começou/parou de correr".
var _is_running_emitted: bool = false

# Verdadeiro enquanto uma conversa está aberta: nenhum esquema de movimento responde (SPEC §11.5).
var _is_input_locked: bool = false

# Caminho que o personagem está percorrendo no esquema de clique, e em qual ponto dele está. Vem
# pronto do Pathfinder (ou é um ponto só, quando não há Pathfinder na cena). Caminho vazio
# significa "sem destino", então não precisa de bandeira separada.
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0

# Há quanto tempo ele está travado indo até o ponto atual. Ver _cancel_click_target_if_blocked().
var _blocked_time: float = 0.0

# Intérprete do botão do mouse no esquema de clique: clique, clique duplo e segurar. O relógio que
# ele recebe é _click_clock, e não o relógio do sistema, pelos motivos explicados lá.
var _click_gesture: ClickMoveGesture = ClickMoveGesture.new()

# Relógio do gesto de clique, em segundos: soma dos delta de física. Usar o tempo do próprio jogo
# (e não Time.get_ticks_msec) faz "segurar" e "clique duplo" congelarem junto com o jogo quando ele
# pausa, e deixa o autoteste avançar o tempo de forma determinística, frame a frame.
var _click_clock: float = 0.0

# Acompanhamento do mouse (botão segurado): tempo desde o último caminho traçado e o ponto do mundo
# para onde ele foi traçado. Ver _follow_pointer().
var _follow_repath_elapsed: float = 0.0
var _follow_target: Vector2 = Vector2.ZERO

# Se o último ponto do caminho atual é o próprio mouse — e pode, portanto, acompanhá-lo a cada frame
# entre um retraçado e outro. Falso quando o Pathfinder trocou o destino (mouse em cima de um prédio).
var _is_follow_path_end_live: bool = false

# Trilha própria da aproximação de conversa — não é _path/_path_index de propósito: aqueles somem
# numa troca de esquema de movimento (ver _get_movement_direction()), e a aproximação precisa
# sobreviver a isso, já que ela nem é um dos dois esquemas.
var _approach_path: PackedVector2Array = PackedVector2Array()
var _approach_index: int = 0
var _is_approaching: bool = false
var _approach_blocked_time: float = 0.0

# Onde a cena pôs o Player. É o ponto de partida de um novo jogo e o destino de uma posição salva
# que não vale mais (o mapa mudou e ela caiu dentro de uma parede). Guardado só uma vez, no primeiro
# _enter_tree(), antes de qualquer restore_position().
var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false

# Última posição em momento seguro (ver _is_in_safe_state()). É ela, e não a de agora, que vai para
# o save: gravar no meio de uma abordagem de conversa ou de uma troca de cena guarda onde o jogador
# estava no controle pela última vez.
var _last_safe_position: Vector2 = Vector2.ZERO

# Há uma posição restaurada esperando validação contra o mapa. A consulta ao espaço de física fica
# para o primeiro _physics_process, quando a cena inteira (inclusive as colisões do mapa) já montou.
var _needs_position_check: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


# Entra no grupo e guarda o ponto de partida. Em _enter_tree, e não em _ready, de propósito: a engine
# roda todo _enter_tree da cena antes de qualquer _ready, então a GameSession (que restaura a posição
# no _ready dela) nunca chega antes e o ponto de partida nunca vira a posição restaurada.
func _enter_tree() -> void:
	add_to_group(GROUP)
	if _has_spawn_position:
		return
	_has_spawn_position = true
	_spawn_position = global_position
	_last_safe_position = global_position


func _ready() -> void:
	_configure_click_gesture()
	movement_state_changed.connect(_on_movement_state_changed)
	EventBus.conversation_approach_started.connect(_on_conversation_started)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.conversation_ended.connect(_on_conversation_ended)

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Velocidades ajustáveis com o jogo rodando e o autoteste do gesto de clique (F4).
		DebugMenu.register_value(DEBUG_SECTION, "Velocidade andando", _set_walk_speed,
			DebugParam.float_value("", walk_speed, 0.0, 2000.0, 10.0), _get_walk_speed)
		DebugMenu.register_value(DEBUG_SECTION, "Velocidade correndo", _set_run_speed,
			DebugParam.float_value("", run_speed, 0.0, 2000.0, 10.0), _get_run_speed)
		DebugMenu.register_action(DEBUG_SECTION, "Autoteste do clique", _run_click_gesture_self_test)

	print("[Player] - Controlador inicializado na posição %s (andando %.0f, correndo %.0f)"
		% [global_position, walk_speed, run_speed])


func _physics_process(delta: float) -> void:
	if _needs_position_check:
		_validate_restored_position()
	_click_clock += delta
	_update_click_gesture(delta)

	var input_direction: Vector2 = _get_movement_direction()
	velocity = _to_screen_velocity(input_direction)
	move_and_slide()
	_cancel_click_target_if_blocked(delta)
	_cancel_approach_if_blocked(delta)
	_update_movement_state(input_direction)
	if _is_in_safe_state():
		_last_safe_position = global_position


# Repassa o botão do esquema de clique para o ClickMoveGesture. Roda em _unhandled_input (e não em
# _input) de propósito: assim um clique consumido pela interface — um botão, um menu aberto por cima
# do jogo, um orbe de insight — não faz o personagem sair andando pra trás da UI.
#
# O soltar só é repassado se o apertar correspondente passou por aqui: um apertar engolido pela UI
# não pode deixar um soltar órfão encerrar um "segurar" que nem começou.
func _unhandled_input(event: InputEvent) -> void:
	if _is_input_locked:
		return
	if not GameManager.is_click_movement_enabled():
		return

	if event.is_action_pressed(&"move_click"):
		_apply_click_command(_click_gesture.press(_click_clock, _get_event_screen_position(event)))
	elif event.is_action_released(&"move_click") and _click_gesture.is_pressed():
		_apply_click_command(_click_gesture.release(_click_clock))


# Avança o gesto de clique no tempo (é aqui que um clique vira "segurar") e, enquanto o botão está
# segurado, mantém o caminho apontado para o mouse. Fora do esquema de clique ou com o input travado
# não faz nada: o gesto é zerado por quem trava (_on_conversation_started) ou troca de esquema
# (_get_movement_direction).
func _update_click_gesture(delta: float) -> void:
	if _is_input_locked or not GameManager.is_click_movement_enabled():
		return

	_apply_click_command(_click_gesture.update(_click_clock, _is_click_button_down()))
	if _click_gesture.is_following:
		_follow_pointer(delta)


# Executa o que o gesto de clique pediu. Todo destino é o ponto do mundo sob o mouse NESTE momento.
func _apply_click_command(command: ClickMoveGesture.Command) -> void:
	match command:
		ClickMoveGesture.Command.GO_TO:
			_is_running = _click_gesture.is_running
			var destination: Vector2 = _get_pointer_world_position()
			_set_click_destination(destination)
			print("[Player] - Clique %s: %s até %s"
				% ["duplo" if _is_running else "simples", _gait_label(), destination])
		ClickMoveGesture.Command.START_FOLLOW:
			_is_running = _click_gesture.is_running
			# Força o primeiro caminho no próximo _follow_pointer, sem esperar o intervalo e sem
			# aproveitar nada de um "segurar" anterior (alvo e ponta viva do caminho antigos).
			_follow_repath_elapsed = follow_repath_seconds
			_follow_target = Vector2.INF
			_is_follow_path_end_live = false
			print("[Player] - Clique segurado: acompanhando o mouse %s" % _gait_label())
		ClickMoveGesture.Command.STOP_FOLLOW:
			# Soltar termina o trajeto no ponto em que o mouse está, em vez de parar seco: é o mesmo
			# que um último clique ali, e evita o tranco de frear no meio da passada.
			var release_point: Vector2 = _get_pointer_world_position()
			_set_click_destination(release_point, false)
			print("[Player] - Clique solto: parou de acompanhar o mouse, %s até %s"
				% [_gait_label(), release_point])
		ClickMoveGesture.Command.CANCEL_FOLLOW:
			# O botão subiu sem o evento chegar aqui (pausa, janela sem foco, menu por cima): para onde
			# está. O mouse agora pode estar num botão da interface, e ir até ele seria andar até o
			# "Continuar" do menu de pausa.
			_clear_path()
			_is_running = false
			print("[Player] - Botão solto sem o evento chegar (pausa/foco/menu): parou de acompanhar o mouse")


# Mantém o caminho apontado para o mouse enquanto o botão está segurado, em duas velocidades:
#
#   - A cada frame, o último ponto do caminho é trocado pelo mouse de agora. Sem isso o destino seria
#     o mouse de até follow_repath_seconds atrás, e com o mouse perto do personagem (a câmera o segue,
#     então o mouse parado na tela anda junto com ele) ele alcançava esse ponto velho antes do
#     retraçado seguinte e parava um frame — a animação piscava andando/parado sem parar.
#   - Em intervalos de follow_repath_seconds, o caminho inteiro é retraçado pelo Pathfinder, que é
#     quem desvia dos prédios. Não retraça a cada frame porque cada traçado é uma busca no grafo.
#
# Com o mouse em cima do personagem não há para onde ir: para, e não pede caminho nenhum.
func _follow_pointer(delta: float) -> void:
	var target: Vector2 = _get_pointer_world_position()
	_follow_repath_elapsed += delta

	if global_position.distance_to(target) <= CLICK_ARRIVAL_DISTANCE:
		_clear_path()
		# O mouse saindo de cima do personagem é traçado na hora, sem esperar o intervalo.
		_follow_repath_elapsed = follow_repath_seconds
		return

	if _follow_repath_elapsed >= follow_repath_seconds \
			and (_path.is_empty() or target.distance_to(_follow_target) >= FOLLOW_RETARGET_DISTANCE):
		_follow_repath_elapsed = 0.0
		_follow_target = target
		_set_click_destination(target, false)
		# O Pathfinder troca um destino dentro de um prédio pelo ponto acessível mais próximo; aí o
		# último ponto já não é o mouse e não pode ser sobrescrito por ele até o próximo retraçado.
		_is_follow_path_end_live = not _path.is_empty() and _path[_path.size() - 1].is_equal_approx(target)
		return

	if _is_follow_path_end_live and not _path.is_empty():
		_path[_path.size() - 1] = target


# Devolve a direção do movimento deste frame, vinda da fonte que o jogador escolheu nas
# configurações: só teclado, só clique, ou os dois (GameManager.MovementScheme.BOTH). Daqui pra
# frente o resto do script não sabe (nem precisa saber) de onde veio a direção — velocidade e
# escolha de animação são iguais nos dois casos.
#
# Com os dois ligados, o teclado manda enquanto alguma direção estiver apertada: apertar WASD no
# meio de um trajeto de clique descarta o trajeto, como tomar o controle de volta. O botão do mouse
# segurado continua valendo, então soltar o teclado com ele ainda apertado volta a seguir o mouse.
#
# A aproximação de conversa vem ANTES de tudo isso, inclusive de _is_input_locked: é justamente
# por estar travado que o personagem só anda pela aproximação (script), nunca por input do
# jogador, enquanto ela dura.
func _get_movement_direction() -> Vector2:
	if _is_approaching:
		return _get_approach_direction()
	if _is_input_locked:
		return Vector2.ZERO

	if GameManager.is_keyboard_movement_enabled():
		var keyboard_direction: Vector2 = _get_input_direction()
		if keyboard_direction != Vector2.ZERO or not GameManager.is_click_movement_enabled():
			# Teclado: anda por padrão e corre enquanto o SHIFT estiver segurado. Lido a cada frame,
			# então soltar o SHIFT no meio do caminho volta a andar na hora.
			_is_running = Input.is_action_pressed(&"move_run")
			# Um trajeto de clique pendente é descartado: no esquema só de teclado, senão ele seria
			# retomado do nada se o jogador trocasse de esquema outra vez; nos dois, porque o
			# jogador acabou de tomar o controle pelo teclado.
			_clear_path()
			if not GameManager.is_click_movement_enabled():
				_click_gesture.reset()
			return keyboard_direction

	return _get_click_direction()


# Lê o input de movimento (AWSD, setinhas e analógico esquerdo do joystick, configurados juntos
# em cada ação no Input Map) já normalizado, permitindo as 8 direções sem que o diagonal ande
# mais rápido que os eixos retos.
func _get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# Traça o caminho até "destination" e começa a percorrê-lo. log_failures desliga o aviso de "sem
# caminho" para quem traça várias vezes por segundo (acompanhar o mouse), onde ele viraria spam.
#
# O Pathfinder é procurado por grupo, e não guardado numa referência exportada, pra que o Player
# funcione igual numa cena que não tenha nenhum: sem Pathfinder o caminho vira o ponto clicado
# sozinho, que é exatamente o comportamento em linha reta de antes.
func _set_click_destination(destination: Vector2, log_failures: bool = true) -> void:
	var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP) as Pathfinder

	if pathfinder == null:
		_path = PackedVector2Array([destination])
	else:
		# O proprio RID vai junto: a linha de visao do Pathfinder e raycast, e sem se excluir o
		# personagem bate no proprio colisor e nunca enxerga destino nenhum.
		_path = pathfinder.find_path(global_position, destination, [get_rid()])

	_path_index = 0
	_blocked_time = 0.0
	if _path.is_empty() and log_failures:
		print("[Player] - Sem caminho até %s" % destination)


# Converte o ponto atual do caminho na mesma direção unitária que o teclado produziria pra ir
# até lá, avançando pro ponto seguinte conforme chega. Devolve ZERO quando o caminho acabou.
func _get_click_direction() -> Vector2:
	# Raio de chegada: o maior entre a folga fixa e o quanto o personagem anda num frame, pra ele
	# não passar do ponto e ficar voltando em looping quando a velocidade for alta.
	var arrival_distance: float = maxf(CLICK_ARRIVAL_DISTANCE, _current_speed() * get_physics_process_delta_time())

	# Laço, e não if: com os pontos do caminho próximos entre si, um único frame pode vencer mais
	# de um de uma vez.
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) <= arrival_distance:
		_path_index += 1

	if _path_index >= _path.size():
		_clear_path()
		# Chegou. Seguindo o mouse, a corrida continua valendo pro próximo trecho (o mouse ainda está
		# segurado); fora isso o trajeto acabou, e o próximo clique decide de novo.
		if not _click_gesture.is_following:
			_is_running = false
		return Vector2.ZERO

	return (_path[_path_index] - global_position).normalized()


# Desiste do caminho quando o personagem trava. Com o Pathfinder o traçado já desvia da geometria
# estática, então travar aqui quer dizer que apareceu algo que o grafo não conhece — outro corpo no
# caminho, ou cenário que mudou desde o último rebuild(). Sem isso o personagem empurraria o
# obstáculo pra sempre.
#
# Acompanhando o mouse, desistir só descarta o trecho: _follow_pointer traça de novo no intervalo
# seguinte, e o personagem volta a tentar enquanto o botão estiver segurado. Por isso não loga nesse
# caso — seria uma linha a cada tentativa enquanto ele empurra a parede.
func _cancel_click_target_if_blocked(delta: float) -> void:
	if _path.is_empty():
		_blocked_time = 0.0
		return

	# Andando: zera o cronômetro. Só conta como travado o tempo CONTÍNUO parado — roçar numa quina
	# custa um ou dois frames lentos e não pode custar o trajeto inteiro.
	if get_real_velocity().length() >= _current_speed() * BLOCKED_SPEED_FRACTION:
		_blocked_time = 0.0
		return

	_blocked_time += delta
	if _blocked_time >= BLOCKED_GRACE_SECONDS:
		_clear_path()
		if not _click_gesture.is_following:
			_is_running = false
			print("[Player] - Caminho descartado: passagem bloqueada")


# Descarta o caminho do esquema de clique (e o cronômetro de travamento que pertence a ele).
func _clear_path() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_blocked_time = 0.0


# Descarta o destino pendente do esquema de clique. Público para quem move o jogador por script sem
# travar o input (a aproximação de um Interactable): sem isto, um clique antigo ainda em andamento
# seria retomado assim que a aproximação terminasse, e o jogador sairia andando para longe.
func cancel_click_destination() -> void:
	_clear_path()


# Anda até "target" ignorando o esquema de movimento ativo e _is_input_locked (ver
# _get_movement_direction()) — usado para abordar um NPC (NPCInteraction._start_conversation).
# Emite conversation_approach_arrived ao chegar. _is_input_locked já precisa estar true antes de
# chamar (quem inicia a abordagem trava o input via conversation_approach_started); este método só
# cuida do caminho.
#
# A velocidade é herdada de como o jogador vinha se movendo (_is_running não é mexido aqui): quem
# corria até o NPC chega correndo, quem andava chega andando.
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
	_is_running = false
	conversation_approach_arrived.emit()


# Mesma mecânica de _get_click_direction, mas sobre _approach_path (ver o comentário dela lá em
# cima pra saber por que ela é separada de _path).
func _get_approach_direction() -> Vector2:
	var arrival_distance: float = maxf(CLICK_ARRIVAL_DISTANCE, _current_speed() * get_physics_process_delta_time())

	while _approach_index < _approach_path.size() and global_position.distance_to(_approach_path[_approach_index]) <= arrival_distance:
		_approach_index += 1

	if _approach_index >= _approach_path.size():
		_is_approaching = false
		_is_running = false
		conversation_approach_arrived.emit()
		return Vector2.ZERO

	return (_approach_path[_approach_index] - global_position).normalized()


# Desiste da aproximação se o personagem travar por tempo demais (NPC cercado, cenário mudou desde
# o último rebuild do Pathfinder). Sem isto um caminho impossível deixaria o input congelado para
# sempre — pior que abrir o diálogo um pouco mais longe do NPC do que o previsto.
func _cancel_approach_if_blocked(delta: float) -> void:
	if not _is_approaching:
		_approach_blocked_time = 0.0
		return

	if get_real_velocity().length() >= _current_speed() * BLOCKED_SPEED_FRACTION:
		_approach_blocked_time = 0.0
		return

	_approach_blocked_time += delta
	if _approach_blocked_time >= APPROACH_BLOCKED_GRACE_SECONDS:
		_is_approaching = false
		_is_running = false
		print("[Player] - Aproximação de conversa travada; abrindo diálogo daqui mesmo")
		conversation_approach_arrived.emit()


# Trava o movimento do jogador quando uma conversa (ou a aproximação dela) começa. O gesto de clique
# é zerado junto: um botão que estava segurado não pode voltar a puxar o personagem quando a conversa
# acabar, nem um clique de antes da conversa formar clique duplo com um de depois.
func _on_conversation_started(_conversation_id: StringName, _initiator_id: StringName) -> void:
	_is_input_locked = true
	_clear_path()
	_click_gesture.reset()


# Devolve o controle ao jogador no fim da conversa, sempre andando: nada do que ele fazia antes da
# conversa continua valendo.
func _on_conversation_ended(_conversation_id: StringName, _end_node_id: StringName) -> void:
	_is_input_locked = false
	_is_running = false


# Converte a direção do input na velocidade final, em pixels de tela por segundo. A conta em si
# mora em TopDown porque é a mesma para todo agente que anda neste chão (o NPC usa a mesma); o que
# é do Player são os números que entram nela.
func _to_screen_velocity(direction: Vector2) -> Vector2:
	return TopDown.screen_velocity(direction, _current_speed(), vertical_speed_factor)


# Velocidade do movimento atual: corrida ou caminhada. Ponto único pra todo lugar que precisa dela
# (velocidade de tela, raio de chegada, detecção de travamento), pra nenhum deles usar a errada.
func _current_speed() -> float:
	return run_speed if _is_running else walk_speed


# Rótulo do passo atual para os prints de debug.
func _gait_label() -> String:
	return "correndo" if _is_running else "andando"


# Ponto do mundo sob o mouse. Isolado num método (em vez de get_global_mouse_position() espalhado)
# porque é a única leitura do esquema de clique que depende do ponteiro físico: o autoteste da
# movimentação sobrescreve este método para apontar o "mouse" onde quiser, inclusive rodando em
# --headless, onde não existe ponteiro nenhum.
func _get_pointer_world_position() -> Vector2:
	return get_global_mouse_position()


# Estado real do botão do esquema de clique, repassado ao gesto a cada frame (ver
# ClickMoveGesture.update, rede de segurança contra o evento de soltar se perder).
func _is_click_button_down() -> bool:
	return Input.is_action_pressed(&"move_click")


# Posição do evento na tela (viewport), usada só para medir a distância entre os dois cliques de um
# clique duplo. Um evento de ação sem posição (ação disparada por código) cai na posição do mouse.
func _get_event_screen_position(event: InputEvent) -> Vector2:
	var mouse_event: InputEventMouse = event as InputEventMouse
	if mouse_event != null:
		return mouse_event.position
	return get_viewport().get_mouse_position()


# Copia para o ClickMoveGesture os tempos e distâncias expostos no Inspector. O gesto não é um Node
# e não aparece no Inspector, então o dono dos valores é o Player.
func _configure_click_gesture() -> void:
	_click_gesture.hold_seconds = click_hold_seconds
	_click_gesture.double_click_seconds = double_click_seconds
	_click_gesture.double_click_distance = double_click_distance


# Calcula o estado de movimento (parado/andando/correndo + direção encarada) a partir do input
# deste frame. Sem input, mantém a última direção encarada. Só emite movement_state_changed quando
# esse estado é diferente do frame anterior — a troca de animação não precisa (e não deve) rodar
# a cada frame, só quando muda.
func _update_movement_state(input_direction: Vector2) -> void:
	var is_moving: bool = input_direction != Vector2.ZERO
	var is_running: bool = is_moving and _is_running
	var facing_direction: TopDown.Facing = _facing_direction

	if is_moving:
		facing_direction = TopDown.facing_from_direction(input_direction)

	if is_moving == _is_moving and is_running == _is_running_emitted and facing_direction == _facing_direction:
		return

	if is_running != _is_running_emitted:
		print("[Player] - %s" % ("Começou a correr" if is_running else "Parou de correr"))

	_is_moving = is_moving
	_is_running_emitted = is_running
	_facing_direction = facing_direction
	movement_state_changed.emit(_is_moving, _is_running_emitted, _facing_direction)


# Reage à mudança de estado de movimento tocando a animação correspondente. Só roda quando
# movement_state_changed é emitido (ou seja, quando o estado muda de verdade), não a cada frame.
func _on_movement_state_changed(is_moving: bool, is_running: bool, facing_direction: TopDown.Facing) -> void:
	var prefix: StringName = &"idle"
	if is_moving:
		prefix = &"run" if is_running else &"walk"
	_animated_sprite.play(TopDown.animation_name(prefix, facing_direction))


# [DEBUG] Setters e getters dos campos de velocidade do menu de debug (F4).
func _set_walk_speed(value: float) -> void:
	walk_speed = value
	print("[Player] - Velocidade andando ajustada para %.0f" % value)


# [DEBUG] Ver _set_walk_speed.
func _get_walk_speed() -> float:
	return walk_speed


# [DEBUG] Ver _set_walk_speed.
func _set_run_speed(value: float) -> void:
	run_speed = value
	print("[Player] - Velocidade correndo ajustada para %.0f" % value)


# [DEBUG] Ver _set_walk_speed.
func _get_run_speed() -> float:
	return run_speed


# [DEBUG] Roda a parte do autoteste que não mexe no jogo (a regra de tempo do ClickMoveGesture) e
# imprime o relatório no log. A parte que move um Player de verdade só roda pela linha de comando
# (tests/run_player_movement_self_test.gd), pra não sair empurrando o personagem da partida.
#
# Carregado por caminho, e não pelo nome da classe: o autoteste declara uma subclasse do Player, e
# citá-lo aqui pelo nome faria cada um dos dois scripts depender do outro pra compilar.
func _run_click_gesture_self_test() -> void:
	var self_test_script: GDScript = load(SELF_TEST_PATH) as GDScript
	if self_test_script == null or not self_test_script.can_instantiate():
		push_error("[Player] - ERRO: autoteste da movimentação não compilou (%s)" % SELF_TEST_PATH)
		return
	var self_test: RefCounted = self_test_script.new()
	self_test.call(&"run_gesture_cases")
	print(self_test.call(&"report"))


# Posição que a GameSession grava no save: a última em momento seguro, não a de agora.
func get_last_safe_position() -> Vector2:
	return _last_safe_position


# Põe o Player na posição de um save. Valor não finito (save editado à mão) é ignorado: o Player
# fica no ponto de partida. A checagem contra o mapa fica para o primeiro _physics_process (ver
# _validate_restored_position()), porque aqui a cena ainda está montando.
func restore_position(saved: Vector2) -> void:
	if not saved.is_finite():
		print("[Player] - Posição salva %s não é finita; ficando no ponto de partida" % [saved])
		return
	global_position = saved
	_last_safe_position = saved
	_needs_position_check = true
	print("[Player] - Posição restaurada do save: %s" % [saved])


# O jogador está no controle, acordado, fora de conversa e de troca de cena. Só nesses momentos a
# posição vale como ponto de retorno: sair no meio de um diálogo grava a posição de antes da
# abordagem. Pausa não entra na conta porque, com a árvore pausada, _physics_process nem
# roda. Combate e cutscene futuros entram aqui travando o input ou acontecendo no sonho.
func _is_in_safe_state() -> bool:
	return not _is_input_locked and not _is_approaching and not GameClock.is_dreaming() \
		and not GameManager.in_transition


# Confere se a posição restaurada caiu dentro da geometria do mapa (o mapa mudou desde o save). Se
# caiu, volta ao ponto de partida em vez de deixar o jogador preso numa parede. A máscara é só a do
# mundo, e o próprio corpo fica de fora da consulta.
func _validate_restored_position() -> void:
	_needs_position_check = false
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = WORLD_COLLISION_MASK
	query.exclude = [get_rid()]
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(query, 1)
	if hits.is_empty():
		return
	global_position = _spawn_position
	_last_safe_position = _spawn_position
	print("[Player] - Posição salva inválida, voltando ao ponto de partida")
