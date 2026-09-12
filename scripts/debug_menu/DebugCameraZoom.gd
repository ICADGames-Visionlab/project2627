# DebugCameraZoom.gd — Ajusta o zoom da câmera em runtime pelo menu de debug, com um botão para
# voltar ao valor que a cena trouxe.
#
# Serve para conferir enquadramento, alcance de visão e leitura do cenário sem recarregar a cena
# nem mexer no Inspector: afastar mostra o mapa inteiro (ótimo junto do overlay do Pathfinder),
# aproximar mostra o pixel art de perto.
#
# O DETALHE QUE NÃO É ÓBVIO: escrever em Camera2D.zoom não adianta neste projeto. O
# PhantomCameraHost copia o zoom da PhantomCamera ativa para a Camera2D a cada frame (ver
# phantom_camera_host.gd), então qualquer valor posto direto na Camera2D é sobrescrito no frame
# seguinte. Por isso o alvo aqui é a PhantomCamera ATIVA quando ela existe, e só cai na Camera2D
# crua quando a cena não usa o addon.
#
# Zoom é Vector2 na engine, mas aqui é tratado como um número só: zoom não uniforme distorce a
# imagem, e não é isso que se quer conferir. Valores maiores aproximam.
#
# Vive como nó filho do Autoload DebugMenu e registra a própria seção, então não existe em build
# de release.
class_name DebugCameraZoom
extends Node

const SECTION: StringName = &"Câmera"

const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 5.0
const ZOOM_STEP: float = 0.05

# Zoom "de fábrica" da câmera ativa e de qual câmera ele foi lido. Guardar a origem é o que faz
# "Restaurar zoom padrão" continuar certo depois de uma troca de cena: a cena nova traz outra
# PhantomCamera, com outro zoom, e o padrão antigo não vale mais.
var _default_zoom: float = 1.0
var _default_source: int = 0


func _ready() -> void:
	# [DEBUG] Seção "Câmera": zoom em runtime (ver docs/debug_menu.md).
	DebugMenu.register_value(SECTION, "Zoom", _on_zoom_changed,
		DebugParam.float_value("zoom", _default_zoom, MIN_ZOOM, MAX_ZOOM, ZOOM_STEP), _get_zoom)
	DebugMenu.register_action(SECTION, "Restaurar zoom padrão", _restore_default)


# Aplica o zoom digitado no menu (ou no console, via `camera.zoom`).
func _on_zoom_changed(zoom: float) -> void:
	var camera: Node = _get_target_camera()
	if camera == null:
		push_warning("[DebugCamera] - Nenhuma câmera ativa para aplicar zoom")
		return

	_remember_default(camera)
	var value: float = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(value, value)
	print("[DebugCamera] - Zoom ajustado para %.2f em \"%s\"" % [value, camera.name])


# Volta ao zoom que a cena trouxe.
func _restore_default() -> void:
	var camera: Node = _get_target_camera()
	if camera == null:
		push_warning("[DebugCamera] - Nenhuma câmera ativa para restaurar")
		return

	_remember_default(camera)
	camera.zoom = Vector2(_default_zoom, _default_zoom)
	print("[DebugCamera] - Zoom restaurado para o padrão da cena (%.2f)" % _default_zoom)


# Lido pelo menu ao remontar a UI: sem isto o campo mostraria a cópia guardada no registro e
# desencontraria depois de um "Restaurar zoom padrão" ou de uma troca de cena.
func _get_zoom() -> float:
	var camera: Node = _get_target_camera()
	if camera == null:
		return _default_zoom

	_remember_default(camera)
	return (camera.zoom as Vector2).x


# Guarda o zoom de fábrica da câmera, mas só na primeira vez que vê cada uma. Sem essa checagem,
# recapturar a cada chamada faria "Restaurar" voltar para o último valor digitado em vez do valor
# original — ou seja, não restauraria nada.
func _remember_default(camera: Node) -> void:
	var id: int = camera.get_instance_id()
	if id == _default_source:
		return

	_default_source = id
	_default_zoom = (camera.zoom as Vector2).x


# A câmera que de fato manda no zoom (ver o comentário no topo do arquivo).
func _get_target_camera() -> Node:
	for host: PhantomCameraHost in PhantomCameraManager.phantom_camera_hosts:
		var pcam: Node = host.get_active_pcam()
		if pcam is PhantomCamera2D:
			return pcam

	return get_viewport().get_camera_2d()
