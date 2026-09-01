## GameManager - Singleton padrão e mais genérico para utilizar no jogo

extends Node

## Espaço para sinais

# Emitido pela LoadingScreen quando a cena de destino termina de carregar e a troca real já
# ocorreu. O GameManager escuta este sinal para saber a hora certa de disparar o fade-in final.
signal scene_loaded

## Espaço para variáveis

# Variável a ser utilizada na transição de cenas, fica true no inicio da troca e passa para false após a troca
var in_transition: bool = false

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

## Espaço para funções personalizadas

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
