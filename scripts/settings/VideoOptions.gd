class_name VideoOptions
extends RefCounted

# Catálogo e aplicação das opções de vídeo (modo de janela, resolução e proporção).
#
# Este script não guarda estado nem salva nada: quem é dono das escolhas do jogador e persiste em
# disco é o GameManager (set_video_preference / user://video_settings.cfg) — mesma divisão usada
# com o volume (AudioManager) e a movimentação. Aqui ficam só as listas de opções e o código que
# conversa com o DisplayServer, pra não inchar o GameManager com detalhes de janela.

# Modos de janela que o jogador pode escolher. A ordem importa: é a mesma em que as opções aparecem
# no OptionButton da tela de Settings.
#   FULLSCREEN -> tela cheia exclusiva (WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
#   BORDERLESS -> tela cheia sem borda (WINDOW_MODE_FULLSCREEN; é o padrão do project.godot)
#   WINDOWED   -> janela comum, no tamanho da resolução escolhida
enum WindowMode { FULLSCREEN, BORDERLESS, WINDOWED }

# Proporções de tela. AUTO estica a área de jogo pra qualquer formato de monitor (stretch aspect
# "expand", o padrão do projeto); as outras travam a proporção e põem barras pretas no que sobrar.
# A ordem importa pelo mesmo motivo do WindowMode.
enum AspectRatio { AUTO, RATIO_16_9, RATIO_16_10, RATIO_4_3, RATIO_21_9 }

# Largura/altura de cada proporção travada. Fica alinhado com o enum AspectRatio (AUTO não entra).
const ASPECT_RATIO_VALUES: Dictionary = {
	AspectRatio.RATIO_16_9: Vector2i(16, 9),
	AspectRatio.RATIO_16_10: Vector2i(16, 10),
	AspectRatio.RATIO_4_3: Vector2i(4, 3),
	AspectRatio.RATIO_21_9: Vector2i(21, 9),
}

# Resoluções oferecidas no modo janela, agrupadas pela proporção a que pertencem. A lista que o
# jogador vê é filtrada pela proporção escolhida e pelo tamanho do monitor (ver get_resolutions()).
# Pra oferecer uma resolução nova, basta adicioná-la no grupo certo.
const RESOLUTIONS: Dictionary = {
	AspectRatio.RATIO_16_9: [
		Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	],
	AspectRatio.RATIO_16_10: [
		Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050),
		Vector2i(1920, 1200), Vector2i(2560, 1600),
	],
	AspectRatio.RATIO_4_3: [
		Vector2i(1024, 768), Vector2i(1280, 960), Vector2i(1600, 1200),
	],
	AspectRatio.RATIO_21_9: [
		Vector2i(2560, 1080), Vector2i(3440, 1440),
	],
}

const DEFAULT_WINDOW_MODE: WindowMode = WindowMode.BORDERLESS
const DEFAULT_ASPECT_RATIO: AspectRatio = AspectRatio.AUTO
const DEFAULT_RESOLUTION: Vector2i = Vector2i(1920, 1080)

# Altura de referência do layout (window/size/viewport_height no project.godot). Com a proporção
# travada, a área de jogo vira BASE_HEIGHT de altura e a largura sai da proporção (ex.: 4:3 ->
# 1440x1080), então a UI ancorada continua no mesmo tamanho e só ganha/perde as laterais.
const BASE_HEIGHT: int = 1080


# Resoluções que o jogador pode escolher pra proporção dada, da menor pra maior. Só entram as que
# cabem no monitor atual; se nenhuma couber (monitor muito pequeno), devolve a menor da lista pra o
# dropdown nunca ficar vazio.
static func get_resolutions(aspect: AspectRatio) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if aspect == AspectRatio.AUTO:
		for group: Array in RESOLUTIONS.values():
			candidates.append_array(group)
	else:
		candidates.append_array(RESOLUTIONS[aspect])
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * a.y < b.x * b.y if a.x * a.y != b.x * b.y else a.x < b.x)

	var screen_size: Vector2i = _get_screen_size()
	var fitting: Array[Vector2i] = []
	for resolution: Vector2i in candidates:
		if resolution.x <= screen_size.x and resolution.y <= screen_size.y:
			fitting.append(resolution)
	if fitting.is_empty():
		fitting.append(candidates[0])
	return fitting


# Escolhe, dentro da lista válida pra proporção, a resolução mais próxima da desejada. Usado quando
# o jogador troca a proporção (a resolução antiga pode não existir na lista nova) e ao carregar um
# arquivo salvo de outro monitor.
static func closest_resolution(aspect: AspectRatio, desired: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_distance: int = -1
	for resolution: Vector2i in get_resolutions(aspect):
		var distance: int = absi(resolution.x * resolution.y - desired.x * desired.y)
		if best_distance == -1 or distance < best_distance:
			best = resolution
			best_distance = distance
	return best


# Texto exibido no dropdown de resolução (ex.: "1920 x 1080"). Números não precisam de tradução.
static func format_resolution(resolution: Vector2i) -> String:
	return "%d x %d" % [resolution.x, resolution.y]


# Aplica as três opções na janela principal (root). A proporção vai primeiro porque ela muda o
# content_scale da janela, e o modo/tamanho da janela vêm por último.
static func apply(root: Window, window_mode: WindowMode, aspect: AspectRatio, resolution: Vector2i) -> void:
	_apply_aspect_ratio(root, aspect)
	_apply_window_mode(root, window_mode, resolution)


static func _apply_aspect_ratio(root: Window, aspect: AspectRatio) -> void:
	if aspect == AspectRatio.AUTO:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", BASE_HEIGHT))
		)
		return
	var ratio: Vector2i = ASPECT_RATIO_VALUES[aspect]
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(roundi(BASE_HEIGHT * float(ratio.x) / ratio.y), BASE_HEIGHT)


static func _apply_window_mode(root: Window, window_mode: WindowMode, resolution: Vector2i) -> void:
	# Rodando sem janela de verdade (testes headless) não há o que aplicar.
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		WindowMode.FULLSCREEN:
			root.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		WindowMode.BORDERLESS:
			root.mode = Window.MODE_FULLSCREEN
		WindowMode.WINDOWED:
			root.mode = Window.MODE_WINDOWED
			root.borderless = false
			# O tamanho é aplicado no frame seguinte: logo depois de sair da tela cheia o SO ainda
			# está restaurando a janela e sobrescreveria um tamanho aplicado agora.
			_resize_and_center.call_deferred(root, resolution)


static func _resize_and_center(root: Window, resolution: Vector2i) -> void:
	if root.mode != Window.MODE_WINDOWED:
		return
	root.size = resolution
	var screen: int = root.current_screen
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	# Se a janela for maior que a área útil (ex.: 1920x1080 num monitor 1080p com barra de tarefas),
	# encosta no canto em vez de deixar a barra de título fora da tela.
	root.position = usable.position + ((usable.size - resolution) / 2).max(Vector2i.ZERO)


static func _get_screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(7680, 4320) # sem monitor: não filtra nada
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
