## LoadingScreen - Cena intermediária exibida durante a troca de cenas.
## Carrega a cena de destino de forma assíncrona (thread separada) e mostra o progresso,
## evitando travar o jogo em carregamentos pesados. O GameManager troca para esta cena e ela
## se vira sozinha: descobre o que carregar, carrega, e faz a troca final quando termina.
##
## O root é um CanvasLayer (e não um Control puro) de propósito: o GameManager cobre a tela com
## um overlay preto (CanvasLayer.layer = GameManager.FADE_LAYER) durante toda a transição, então
## o layer daqui precisa ser maior para a barra de progresso continuar visível por cima do preto.

extends CanvasLayer

## Espaço para sinais

## Espaço para variáveis

# Tempo mínimo (em segundos) que a tela de loading fica visível, mesmo com carregamento
# instantâneo. Evita o "piscar" da tela em cenas leves.
@export var minimum_display_time: float = 0.5

# Caminho da cena que está sendo carregada, lido do GameManager em _ready().
var _scene_path: String = ""

# Marca se já existe um carregamento em andamento, evita reenviar o pedido a cada frame.
var _loading_requested: bool = false

# Instante (em ms) em que o carregamento começou, usado para calcular o tempo mínimo de exibição.
var _start_time_msec: int = 0

## Espaço para variáveis onready

@onready var _progress_bar: ProgressBar = $Layout/ProgressBar

## Espaço para funções nativas

func _ready() -> void:
	_start_time_msec = Time.get_ticks_msec()
	_scene_path = GameManager.get_target_scene_path()
	_request_loading()


func _process(_delta: float) -> void:
	if not _loading_requested:
		return
	_poll_loading_status()

## Espaço para funções personalizadas

# Dispara o carregamento assíncrono da cena de destino em uma thread separada — ou, se o
# GameManager já iniciou esse carregamento durante o período de tolerância (antes de decidir que
# esta tela era necessária), só passa a acompanhar o que já está em andamento.
func _request_loading() -> void:
	if _scene_path.is_empty():
		push_error("[LoadingScreen] - Nenhuma cena de destino definida pelo GameManager")
		return

	if GameManager.is_load_already_in_progress(_scene_path):
		print("[LoadingScreen] - Carregamento de \"%s\" já estava em andamento, acompanhando" % _scene_path)
		_loading_requested = true
		return

	var error: Error = ResourceLoader.load_threaded_request(_scene_path)
	if error != OK:
		push_error("[LoadingScreen] - Falha ao iniciar carregamento de \"%s\" (erro %d)" % [_scene_path, error])
		return

	print("[LoadingScreen] - Iniciando carregamento assíncrono de \"%s\"" % _scene_path)
	_loading_requested = true


# Consulta o status do carregamento a cada frame e atualiza a barra de progresso proporcionalmente.
func _poll_loading_status() -> void:
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_progress_bar.value = float(progress[0]) * 100.0
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading_requested = false
			_progress_bar.value = 100.0
			_finish_loading()
		ResourceLoader.THREAD_LOAD_FAILED:
			_loading_requested = false
			push_error("[LoadingScreen] - Carregamento de \"%s\" falhou" % _scene_path)
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading_requested = false
			push_error("[LoadingScreen] - Recurso inválido: \"%s\"" % _scene_path)


# Busca a cena já carregada, garante o tempo mínimo de exibição, troca para a cena de destino e
# avisa o GameManager (via sinal) para disparar o fade-in final.
func _finish_loading() -> void:
	var loaded_resource: Resource = ResourceLoader.load_threaded_get(_scene_path)
	var packed_scene: PackedScene = loaded_resource as PackedScene
	if packed_scene == null:
		push_error("[LoadingScreen] - Recurso carregado não é uma PackedScene: \"%s\"" % _scene_path)
		return

	var elapsed_msec: int = Time.get_ticks_msec() - _start_time_msec
	var remaining_msec: int = int(minimum_display_time * 1000.0) - elapsed_msec
	if remaining_msec > 0:
		await get_tree().create_timer(remaining_msec / 1000.0).timeout

	print("[LoadingScreen] - Carregamento de \"%s\" concluído, trocando de cena" % _scene_path)
	get_tree().change_scene_to_packed(packed_scene)
	GameManager.scene_loaded.emit()
