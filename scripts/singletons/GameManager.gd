## GameManager - Singleton padrão e mais genérico para utilizar no jogo

extends Node

## Espaço para sinais

# Emitido pela LoadingScreen quando a cena de destino termina de carregar e a troca real já
# ocorreu. O GameManager escuta este sinal para saber a hora certa de disparar o fade-in final.
signal scene_loaded

# Emitido quando qualquer preferência de diálogo muda. Signal direto, não evento do EventBus: o
# único ouvinte é a DialogueScreen, numa relação direta e permanente (ver docs/event_bus.md).
signal dialogue_preferences_changed

## Espaço para variáveis

# Esquemas de movimentação que o jogador pode escolher nas configurações. A ordem importa: é a
# mesma em que as opções aparecem no OptionButton da tela de Settings.
enum MovementScheme { KEYBOARD, CLICK }

# Modo de revelação do texto de diálogo (SPEC §14): instantâneo mostra a fala inteira de uma vez;
# progressivo é o typewriter (DialogueScreen._await_entry_then_continue).
enum TextReveal { INSTANT, PROGRESSIVE }

# Preferências de diálogo (SPEC §14.1). Mude sempre por set_dialogue_preference(): é o setter que
# aplica o clamp, persiste e avisa a DialogueScreen.
var dialogue_text_scale: float = 1.0          # 0.8 .. 2.0
var dialogue_use_alt_font: bool = false
var dialogue_panel_opacity: float = 0.82      # 0.82 .. 1.0
var dialogue_text_reveal: TextReveal = TextReveal.INSTANT
var dialogue_animation_multiplier: float = 1.0   # 1.0, 0.5 ou 0.0

# Variável a ser utilizada na transição de cenas, fica true no inicio da troca e passa para false após a troca
var in_transition: bool = false

# Esquema de movimentação ativo, lido pelo Player a cada frame. O padrão é o teclado
# (WASD/setas/analógico); clique é opt-in pelo jogador.
#
# Quem altera isso a partir de uma escolha do jogador deve chamar set_movement_scheme(), nunca
# mexer na variável direto — é o setter que persiste em disco. Mesma divisão de responsabilidade
# que o AudioManager usa com o volume geral: o dono do estado é quem salva, e a tela de
# configurações só reflete e repassa.
var movement_scheme: MovementScheme = MovementScheme.KEYBOARD

# Arquivo próprio pras configurações de jogabilidade. Separado do user://settings.cfg de propósito:
# aquele arquivo é reescrito inteiro pela tela de Settings a cada _save_settings(), então uma
# seção extra ali seria apagada na primeira mudança de idioma ou de modo de tela.
const GAMEPLAY_CONFIG_PATH: String = "user://gameplay_settings.cfg"

# Caminho da cena de loading exibida durante o carregamento assíncrono da cena de destino.
# Atenção: o layer do CanvasLayer da LoadingScreen precisa ser MAIOR que FADE_LAYER (ver
# abaixo), senão a barra de progresso fica escondida atrás do overlay preto.
const LOADING_SCENE_PATH: String = "res://scenes/ui/LoadingScreen.tscn"

# Layer do CanvasLayer usado no fade preto. Bem alto para ficar acima de qualquer cena comum.
const FADE_LAYER: int = 1001

# Tempo (em segundos) que _fade_change_scene espera pelo carregamento antes de desistir de
# trocar direto e mostrar a LoadingScreen. Cenas leves terminam dentro desse período e o jogador
# nunca chega a ver a tela de loading — só um fade um pouco mais longo, com a tela já preta.
const LOADING_GRACE_PERIOD_SECONDS: float = 0.15

# Caminho da cena de destino da troca em andamento. Preenchido em _fade_change_scene e lido pela
# LoadingScreen (via get_target_scene_path) para saber o que carregar.
var _target_scene_path: String = ""

# Caminho cujo load_threaded_request já foi disparado por _fade_change_scene durante o período
# de tolerância. A LoadingScreen consulta isso (via is_load_already_in_progress) para saber que
# não deve chamar load_threaded_request de novo — pedir duas vezes pro mesmo caminho dá erro.
var _load_in_progress_path: String = ""

## Espaço para variáveis onready

## Espaço para funções nativas

func _ready() -> void:
	_load_gameplay_settings()


## Espaço para funções personalizadas

# Troca o esquema de movimentação e persiste a escolha. Usar sempre este método (nunca a
# variável movement_scheme direto) quando a troca vier do jogador.
func set_movement_scheme(scheme: MovementScheme) -> void:
	movement_scheme = scheme
	_save_gameplay_settings()
	print("[GameManager] - Esquema de movimentação definido para %s" % MovementScheme.keys()[scheme])


# Muda uma preferência de diálogo, com o clamp de cada campo (SPEC §14.1), persiste e avisa a
# DialogueScreen. key é o nome do campo sem o prefixo "dialogue_" (ex.: &"text_scale").
func set_dialogue_preference(key: StringName, value: Variant) -> void:
	match key:
		&"text_scale":
			dialogue_text_scale = clampf(value, 0.8, 2.0)
		&"use_alt_font":
			dialogue_use_alt_font = value
		&"panel_opacity":
			dialogue_panel_opacity = clampf(value, 0.82, 1.0)
		&"text_reveal":
			dialogue_text_reveal = value as TextReveal
		&"animation_multiplier":
			dialogue_animation_multiplier = value
		_:
			push_warning("[GameManager] - AVISO: preferência de diálogo desconhecida: \"%s\"" % key)
			return
	_save_gameplay_settings()
	dialogue_preferences_changed.emit()

# Ponto de entrada público para qualquer troca de cena do projeto. Nenhum outro script deve
# chamar get_tree().change_scene_to_file()/change_scene_to_packed() diretamente.
func change_scene(scene_path: String, time: float = 0.5) -> void:
	_fade_change_scene(scene_path, time)


# Devolve o caminho da cena de destino da troca em andamento. Usado pela LoadingScreen, que é
# instanciada via change_scene_to_file (sem parâmetros) e por isso não recebe o caminho direto.
func get_target_scene_path() -> String:
	return _target_scene_path


# Diz se scene_path já está sendo carregada em thread por causa do período de tolerância. A
# LoadingScreen usa isso para não chamar load_threaded_request de novo pro mesmo caminho.
func is_load_already_in_progress(scene_path: String) -> bool:
	return _load_in_progress_path == scene_path


# Orquestra a troca de cena completa: fade-out, tentativa de carregamento dentro do período de
# tolerância (troca direto se der tempo), cena de loading só se necessário, e fade-in. Função
# privada, chamada apenas por change_scene().
func _fade_change_scene(scene_path: String, time: float = 0.5) -> void:
	in_transition = true
	_target_scene_path = scene_path

	# Segura o relógio durante a troca. Sem isso, o tempo de carregamento — que varia por máquina
	# e por cena — viraria tempo de jogo, e o mesmo trajeto custaria horários diferentes em PCs
	# diferentes.
	GameClock.freeze(&"transicao")

	print("[GameManager] - Iniciando troca de cena para \"%s\"" % scene_path)

	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = FADE_LAYER

	var fade: ColorRect = ColorRect.new()
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)

	canvas.add_child(fade)
	get_tree().root.add_child(canvas)

	# Fade-out: escurece a tela antes de decidir como trocar de cena.
	var tween_out: Tween = get_tree().create_tween()
	tween_out.tween_property(fade, "modulate:a", 1.0, time)
	await tween_out.finished

	var request_error: Error = ResourceLoader.load_threaded_request(scene_path)
	if request_error != OK:
		# Não deu nem pra iniciar o carregamento assíncrono (caminho inválido, etc). Cai pra
		# troca síncrona simples — ainda protegida pelo fade preto, então não gera um "pulo" visual.
		push_error("[GameManager] - Falha ao iniciar carregamento de \"%s\" (erro %d), trocando de forma síncrona" % [scene_path, request_error])
		get_tree().change_scene_to_file(scene_path)
		await get_tree().process_frame
	else:
		_load_in_progress_path = scene_path
		var grace_result: Dictionary = await _try_load_within_grace_period(scene_path)
		match grace_result["status"] as String:
			"loaded":
				# Carregou dentro do período de tolerância: troca direto, sem passar pela loading screen.
				print("[GameManager] - \"%s\" carregou dentro do período de tolerância, pulando a loading screen" % scene_path)
				get_tree().change_scene_to_packed(grace_result["scene"] as PackedScene)
				await get_tree().process_frame
			"failed":
				# Já logado dentro de _try_load_within_grace_period. Como ainda não trocamos de
				# cena, a cena atual continua válida — só revela ela de novo no fade-in abaixo.
				pass
			"pending":
				# Ainda carregando depois do período de tolerância: agora sim mostra a loading screen,
				# que assume o acompanhamento do carregamento já em andamento (não pede de novo).
				get_tree().change_scene_to_file(LOADING_SCENE_PATH)
				await scene_loaded
		_load_in_progress_path = ""

	# Fade-in: revela a cena de destino já carregada.
	var tween_in: Tween = get_tree().create_tween()
	tween_in.tween_property(fade, "modulate:a", 0.0, time)
	await tween_in.finished

	canvas.queue_free()
	in_transition = false
	GameClock.unfreeze(&"transicao")
	print("[GameManager] - Troca de cena para \"%s\" concluída" % scene_path)


# Faz polling do carregamento em andamento por até LOADING_GRACE_PERIOD_SECONDS. Devolve um dos
# três estados: {status: "loaded", scene: PackedScene}, {status: "failed"} ou {status: "pending"}
# (ainda carregando — quem chamou decide mostrar a loading screen).
#
# Importante: load_threaded_get só pode ser consumido uma vez por caminho — por isso, se o
# recurso carregado não for uma PackedScene válida, isso já é tratado como falha aqui mesmo
# (a LoadingScreen não teria como tentar de novo).
func _try_load_within_grace_period(scene_path: String) -> Dictionary:
	var start_msec: int = Time.get_ticks_msec()
	var grace_period_msec: int = int(LOADING_GRACE_PERIOD_SECONDS * 1000.0)

	while Time.get_ticks_msec() - start_msec < grace_period_msec:
		await get_tree().process_frame

		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded_resource: Resource = ResourceLoader.load_threaded_get(scene_path)
			var packed_scene: PackedScene = loaded_resource as PackedScene
			if packed_scene == null:
				push_error("[GameManager] - Recurso carregado não é uma PackedScene: \"%s\"" % scene_path)
				return { "status": "failed" }
			return { "status": "loaded", "scene": packed_scene }
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("[GameManager] - Carregamento de \"%s\" falhou" % scene_path)
			return { "status": "failed" }

	return { "status": "pending" }


# Salva as configurações de jogabilidade atuais em disco: gameplay (movimentação) e diálogo
# (SPEC §14.1) juntas, sempre a partir do estado em memória — as duas seções são regravadas a cada
# chamada de propósito, senão uma apagaria a outra na primeira mudança (mesmo cuidado do
# Settings.gd com o user://settings.cfg).
func _save_gameplay_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("gameplay", "movement_scheme", int(movement_scheme))
	config.set_value("dialogue", "text_scale", dialogue_text_scale)
	config.set_value("dialogue", "use_alt_font", dialogue_use_alt_font)
	config.set_value("dialogue", "panel_opacity", dialogue_panel_opacity)
	config.set_value("dialogue", "text_reveal", int(dialogue_text_reveal))
	config.set_value("dialogue", "animation_multiplier", dialogue_animation_multiplier)
	config.save(GAMEPLAY_CONFIG_PATH)
	print("[GameManager] - Configurações de jogabilidade salvas")


# Carrega as configurações de jogabilidade do disco, caindo no padrão se não houver arquivo (1ª
# vez rodando o jogo) ou se um valor salvo não for válido — o arquivo fica em user:// e pode ter
# sido editado à mão ou vir de uma versão antiga com outros esquemas.
func _load_gameplay_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(GAMEPLAY_CONFIG_PATH) != OK:
		movement_scheme = MovementScheme.KEYBOARD
		print("[GameManager] - Nenhuma configuração de jogabilidade salva, usando os padrões")
		return

	var saved_scheme: int = config.get_value("gameplay", "movement_scheme", int(MovementScheme.KEYBOARD))
	if not MovementScheme.values().has(saved_scheme):
		push_warning("[GameManager] - Esquema de movimentação salvo inválido (%d), usando o padrão" % saved_scheme)
		saved_scheme = int(MovementScheme.KEYBOARD)
	movement_scheme = saved_scheme as MovementScheme

	dialogue_text_scale = clampf(config.get_value("dialogue", "text_scale", dialogue_text_scale), 0.8, 2.0)
	dialogue_use_alt_font = config.get_value("dialogue", "use_alt_font", dialogue_use_alt_font)
	dialogue_panel_opacity = clampf(config.get_value("dialogue", "panel_opacity", dialogue_panel_opacity), 0.82, 1.0)
	var saved_reveal: int = config.get_value("dialogue", "text_reveal", int(dialogue_text_reveal))
	dialogue_text_reveal = saved_reveal as TextReveal if TextReveal.values().has(saved_reveal) else TextReveal.INSTANT
	dialogue_animation_multiplier = config.get_value("dialogue", "animation_multiplier", dialogue_animation_multiplier)

	print("[GameManager] - Configurações de jogabilidade carregadas (movimentação: %s)" % MovementScheme.keys()[movement_scheme])
