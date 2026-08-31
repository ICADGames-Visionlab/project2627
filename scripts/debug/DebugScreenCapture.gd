# DebugScreenCapture.gd — Captura de tela rápida: um clique (ou F6) salva um PNG do que está na
# tela em user://debug_screenshots/, com data e hora no nome.
#
# Existe porque é o gesto mais repetido em revisão de PR e em report de bug, e a alternativa é
# depender da ferramenta de captura do sistema operacional — que pega a janela inteira, com barra
# de título, e joga o arquivo em qualquer lugar.
#
# Vive como nó filho do Autoload DebugMenu e registra a própria seção; não existe em release.
class_name DebugScreenCapture
extends Node

const SECTION: StringName = &"Captura"
const DIRECTORY: String = "user://debug_screenshots"
const FILE_PREFIX: String = "screenshot"
# Teto de tentativas de sufixo quando várias capturas caem no mesmo segundo (F6 repetido).
const MAX_NAME_ATTEMPTS: int = 100

# Se os painéis de debug somem da imagem. Ligado por padrão: a captura serve para mostrar o JOGO
# num PR ou num report de bug, e o menu aberto por cima é ruído.
var _hide_overlays: bool = true


func _ready() -> void:
	# [DEBUG] Seção "Captura": captura de tela do jogo (ver docs/debug_menu.md).
	DebugMenu.register_action(SECTION, "Capturar tela (F6)", capture)
	DebugMenu.register_toggle(SECTION, "Ocultar overlays de debug", _on_hide_overlays_toggled, _hide_overlays)
	DebugMenu.register_action(SECTION, "Abrir pasta das capturas", _open_directory)


# Salva um PNG do quadro atual. Público porque o F6 (roteado pelo DebugMenu) chama isto direto,
# sem passar pelo menu.
func capture() -> void:
	var hidden: Array[CanvasLayer] = []
	if _hide_overlays:
		hidden = _hide_debug_overlays()
	# Duas esperas, e não uma: esconder um painel só vale a partir do próximo quadro desenhado, e a
	# textura do viewport só tem o quadro pronto depois que o desenho termina.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	for overlay: CanvasLayer in hidden:
		overlay.visible = true
	_save_image(image)


# Esconde os overlays de debug visíveis e devolve exatamente os que escondeu. Devolver a lista (em
# vez de reacender tudo depois) é o que evita abrir painéis que estavam fechados antes da captura.
#
# A varredura é por grupo, e não por referência: assim a captura não precisa conhecer nenhum
# overlay, e um painel novo entra na regra com a linha de add_to_group() do próprio _ready().
func _hide_debug_overlays() -> Array[CanvasLayer]:
	var hidden: Array[CanvasLayer] = []
	for node: Node in get_tree().get_nodes_in_group(DebugMenu.OVERLAY_GROUP):
		var overlay: CanvasLayer = node as CanvasLayer
		if overlay != null and overlay.visible:
			overlay.visible = false
			hidden.append(overlay)
	return hidden


# Escreve a imagem em disco e loga o caminho absoluto — é o caminho que se cola no PR, então
# imprimir o "user://" cru só daria trabalho a quem for procurar o arquivo.
func _save_image(image: Image) -> void:
	# Sem imagem não há o que salvar: acontece quando não existe renderizador de verdade (uma
	# execução headless, por exemplo), e é melhor dizer isso do que estourar no save_png().
	if image == null:
		push_error("[DebugCapture] - ERRO: o viewport não devolveu imagem; captura cancelada")
		return
	if not _ensure_directory():
		return
	var path: String = _next_file_path()
	if path.is_empty():
		push_error("[DebugCapture] - ERRO: nenhum nome livre para a captura em %s" % DIRECTORY)
		return
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("[DebugCapture] - ERRO: falha ao salvar a captura em %s (código %d)" % [path, error])
		return
	print("[DebugCapture] - Captura salva em %s (%dx%d)" % [
		ProjectSettings.globalize_path(path), image.get_width(), image.get_height()
	])


# Monta o nome do arquivo com data e hora. Se já existir um do mesmo segundo, acrescenta um número:
# duas capturas seguidas nunca podem sobrescrever uma à outra.
func _next_file_path() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = "%04d-%02d-%02d_%02d-%02d-%02d" % [
		now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]
	]
	var base: String = "%s/%s_%s" % [DIRECTORY, FILE_PREFIX, stamp]
	if not FileAccess.file_exists("%s.png" % base):
		return "%s.png" % base
	for attempt: int in range(2, MAX_NAME_ATTEMPTS):
		var candidate: String = "%s_%d.png" % [base, attempt]
		if not FileAccess.file_exists(candidate):
			return candidate
	return ""


# Garante que a pasta das capturas existe antes de escrever ou de abrir o explorador de arquivos.
func _ensure_directory() -> bool:
	if DirAccess.dir_exists_absolute(DIRECTORY):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK:
		push_error("[DebugCapture] - ERRO: não foi possível criar %s (código %d)" % [DIRECTORY, error])
		return false
	return true


# Abre a pasta das capturas no explorador de arquivos do sistema. É o que fecha o ciclo "capturei,
# agora quero arrastar o arquivo para o PR" sem ninguém precisar caçar onde fica o user://.
func _open_directory() -> void:
	if not _ensure_directory():
		return
	var absolute: String = ProjectSettings.globalize_path(DIRECTORY)
	OS.shell_open(absolute)
	print("[DebugCapture] - Pasta das capturas aberta: %s" % absolute)


# Liga/desliga o sumiço dos painéis de debug na captura. Desligar é útil quando o print É do
# próprio menu (documentação da ferramenta, por exemplo).
func _on_hide_overlays_toggled(enabled: bool) -> void:
	_hide_overlays = enabled
	print("[DebugCapture] - Overlays de debug %s na captura" % ("ocultos" if enabled else "visíveis"))
