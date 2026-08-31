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
const LOADING_SCENE_PATH: String = "res://scenes/loading_screen/LoadingScreen.tscn"

# Layer do CanvasLayer usado no fade preto. Bem alto para ficar acima de qualquer cena comum.
const FADE_LAYER: int = 1001

# Caminho da cena de destino da troca em andamento. Preenchido em _fade_change_scene e lido pela
# LoadingScreen (via get_target_scene_path) para saber o que carregar.
var _target_scene_path: String = ""

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


# Orquestra a troca de cena completa: fade-out, cena de loading, carregamento assíncrono
# (feito pela LoadingScreen) e fade-in. Função privada, chamada apenas por change_scene().
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

	# Fade-out: escurece a tela antes de trocar para a cena de loading.
	var tween_out: Tween = get_tree().create_tween()
	tween_out.tween_property(fade, "modulate:a", 1.0, time)
	await tween_out.finished

	# A partir daqui a LoadingScreen assume: carrega a cena de destino de forma assíncrona e
	# faz a troca final quando terminar.
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)

	# Espera a LoadingScreen avisar que a cena de destino já foi carregada e trocada.
	await scene_loaded

	# Fade-in: revela a cena de destino já carregada.
	var tween_in: Tween = get_tree().create_tween()
	tween_in.tween_property(fade, "modulate:a", 0.0, time)
	await tween_in.finished

	canvas.queue_free()
	in_transition = false
	print("[GameManager] - Troca de cena para \"%s\" concluída" % scene_path)
