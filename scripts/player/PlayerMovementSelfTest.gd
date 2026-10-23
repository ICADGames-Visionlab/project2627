# PlayerMovementSelfTest.gd — Autoteste da movimentação do jogador: andar e correr nos dois esquemas.
#
# Duas partes, com custos bem diferentes:
#
#   1. Gesto (run_gesture_cases): a regra de TEMPO do ClickMoveGesture — o que é clique, clique duplo e
#      segurar. Lógica pura, com o instante passado por parâmetro: roda instantâneo e não toca em nada
#      do jogo, por isso é a única parte exposta no menu de debug ("Autoteste do clique").
#
#   2. Player (run_player_cases): um Player de verdade, criado só para o teste e solto na raiz da
#      árvore, andando frame a frame. Confere o que o jogador VÊ: velocidade de caminhada ou corrida,
#      animação walk_/run_/idle_, seguir o mouse, parar ao soltar, conversa travando o movimento. Leva
#      alguns segundos de frames de física, e por isso só roda pela linha de comando
#      (tests/run_player_movement_self_test.gd).
#
# O "mouse" do Player de teste é um ponto qualquer escolhido pelo caso (ver FakePointerPlayer), o que
# deixa o teste rodar em --headless, onde não existe ponteiro. O botão do mouse e as teclas são
# simulados pelas próprias ações do Input Map (Input.action_press), então o Player lê o input pelo
# mesmo caminho do jogo; só o evento do clique é entregue direto no _unhandled_input dele.
#
# Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao jogador — ver
# docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"

const SPRITE_FRAMES_PATH: String = "res://resources/player_sprite_frames.tres"

# Folga na comparação de velocidades, em pixels por segundo. As velocidades testadas saem exatas da
# conta do TopDown (movimento puramente horizontal), então a folga só cobre arredondamento.
const SPEED_TOLERANCE: float = 1.0

# Frames de física usados pelos casos do Player. Contados em frames, e não em segundos, porque o
# relógio do gesto de clique é a soma dos delta de física (ver Player._click_clock): a 60 ticks por
# segundo, 1 frame = 1/60 s, com ou sem --fixed-fps.
const FRAMES_TAP: int = 3            # quanto dura um clique normal com o botão apertado
const FRAMES_SETTLE: int = 4         # o bastante para velocidade e animação refletirem uma mudança
const FRAMES_PAST_HOLD: int = 20     # passa com folga do click_hold_seconds padrão (0.25 s = 15)
const FRAMES_PAST_DOUBLE: int = 30   # passa com folga do double_click_seconds padrão (0.4 s = 24)
const FRAMES_ARRIVE: int = 90        # chega a um destino próximo (até ~300 px andando)

# Longe o bastante para o personagem nunca chegar durante um caso: medir velocidade exige que ele
# ainda esteja a caminho.
const FAR: float = 5000.0

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()
var _tree: SceneTree = null


# Player de teste: idêntico ao do jogo, exceto pela posição do "mouse", que o caso define à mão.
class FakePointerPlayer extends Player:
	var fake_pointer: Vector2 = Vector2.ZERO

	# Quando ligado, o "mouse" anda junto com o personagem, a pointer_offset dele — é o que acontece no
	# jogo com o mouse parado na tela, porque a câmera segue o personagem. Liga os casos de "segurar"
	# com o mouse perto do personagem, onde um alvo velho faz ele chegar e parar a cada retraçado.
	var pointer_follows_player: bool = false
	var pointer_offset: Vector2 = Vector2.ZERO

	# Troca o mouse de verdade pelo ponto escolhido pelo caso (ver Player._get_pointer_world_position).
	func _get_pointer_world_position() -> Vector2:
		if pointer_follows_player:
			return global_position + pointer_offset
		return fake_pointer


# Roda as duas partes. Assíncrono: a parte do Player espera frames de física de verdade, então quem
# chama precisa de await.
func run(tree: SceneTree) -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()
	_run_gesture_cases_into_report()
	await _run_player_cases_into_report(tree)


# Só a parte do gesto (instantânea, sem árvore de cena). É o que o menu de debug roda.
func run_gesture_cases() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()
	_run_gesture_cases_into_report()


# Relatório da última execução, pronto para print(): o resumo na primeira linha e um ✓/✗ por caso.
func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[Player] - Autoteste da movimentação: %d ok, %d falha(s)" % [passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# ---------------------------------------------------------------------------------------------------
# Parte 1 — ClickMoveGesture
# ---------------------------------------------------------------------------------------------------

# Todos os casos do gesto, na ordem em que aparecem no relatório.
func _run_gesture_cases_into_report() -> void:
	_lines.append("  Gesto de clique (ClickMoveGesture):")
	_test_gesture_single_and_double_click()
	_test_gesture_double_click_limits()
	_test_gesture_hold()
	_test_gesture_hold_after_double_click()
	_test_gesture_lost_release_and_reset()


# Clique simples anda, dois cliques rápidos no mesmo lugar correm, e o terceiro continua correndo.
func _test_gesture_single_and_double_click() -> void:
	var gesture: ClickMoveGesture = _make_gesture()
	var first: ClickMoveGesture.Command = gesture.press(0.0, Vector2(100, 100))
	_expect("Primeiro clique pede destino, andando",
		first == ClickMoveGesture.Command.GO_TO and not gesture.is_running,
		"veio %s, correndo=%s" % [_command_name(first), gesture.is_running])
	gesture.release(0.05)

	var second: ClickMoveGesture.Command = gesture.press(0.2, Vector2(103, 98))
	_expect("Segundo clique rápido perto do primeiro pede destino, correndo",
		second == ClickMoveGesture.Command.GO_TO and gesture.is_running,
		"veio %s, correndo=%s" % [_command_name(second), gesture.is_running])
	gesture.release(0.25)

	gesture.press(0.4, Vector2(100, 100))
	_expect("Terceiro clique rápido no mesmo lugar continua correndo", gesture.is_running, "voltou a andar")
	gesture.release(0.45)

	var late: ClickMoveGesture.Command = gesture.release(0.5)
	_expect("Soltar sem nada apertado não faz nada", late == ClickMoveGesture.Command.NONE,
		"veio %s" % _command_name(late))
	_expect("update() sem nada apertado não faz nada",
		gesture.update(10.0, false) == ClickMoveGesture.Command.NONE and not gesture.is_following,
		"começou a seguir o mouse sozinho")


# Os dois limites do clique duplo: tempo e distância na tela.
func _test_gesture_double_click_limits() -> void:
	var gesture: ClickMoveGesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.release(0.05)
	gesture.press(0.0 + gesture.double_click_seconds, Vector2(100, 100))
	_expect("Segundo clique exatamente no limite de tempo ainda é clique duplo", gesture.is_running, "andou")

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.release(0.05)
	gesture.press(gesture.double_click_seconds + 0.05, Vector2(100, 100))
	_expect("Segundo clique depois do limite de tempo anda", not gesture.is_running, "correu")

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.release(0.05)
	gesture.press(0.15, Vector2(100 + gesture.double_click_distance + 1.0, 100))
	_expect("Segundo clique rápido longe do primeiro (outro destino) anda", not gesture.is_running, "correu")


# Segurar: vira "seguir o mouse" só depois de hold_seconds, e soltar para de seguir.
func _test_gesture_hold() -> void:
	var gesture: ClickMoveGesture = _make_gesture()
	gesture.press(1.0, Vector2(100, 100))

	var early: ClickMoveGesture.Command = gesture.update(1.0 + gesture.hold_seconds * 0.5, true)
	_expect("Antes do tempo de segurar ainda é clique", early == ClickMoveGesture.Command.NONE
		and not gesture.is_following, "veio %s" % _command_name(early))

	var start: ClickMoveGesture.Command = gesture.update(1.0 + gesture.hold_seconds, true)
	_expect("Ao atingir o tempo de segurar passa a seguir o mouse, andando",
		start == ClickMoveGesture.Command.START_FOLLOW and gesture.is_following and not gesture.is_running,
		"veio %s, seguindo=%s, correndo=%s" % [_command_name(start), gesture.is_following, gesture.is_running])

	var again: ClickMoveGesture.Command = gesture.update(2.0, true)
	_expect("Continuar segurando não repete o START_FOLLOW", again == ClickMoveGesture.Command.NONE,
		"veio %s" % _command_name(again))

	var stop: ClickMoveGesture.Command = gesture.release(2.5)
	_expect("Soltar depois de segurar para de seguir o mouse",
		stop == ClickMoveGesture.Command.STOP_FOLLOW and not gesture.is_following,
		"veio %s" % _command_name(stop))

	var quick: ClickMoveGesture.Command = gesture.press(10.0, Vector2(300, 300))
	_expect("Clique logo depois de um segurar não vira clique duplo",
		quick == ClickMoveGesture.Command.GO_TO and not gesture.is_running, "correu")
	var quick_release: ClickMoveGesture.Command = gesture.release(10.05)
	_expect("Soltar um clique curto não para nada (o destino já foi pedido)",
		quick_release == ClickMoveGesture.Command.NONE, "veio %s" % _command_name(quick_release))

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.update(gesture.hold_seconds, true)
	gesture.release(1.0)
	gesture.press(1.1, Vector2(100, 100))
	_expect("Segurar, soltar e clicar rápido no mesmo lugar anda (o segurar não conta como 1º clique)",
		not gesture.is_running, "correu")


# Segurar o segundo clique de um clique duplo segue o mouse correndo.
func _test_gesture_hold_after_double_click() -> void:
	var gesture: ClickMoveGesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.release(0.05)
	gesture.press(0.2, Vector2(100, 100))
	var start: ClickMoveGesture.Command = gesture.update(0.2 + gesture.hold_seconds, true)
	_expect("Clique duplo segurado segue o mouse correndo",
		start == ClickMoveGesture.Command.START_FOLLOW and gesture.is_running,
		"veio %s, correndo=%s" % [_command_name(start), gesture.is_running])
	gesture.release(2.0)
	_expect("Depois de soltar, o trajeto final continua correndo", gesture.is_running, "voltou a andar")


# Redes de segurança: soltar que se perdeu e reset().
func _test_gesture_lost_release_and_reset() -> void:
	var gesture: ClickMoveGesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.update(gesture.hold_seconds, true)
	var lost: ClickMoveGesture.Command = gesture.update(1.0, false)
	_expect("Botão solto sem o evento chegar cancela o seguir o mouse (sem destino novo)",
		lost == ClickMoveGesture.Command.CANCEL_FOLLOW and not gesture.is_following and not gesture.is_pressed(),
		"veio %s" % _command_name(lost))

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	var lost_click: ClickMoveGesture.Command = gesture.update(0.05, false)
	_expect("Clique curto com o soltar perdido só é encerrado, sem seguir o mouse",
		lost_click == ClickMoveGesture.Command.NONE and not gesture.is_pressed(),
		"veio %s, apertado=%s" % [_command_name(lost_click), gesture.is_pressed()])

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.update(gesture.hold_seconds, true)
	gesture.reset()
	_expect("reset() para de seguir e solta o botão", not gesture.is_following and not gesture.is_pressed()
		and gesture.update(5.0, true) == ClickMoveGesture.Command.NONE, "continuou seguindo")

	gesture = _make_gesture()
	gesture.press(0.0, Vector2(100, 100))
	gesture.release(0.05)
	gesture.reset()
	gesture.press(0.1, Vector2(100, 100))
	_expect("reset() esquece o clique anterior (não forma clique duplo)", not gesture.is_running, "correu")


# Gesto com os mesmos tempos e distância padrão do Player, fixados aqui pra um ajuste de
# balanceamento no Inspector não mudar o significado dos casos.
func _make_gesture() -> ClickMoveGesture:
	var gesture: ClickMoveGesture = ClickMoveGesture.new()
	gesture.hold_seconds = 0.25
	gesture.double_click_seconds = 0.4
	gesture.double_click_distance = 24.0
	return gesture


# Nome legível de um Command, para as mensagens de falha.
func _command_name(command: ClickMoveGesture.Command) -> String:
	return ClickMoveGesture.Command.keys()[command]


# ---------------------------------------------------------------------------------------------------
# Parte 2 — Player de verdade
# ---------------------------------------------------------------------------------------------------

# Todos os casos do Player. Guarda e devolve o esquema de movimento e solta todas as ações no fim,
# pra não deixar o jogo (ou o próximo teste) com uma tecla "presa".
func _run_player_cases_into_report(tree: SceneTree) -> void:
	_tree = tree
	var original_scheme: GameManager.MovementScheme = GameManager.movement_scheme

	_lines.append("  Teclado:")
	await _test_keyboard()
	_lines.append("  Clique:")
	await _test_click_walk_and_arrive()
	await _test_click_double_click_runs()
	await _test_click_double_click_limits()
	await _test_click_hold_follows()
	await _test_click_hold_pointer_near_player()
	await _test_click_double_click_hold_runs()
	await _test_click_safety_nets()
	await _test_click_interruptions()
	_lines.append("  Teclado + clique:")
	await _test_both_keyboard_and_click()
	await _test_both_keyboard_overrides_click()

	_release_all_actions()
	GameManager.movement_scheme = original_scheme


# WASD anda; com SHIFT corre; soltar o SHIFT volta a andar; SHIFT parado não anima corrida.
func _test_keyboard() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.KEYBOARD)

	Input.action_press(&"move_right")
	await _step(FRAMES_SETTLE)
	_expect_motion("WASD sem SHIFT anda", player, player.walk_speed, &"walk_e")

	Input.action_press(&"move_run")
	await _step(FRAMES_SETTLE)
	_expect_motion("WASD com SHIFT corre", player, player.run_speed, &"run_e")

	Input.action_release(&"move_run")
	await _step(FRAMES_SETTLE)
	_expect_motion("Soltar o SHIFT no meio do caminho volta a andar", player, player.walk_speed, &"walk_e")

	Input.action_release(&"move_right")
	Input.action_press(&"move_run")
	await _step(FRAMES_SETTLE)
	_expect_motion("SHIFT sem direção fica parado, com animação de parado", player, 0.0, &"idle_e")

	Input.action_press(&"move_left")
	await _step(FRAMES_SETTLE)
	_expect_motion("Segurar o SHIFT antes de andar já sai correndo", player, player.run_speed, &"run_w")

	_release_all_actions()
	await _despawn(player)

	# O SHIFT é só do teclado: no esquema de clique ele não transforma um clique simples em corrida.
	player = await _spawn_player(GameManager.MovementScheme.CLICK)
	Input.action_press(&"move_run")
	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("No esquema de clique o SHIFT não faz correr", player, player.walk_speed, &"walk_e")
	_release_all_actions()
	await _despawn(player)


# Clique simples anda até o ponto e para nele.
func _test_click_walk_and_arrive() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Clique simples anda até o ponto", player, player.walk_speed, &"walk_e")

	var target: Vector2 = player.global_position + Vector2(-200.0, 0.0)
	await _tap(player, target, Vector2(700, 500))
	await _step(FRAMES_ARRIVE)
	_expect_motion("Chegando ao ponto clicado, para com animação de parado", player, 0.0, &"idle_w")
	_expect("Parou em cima do ponto clicado",
		player.global_position.distance_to(target) <= Player.CLICK_ARRIVAL_DISTANCE,
		"parou a %.1f px" % player.global_position.distance_to(target))

	await _despawn(player)


# Clique duplo corre; o próximo clique simples volta a andar.
func _test_click_double_click_runs() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	await _double_click(player, Vector2(FAR, 0.0), Vector2(900, 500), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Clique duplo corre até o ponto", player, player.run_speed, &"run_e")

	await _step(FRAMES_PAST_DOUBLE)
	await _tap(player, Vector2(-FAR, 0.0), Vector2(300, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Clique simples depois de correr volta a andar", player, player.walk_speed, &"walk_w")

	await _step(FRAMES_PAST_DOUBLE)
	var target: Vector2 = player.global_position + Vector2(250.0, 0.0)
	await _double_click(player, target, Vector2(900, 500), Vector2(900, 500))
	await _step(FRAMES_ARRIVE)
	_expect_motion("Chegando correndo, para com animação de parado", player, 0.0, &"idle_e")

	await _step(FRAMES_PAST_DOUBLE)
	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Depois de chegar correndo, o clique simples seguinte anda", player, player.walk_speed, &"walk_e")

	await _despawn(player)


# Dois cliques lentos, ou em lugares diferentes da tela, não correm.
func _test_click_double_click_limits() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_DOUBLE)
	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Dois cliques lentos no mesmo lugar andam", player, player.walk_speed, &"walk_e")

	await _step(FRAMES_PAST_DOUBLE)
	await _double_click(player, Vector2(FAR, 0.0), Vector2(900, 500), Vector2(900 + 200, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Dois cliques rápidos em lugares diferentes da tela andam", player, player.walk_speed, &"walk_e")

	await _despawn(player)


# Segurar segue o mouse andando, inclusive quando ele muda de lado, e soltar termina no mouse.
func _test_click_hold_follows() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)
	var repath_frames: int = _frames_for_seconds(player.follow_repath_seconds) + FRAMES_SETTLE

	_press(player, player.global_position, Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	_expect("Segurar o clique passa a seguir o mouse", player._click_gesture.is_following, "não está seguindo")
	_expect_motion("Segurando com o mouse em cima do personagem: fica parado", player, 0.0, &"idle_s")
	await _step(FRAMES_SETTLE * 3)
	_expect_motion("... e continua parado, sem tremer", player, 0.0, &"idle_s")

	player.fake_pointer = player.global_position + Vector2(FAR, 0.0)
	await _step(repath_frames)
	_expect_motion("Mouse se afasta com o botão segurado: vai atrás dele andando", player,
		player.walk_speed, &"walk_e")

	player.fake_pointer = player.global_position + Vector2(-FAR, 0.0)
	await _step(repath_frames)
	_expect_motion("Mouse muda de lado com o botão segurado: o personagem vira e vai atrás", player,
		player.walk_speed, &"walk_w")

	var release_point: Vector2 = player.global_position + Vector2(150.0, 0.0)
	player.fake_pointer = release_point
	_release(player, Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect("Soltar para de seguir o mouse", not player._click_gesture.is_following, "continua seguindo")
	_expect_motion("Depois de soltar, termina o trajeto até o mouse, andando", player, player.walk_speed, &"walk_e")

	player.fake_pointer = player.global_position + Vector2(0.0, 4000.0)
	await _step(FRAMES_ARRIVE)
	_expect("Soltou: mexer o mouse não puxa mais o personagem",
		player.global_position.distance_to(release_point) <= Player.CLICK_ARRIVAL_DISTANCE,
		"parou a %.1f px do ponto em que soltou" % player.global_position.distance_to(release_point))
	_expect_motion("Chegou ao ponto em que soltou e parou", player, 0.0, &"idle_e")

	await _despawn(player)


# Segurar com o mouse parado na tela, perto do personagem: como a câmera o segue, o mouse anda junto
# com ele e fica sempre à mesma distância. O personagem precisa andar liso, sem parar um frame a cada
# retraçado do caminho (o bug que isso cobre: o destino era o mouse de até follow_repath_seconds atrás,
# e com o mouse perto ele alcançava esse ponto velho antes do retraçado seguinte).
func _test_click_hold_pointer_near_player() -> void:
	for is_running: bool in [false, true]:
		var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)
		var gait: String = "correndo" if is_running else "andando"
		var expected_speed: float = player.run_speed if is_running else player.walk_speed
		var prefix: String = "run_" if is_running else "walk_"
		player.pointer_offset = Vector2(30.0, 0.0)
		player.pointer_follows_player = true

		if is_running:
			await _tap(player, Vector2.ZERO, Vector2(900, 500))
			await _step(FRAMES_TAP * 2)
		_press(player, Vector2.ZERO, Vector2(900, 500))
		await _step(FRAMES_PAST_HOLD)

		var stopped_frames: int = 0
		var animation_changes: int = 0
		var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var last_animation: StringName = sprite.animation
		for i: int in FRAMES_ARRIVE:
			await _tree.physics_frame
			if absf(player.velocity.length() - expected_speed) > SPEED_TOLERANCE:
				stopped_frames += 1
			if sprite.animation != last_animation:
				animation_changes += 1
				last_animation = sprite.animation
		_expect("Segurando %s com o mouse perto do personagem: anda liso, sem parar a cada retraçado" % gait,
			stopped_frames == 0 and animation_changes == 0 and String(sprite.animation).begins_with(prefix),
			"%d frame(s) fora da velocidade, %d troca(s) de animação, terminou em \"%s\""
				% [stopped_frames, animation_changes, sprite.animation])

		player.pointer_offset = Vector2(2.0, 0.0)
		await _step(FRAMES_SETTLE)
		_expect_motion("Segurando %s com o mouse em cima do personagem: para" % gait, player, 0.0, &"idle_e")
		await _step(_frames_for_seconds(player.follow_repath_seconds) * 3)
		_expect_motion("... e continua parado, sem tremer", player, 0.0, &"idle_e")

		_release(player, Vector2(900, 500))
		await _despawn(player)


# Clique duplo com o segundo clique segurado segue o mouse correndo.
func _test_click_double_click_hold_runs() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_TAP * 2)
	_press(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	_expect("Clique duplo segurado segue o mouse", player._click_gesture.is_following, "não está seguindo")
	_expect_motion("Clique duplo segurado corre", player, player.run_speed, &"run_e")

	player.fake_pointer = player.global_position + Vector2(-FAR, 0.0)
	await _step(_frames_for_seconds(player.follow_repath_seconds) + FRAMES_SETTLE)
	_expect_motion("Correndo atrás do mouse, vira junto com ele", player, player.run_speed, &"run_w")

	_release(player, Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Soltar depois do clique duplo termina o trajeto correndo", player, player.run_speed, &"run_w")

	await _despawn(player)


# Redes de segurança: soltar que se perdeu, soltar órfão.
func _test_click_safety_nets() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	_release(player, Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Soltar sem ter apertado (apertar engolido pela UI) não move", player, 0.0, &"idle_s")

	_press(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	# O botão sobe, mas o evento de soltar nunca chega ao Player (jogo pausado, menu por cima) — e o
	# mouse agora está em outro lugar, como em cima do "Continuar" do menu de pausa.
	player.fake_pointer = player.global_position + Vector2(-FAR, 0.0)
	Input.action_release(&"move_click")
	await _step(FRAMES_SETTLE)
	_expect("Botão solto sem o evento chegar: para de seguir o mouse", not player._click_gesture.is_following,
		"continua seguindo")
	_expect_motion("... e para onde está, sem ir até onde o mouse foi parar", player, 0.0, &"idle_e")
	await _step(FRAMES_PAST_HOLD)
	_expect_motion("... e continua parado", player, 0.0, &"idle_e")

	await _despawn(player)


# Conversa e troca de esquema interrompem o movimento e não deixam o gesto pendurado.
func _test_click_interruptions() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.CLICK)

	_press(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	# Chamado direto no Player, e não pelo EventBus: emitir o evento de verdade acordaria os outros
	# ouvintes da conversa (relógio, diálogo), que não fazem parte deste teste.
	player._on_conversation_started(&"__selftest", &"__selftest")
	await _step(FRAMES_SETTLE)
	_expect_motion("Conversa começando com o botão segurado: para na hora", player, 0.0, &"idle_e")
	player._on_conversation_ended(&"__selftest", &"__selftest")
	await _step(FRAMES_PAST_HOLD)
	_expect_motion("Fim da conversa com o botão ainda segurado: não volta a seguir sozinho", player, 0.0, &"idle_e")
	_release(player, Vector2(900, 500))

	await _step(FRAMES_PAST_DOUBLE)
	await _tap(player, Vector2(-FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Depois da conversa, clique simples volta a funcionar (andando)", player, player.walk_speed, &"walk_w")

	await _step(FRAMES_PAST_DOUBLE)
	_press(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	GameManager.movement_scheme = GameManager.MovementScheme.KEYBOARD
	await _step(FRAMES_SETTLE)
	_expect_motion("Trocar para o teclado com o botão segurado: para", player, 0.0, &"idle_e")
	GameManager.movement_scheme = GameManager.MovementScheme.CLICK
	await _step(FRAMES_PAST_HOLD)
	_expect_motion("Voltar para o clique com o botão ainda segurado: não retoma sozinho", player, 0.0, &"idle_e")
	_release(player, Vector2(900, 500))

	await _despawn(player)


# Esquema com os dois ligados: cada um continua com as próprias regras de andar/correr.
func _test_both_keyboard_and_click() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.BOTH)

	Input.action_press(&"move_right")
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: WASD anda", player, player.walk_speed, &"walk_e")
	Input.action_press(&"move_run")
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: WASD com SHIFT corre", player, player.run_speed, &"run_e")
	_release_all_actions()
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: soltar o teclado sem trajeto de clique para", player, 0.0, &"idle_e")

	await _tap(player, Vector2(-FAR, 0.0), Vector2(300, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: clique simples anda", player, player.walk_speed, &"walk_w")

	await _step(FRAMES_PAST_DOUBLE)
	await _double_click(player, Vector2(FAR, 0.0), Vector2(900, 500), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: clique duplo corre", player, player.run_speed, &"run_e")

	await _step(FRAMES_PAST_DOUBLE)
	Input.action_press(&"move_run")
	await _tap(player, Vector2(-FAR, 0.0), Vector2(300, 500))
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado + clique: SHIFT não transforma o clique simples em corrida", player,
		player.walk_speed, &"walk_w")
	_release_all_actions()

	await _step(FRAMES_PAST_DOUBLE)
	_press(player, player.global_position + Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	_expect("Teclado + clique: segurar acompanha o mouse", player._click_gesture.is_following, "não está seguindo")
	_expect_motion("Teclado + clique: segurando, acompanha andando", player, player.walk_speed, &"walk_e")
	_release(player, Vector2(900, 500))

	await _step(FRAMES_PAST_DOUBLE)
	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_TAP * 2)
	_press(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	_expect_motion("Teclado + clique: clique duplo segurado acompanha correndo", player, player.run_speed, &"run_e")
	_release(player, Vector2(900, 500))

	await _despawn(player)


# Com os dois ligados, apertar o teclado toma o controle: descarta o trajeto de clique, e com o
# botão do mouse ainda segurado volta a seguir o mouse quando o teclado é solto.
func _test_both_keyboard_overrides_click() -> void:
	var player: FakePointerPlayer = await _spawn_player(GameManager.MovementScheme.BOTH)

	await _tap(player, Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_SETTLE)
	Input.action_press(&"move_left")
	await _step(FRAMES_SETTLE)
	_expect_motion("Teclado no meio de um trajeto de clique: o teclado manda", player, player.walk_speed, &"walk_w")
	Input.action_release(&"move_left")
	await _step(FRAMES_SETTLE)
	_expect_motion("... e soltar o teclado não retoma o trajeto antigo", player, 0.0, &"idle_w")

	await _step(FRAMES_PAST_DOUBLE)
	player.fake_pointer = player.global_position + Vector2(FAR, 0.0)
	_press(player, player.fake_pointer, Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	Input.action_press(&"move_left")
	await _step(FRAMES_SETTLE)
	_expect_motion("Segurando o clique e apertando o teclado: o teclado manda", player, player.walk_speed, &"walk_w")
	Input.action_release(&"move_left")
	await _step(_frames_for_seconds(player.follow_repath_seconds) + FRAMES_SETTLE)
	_expect_motion("... e soltar o teclado com o botão ainda segurado volta a seguir o mouse", player,
		player.walk_speed, &"walk_e")
	_release(player, Vector2(900, 500))

	await _step(FRAMES_PAST_DOUBLE)
	_press(player, player.global_position + Vector2(FAR, 0.0), Vector2(900, 500))
	await _step(FRAMES_PAST_HOLD)
	GameManager.movement_scheme = GameManager.MovementScheme.KEYBOARD
	await _step(FRAMES_SETTLE)
	_expect_motion("Trocar de teclado + clique para só teclado com o botão segurado: para", player, 0.0, &"idle_e")
	_release(player, Vector2(900, 500))

	await _despawn(player)


# Cria um Player de teste na raiz da árvore, com o mesmo SpriteFrames do jogo (o que também confere
# que todas as animações walk_/run_/idle_ pedidas existem), sem colisão com nada, e espera o _ready.
func _spawn_player(scheme: GameManager.MovementScheme) -> FakePointerPlayer:
	_release_all_actions()
	GameManager.movement_scheme = scheme

	var player: FakePointerPlayer = FakePointerPlayer.new()
	player.name = "PlayerMovementSelfTest"
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	player.collision_layer = 0
	player.collision_mask = 0

	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = load(SPRITE_FRAMES_PATH) as SpriteFrames
	sprite.animation = &"idle_s"
	player.add_child(sprite)

	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	player.add_child(shape)

	_tree.root.add_child(player)
	player.global_position = Vector2.ZERO
	await _step(1)
	return player


# Remove o Player de teste e solta as ações, pra o caso seguinte começar limpo.
func _despawn(player: FakePointerPlayer) -> void:
	_release_all_actions()
	player.queue_free()
	await _step(1)


# Espera "frames" frames de física completos.
func _step(frames: int) -> void:
	for i: int in frames:
		await _tree.physics_frame
	# Mais um: physics_frame é emitido ANTES de os nós processarem o frame, então é só no começo do
	# frame seguinte que o último frame pedido já foi processado por todo mundo.
	await _tree.physics_frame


# Quantos frames de física cobrem "seconds", arredondando pra cima.
func _frames_for_seconds(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second)


# Aperta o botão com o "mouse" em world_point (mundo) / screen_point (tela, usado pelo clique duplo).
func _press(player: FakePointerPlayer, world_point: Vector2, screen_point: Vector2) -> void:
	player.fake_pointer = world_point
	Input.action_press(&"move_click")
	player._unhandled_input(_mouse_button_event(true, screen_point))


# Solta o botão: o estado da ação (lido pelo gesto a cada frame) e o evento (lido no _unhandled_input).
func _release(player: FakePointerPlayer, screen_point: Vector2) -> void:
	Input.action_release(&"move_click")
	player._unhandled_input(_mouse_button_event(false, screen_point))


# Um clique normal: aperta, segura por FRAMES_TAP e solta.
func _tap(player: FakePointerPlayer, world_point: Vector2, screen_point: Vector2) -> void:
	_press(player, world_point, screen_point)
	await _step(FRAMES_TAP)
	_release(player, screen_point)


# Dois cliques normais com FRAMES_TAP * 2 entre eles: bem dentro da janela de clique duplo padrão.
func _double_click(player: FakePointerPlayer, world_point: Vector2, first_screen: Vector2,
		second_screen: Vector2) -> void:
	await _tap(player, world_point, first_screen)
	await _step(FRAMES_TAP * 2)
	await _tap(player, world_point, second_screen)


# Evento de botão esquerdo do mouse, igual ao que a engine entrega (casa com a ação move_click).
func _mouse_button_event(pressed: bool, screen_point: Vector2) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = screen_point
	event.global_position = screen_point
	return event


# Solta todas as ações que os casos apertam. Chamado entre casos e no fim, pra nenhuma ficar "presa".
func _release_all_actions() -> void:
	for action: StringName in [&"move_click", &"move_run", &"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


# Confere de uma vez a velocidade (módulo) e a animação tocando.
func _expect_motion(label: String, player: FakePointerPlayer, expected_speed: float,
		expected_animation: StringName) -> void:
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var actual_speed: float = player.velocity.length()
	var speed_ok: bool = absf(actual_speed - expected_speed) <= SPEED_TOLERANCE
	var animation_ok: bool = sprite.animation == expected_animation
	_expect(label, speed_ok and animation_ok, "esperado %.0f px/s em \"%s\", veio %.0f px/s em \"%s\""
		% [expected_speed, expected_animation, actual_speed, sprite.animation])


# ---------------------------------------------------------------------------------------------------
# Registro
# ---------------------------------------------------------------------------------------------------

# Registra um caso: ✓ quando passou, ✗ com o detalhe quando falhou.
func _expect(label: String, passed: bool, failure_detail: String) -> void:
	if passed:
		passed_count += 1
		_lines.append("    %s %s" % [CHECK, label])
		return
	failed_count += 1
	_lines.append("    %s %s — %s" % [CROSS, label, failure_detail])
