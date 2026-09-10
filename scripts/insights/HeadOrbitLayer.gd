# HeadOrbitLayer.gd — A órbita de cabeças do jogador: onde nascem os orbes do canal de personagem.
#
# Vive como filho do Player, então os orbes acompanham o personagem. O gatilho continua sendo a
# fonte no mundo — é ela que sabe que há algo a dizer sobre aquele ponto —, mas a âncora é o
# jogador: posição diz o canal (no objeto ou aqui), cor diz quem está falando.
#
# Duas regras que a decisão do orbe flutuante cobra, e que economizam retrabalho:
#   - Slot derivado da cabeça, não da ordem de chegada. Uma cabeça calar não faz as outras pularem
#     de lugar; sem isso o jogador clica no orbe errado.
#   - Teto de orbes simultâneos. Acima dele o jogador vira pinheiro de natal e para de distinguir as
#     cores — que é justamente o que a cor por cabeça veio criar.
#
# O guia completo está em docs/insights.md.
class_name HeadOrbitLayer
extends Node2D

const DEBUG_SECTION: StringName = &"Insights"
const MARKER_SCENE_PATH: String = "res://scenes/insights/InsightMarker.tscn"

@export_group("Órbita")
# Quantos orbes de cabeça podem aparecer ao mesmo tempo.
@export var max_visible_orbs: int = 3:
	set = _set_max_visible_orbs
@export var orbit_radius: float = 110.0
# Ângulo do centro do arco, em graus, com -90 apontando para cima do jogador.
@export var orbit_center_degrees: float = -90.0
# Abertura do arco em que os slots são distribuídos.
@export var orbit_arc_degrees: float = 120.0

var _markers: Dictionary = {}    # StringName(head_id) -> InsightMarker
var _offers: Dictionary = {}     # StringName(head_id) -> InsightOffer


func _ready() -> void:
	InsightDirector.set_orbit_layer(self)
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": o teto de orbes é o número que mais vale experimentar em jogo.
		DebugMenu.register_value(DEBUG_SECTION, "Teto de orbes de cabeça", _debug_set_max_orbs,
			DebugParam.int_value("teto", max_visible_orbs, 1, 8), _debug_get_max_orbs)


func _exit_tree() -> void:
	InsightDirector.clear_orbit_layer(self)


# Recebe as ofertas já escolhidas e ordenadas pelo InsightDirector e arruma os orbes em volta do
# jogador. A órbita não decide nada sobre conteúdo: só desenha o que recebeu, no slot de cada cabeça.
func show_offers(offers: Array[InsightOffer]) -> void:
	var visible_offers: Array[InsightOffer] = offers.slice(0, max_visible_orbs)
	var slots: Dictionary = _assign_slots(visible_offers)

	_offers.clear()
	for offer: InsightOffer in visible_offers:
		_offers[offer.head_id] = offer

	for head_id: StringName in _markers.keys():
		if not _offers.has(head_id):
			_remove_marker(head_id)

	for offer: InsightOffer in visible_offers:
		var marker: InsightMarker = _markers.get(offer.head_id, null) as InsightMarker
		if marker == null:
			marker = _create_marker(offer.head_id)
		marker.position = _slot_position(int(slots[offer.head_id]))
		marker.configure(HeadRegistry.get_color(offer.head_id), HeadRegistry.get_glyph(offer.head_id))
		marker.set_read(not offer.is_new)
		# Orbe de cabeça orbita o jogador, então está sempre ao alcance — o alcance já foi decidido
		# lá atrás, quando a fonte disse que o jogador estava perto o bastante para ela falar.
		marker.set_clickable(true)


# Decide em que slot cada cabeça fica. O slot preferido vem da posição canônica da cabeça no elenco
# (ver HeadRegistry.get_slot_index): é o que mantém a mesma cabeça sempre no mesmo lugar. Colisão
# entre duas cabeças que caem no mesmo slot é resolvida andando para o próximo livre.
func _assign_slots(offers: Array[InsightOffer]) -> Dictionary:
	var slot_count: int = maxi(max_visible_orbs, 1)
	var taken: Dictionary = {}
	var result: Dictionary = {}
	for offer: InsightOffer in offers:
		var preferred: int = HeadRegistry.get_slot_index(offer.head_id)
		if preferred < 0:
			preferred = 0
		var slot: int = preferred % slot_count
		var attempts: int = 0
		while taken.has(slot) and attempts < slot_count:
			slot = (slot + 1) % slot_count
			attempts += 1
		taken[slot] = true
		result[offer.head_id] = slot
	return result


# Posição de um slot no arco em volta do jogador. Com um slot só, ele fica no centro do arco; com
# vários, eles se distribuem igualmente entre as pontas.
func _slot_position(slot: int) -> Vector2:
	var slot_count: int = maxi(max_visible_orbs, 1)
	var angle_degrees: float = orbit_center_degrees
	if slot_count > 1:
		var step: float = orbit_arc_degrees / float(slot_count - 1)
		angle_degrees = orbit_center_degrees - orbit_arc_degrees * 0.5 + step * float(slot)
	return Vector2.RIGHT.rotated(deg_to_rad(angle_degrees)) * orbit_radius


# Instancia o orbe de uma cabeça. O clique carrega o head_id por bind() porque a oferta muda a cada
# reavaliação, e reconectar o signal a cada troca seria uma fonte de conexão duplicada.
func _create_marker(head_id: StringName) -> InsightMarker:
	var scene: PackedScene = load(MARKER_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Insights] - ERRO: cena do marcador não encontrada em %s" % MARKER_SCENE_PATH)
		return null
	var marker: InsightMarker = scene.instantiate() as InsightMarker
	add_child(marker)
	marker.clicked.connect(_on_marker_clicked.bind(head_id))
	_markers[head_id] = marker
	return marker


# Tira da órbita o orbe de uma cabeça que não tem mais nada a dizer aqui.
func _remove_marker(head_id: StringName) -> void:
	var marker: InsightMarker = _markers.get(head_id, null) as InsightMarker
	if marker != null:
		marker.queue_free()
	_markers.erase(head_id)


# Leva o clique ao Director com a oferta que este orbe representa agora.
func _on_marker_clicked(head_id: StringName) -> void:
	var offer: InsightOffer = _offers.get(head_id, null) as InsightOffer
	if offer == null:
		return
	InsightDirector.reveal(offer.insight, offer.source as InsightSource)


func _set_max_visible_orbs(value: int) -> void:
	max_visible_orbs = maxi(value, 1)
	if is_node_ready():
		InsightDirector.request_refresh()


# [DEBUG] Muda o teto de orbes em jogo, para calibrar o número olhando a tela em vez de discutindo.
func _debug_set_max_orbs(value: int) -> void:
	max_visible_orbs = value
	print("[Insights] - Teto de orbes de cabeça agora é %d" % max_visible_orbs)


# [DEBUG] Devolve o teto atual para o menu remontar com o valor de verdade.
func _debug_get_max_orbs() -> int:
	return max_visible_orbs
