# DebugScreenTester.gd — Força a janela do jogo a proporções de tela conhecidas (16:9, 16:10, 4:3,
# 21:9 e retrato 9:16) para conferir o enquadramento em cada uma delas sem ninguém precisar
# arrastar a borda da janela na mão.
#
# Por que redimensionar a janela de verdade em vez de recortar a imagem: o projeto usa
# stretch/mode="canvas_items" com aspect="expand", e "expand" quer dizer que o jogo GANHA área
# visível numa janela mais larga e PERDE numa mais estreita. Uma simulação que só desenhasse
# barras pretas por cima mostraria um enquadramento que a build de verdade nunca vai ter — o
# oposto do que este testador existe para validar.
#
# Vive como nó filho do Autoload DebugMenu e registra a própria seção, então não existe em build
# de release. Quando o sistema de configuração do jogo existir, é aqui que ele encosta: a lista de
# proporções e o cálculo de tamanho já são o que uma tela de opções de vídeo precisa.
class_name DebugScreenTester
extends Node

const SECTION: StringName = &"Tela"
# Índice 0 é o tamanho com que a janela nasceu — é para onde "Restaurar tamanho original" volta.
const NATIVE_INDEX: int = 0
const ASPECT_NAMES: PackedStringArray = ["Nativo", "16:9", "16:10", "4:3", "21:9", "9:16"]
# Mesma ordem de ASPECT_NAMES. O 0.0 do "Nativo" nunca vira largura: esse índice usa o tamanho
# guardado no boot (ver _target_size()).
const ASPECT_RATIOS: Array[float] = [0.0, 16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0, 21.0 / 9.0, 9.0 / 16.0]
# Folga descontada da área útil do monitor. A área útil já desconta a barra de tarefas, mas não a
# barra de título da própria janela — sem esta folga, um preset alto nasce com o título fora da
# tela e não dá para arrastar a janela de volta.
const SCREEN_MARGIN: Vector2i = Vector2i(0, 64)
const MIN_WINDOW_SIZE: Vector2i = Vector2i(320, 200)
const MIN_BASE_HEIGHT: int = 240
const MAX_BASE_HEIGHT: int = 2160
const BASE_HEIGHT_STEP: int = 60

# Proporção escolhida e altura de onde a largura é derivada. Não são @export porque este nó é
# criado por código e nunca aparece numa cena: os dois são editáveis em runtime pelo próprio menu
# (F4) e pelo console (`tela.proporcao`, `tela.altura_base`), que é o "Inspetor" de uma ferramenta
# de debug.
var _aspect_index: int = NATIVE_INDEX
var _base_height: int = 720
# Tamanho da janela no boot, lido uma vez. Redimensionar a janela na mão depois disto não muda a
# referência: "original" aqui quer dizer "como o jogo abriu".
var _native_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_native_size = get_window().size
	# [DEBUG] Seção "Tela": simulação de proporção de tela (ver docs/debug_menu.md).
	DebugMenu.register_value(SECTION, "Proporção", _on_aspect_changed,
		DebugParam.enum_value("proporcao", ASPECT_NAMES, _aspect_index), _get_aspect_index)
	DebugMenu.register_value(SECTION, "Altura base (px)", _on_base_height_changed,
		DebugParam.int_value("altura", _base_height, MIN_BASE_HEIGHT, MAX_BASE_HEIGHT, BASE_HEIGHT_STEP),
		_get_base_height)
	DebugMenu.register_action(SECTION, "Próxima proporção", _cycle_aspect)
	DebugMenu.register_action(SECTION, "Restaurar tamanho original", _restore_native)


# Troca a proporção simulada. Recebe o índice em ASPECT_NAMES, que é o que o OptionButton do menu
# e o argumento do console entregam.
func _on_aspect_changed(index: int) -> void:
	_aspect_index = clampi(index, 0, ASPECT_NAMES.size() - 1)
	_apply()


# Troca a altura de referência: a largura sai dela e da proporção escolhida, então mexer aqui vale
# para todos os presets de uma vez. Serve para testar a mesma proporção em resoluções diferentes,
# que é onde escala de fonte e de HUD costumam quebrar.
func _on_base_height_changed(height: int) -> void:
	_base_height = clampi(height, MIN_BASE_HEIGHT, MAX_BASE_HEIGHT)
	_apply()


# Passa para a próxima proporção da lista, dando a volta no fim. Existe porque comparar
# enquadramentos é um gesto repetido: clicar quatro vezes no mesmo botão é mais rápido do que
# abrir a lista de opções quatro vezes.
func _cycle_aspect() -> void:
	_aspect_index = (_aspect_index + 1) % ASPECT_NAMES.size()
	_apply()


# Devolve a janela ao tamanho com que o jogo abriu.
func _restore_native() -> void:
	_aspect_index = NATIVE_INDEX
	_apply()


# Lido pelo menu ao remontar a UI: sem isto, o seletor mostraria a cópia guardada no registro e
# desencontraria depois de um "Próxima proporção".
func _get_aspect_index() -> int:
	return _aspect_index


# Mesmo motivo do getter acima, para o campo de altura.
func _get_base_height() -> int:
	return _base_height


# Aplica o preset atual à janela de verdade. Tela cheia é desfeita antes porque redimensionar uma
# janela em fullscreen não faz nada e o preset sairia silenciosamente ignorado.
func _apply() -> void:
	var window: Window = get_window()
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
		print("[DebugScreen] - Janela saiu de tela cheia/maximizada para aplicar o preset")
	var target: Vector2i = _target_size()
	window.size = target
	# Sem centralizar, um preset mais alto que o anterior cresce para baixo e o rodapé some atrás
	# da barra de tarefas.
	window.move_to_center()
	print("[DebugScreen] - Proporção \"%s\" aplicada: janela %dx%d (%.2f:1)" % [
		ASPECT_NAMES[_aspect_index], target.x, target.y, float(target.x) / float(maxi(target.y, 1))
	])


# Tamanho de janela do preset atual, já reduzido para caber no monitor.
func _target_size() -> Vector2i:
	if _aspect_index == NATIVE_INDEX:
		return _fit_to_screen(_native_size)
	var width: int = roundi(float(_base_height) * ASPECT_RATIOS[_aspect_index])
	return _fit_to_screen(Vector2i(width, _base_height))


# Encolhe o tamanho pedido até caber na área útil do monitor, aplicando o MESMO fator nos dois
# eixos: encolher só um eixo mudaria justamente a proporção que se está testando. Um 21:9 a 1080
# de altura vira 21:9 menor num monitor 1080p, e não um 16:9 disfarçado.
func _fit_to_screen(size: Vector2i) -> Vector2i:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var limit: Vector2i = usable.size - SCREEN_MARGIN
	var shrink: float = minf(1.0, minf(
		float(limit.x) / float(maxi(size.x, 1)),
		float(limit.y) / float(maxi(size.y, 1))
	))
	var fitted: Vector2i = Vector2i(roundi(float(size.x) * shrink), roundi(float(size.y) * shrink))
	return Vector2i(maxi(fitted.x, MIN_WINDOW_SIZE.x), maxi(fitted.y, MIN_WINDOW_SIZE.y))
