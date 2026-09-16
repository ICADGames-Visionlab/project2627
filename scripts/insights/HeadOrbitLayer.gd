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
# E um custo da mesma decisão: o orbe nasce longe da coisa de que fala. Com o orbe em destaque
# (mouse em cima ou foco do controle), a órbita desenha uma linha tracejada até a fonte — com duas
# fontes no alcance, é o que diz se a cabeça vai falar da parede ou da calha.
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

@export_group("Ligação com a fonte")
@export var link_width: float = 2.0
@export var link_dash: float = 10.0
@export var link_alpha: float = 0.7
# Raio do anel desenhado no ponto de que a cabeça fala.
@export var link_target_radius: float = 14.0

var _markers: Dictionary = {}    # StringName(head_id) -> InsightMarker
var _offers: Dictionary = {}     # StringName(head_id) -> InsightOffer
# Cabeça cujo orbe está em destaque agora, ou vazio. Só uma por vez: é para onde o mouse (ou o foco)
# está apontando.
var _highlighted_head: StringName = &""


func _ready() -> void:
	InsightDirector.set_orbit_layer(self)
	set_process(false)
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": o teto de orbes é o número que mais vale experimentar em jogo.
		DebugMenu.register_value(DEBUG_SECTION, "Teto de orbes de cabeça", _debug_set_max_orbs,
			DebugParam.int_value("teto", max_visible_orbs, 1, 8), _debug_get_max_orbs)


func _exit_tree() -> void:
	InsightDirector.clear_orbit_layer(self)


func _process(_delta: float) -> void:
	# O jogador anda e a fonte fica: a linha precisa ser redesenhada a cada quadro enquanto existir.
	queue_redraw()


func _draw() -> void:
	var offer: InsightOffer = _offers.get(_highlighted_head, null) as InsightOffer
	var marker: InsightMarker = _markers.get(_highlighted_head, null) as InsightMarker
	if offer == null or marker == null or not is_instance_valid(offer.source):
		return
	var source: InsightSource = offer.source as InsightSource
	if source == null:
		return
	var color: Color = Color(HeadRegistry.get_color(_highlighted_head), link_alpha)
	var target: Vector2 = to_local(source.get_anchor_global_position())
	# Desenhado pela órbita, e não pelo orbe, para ficar por baixo de todos os orbes: o pai desenha
	# antes dos filhos.
	draw_dashed_line(marker.position, target, color, link_width, link_dash, true, true)
	draw_arc(target, link_target_radius, 0.0, TAU, 24, color, link_width, true)


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
		marker.set_hover_text_key(HeadRegistry.get_display_name_key(offer.head_id))
		marker.set_read(not offer.is_new)
	queue_redraw()


# Orbes de cabeça visíveis agora, da esquerda para a direita na tela. É a ordem em que o foco do
# controle percorre a órbita: seguir a posição na tela é o que a mão espera ao apertar "próximo".
func get_markers() -> Array[InsightMarker]:
	var result: Array[InsightMarker] = []
	for head_id: StringName in _markers:
		result.append(_markers[head_id])
	result.sort_custom(_compare_marker_positions)
	return result


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


# Instancia o orbe de uma cabeça. Os signals carregam o head_id por bind() porque a oferta muda a
# cada reavaliação, e reconectar a cada troca seria uma fonte de conexão duplicada.
func _create_marker(head_id: StringName) -> InsightMarker:
	var scene: PackedScene = load(MARKER_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Insights] - ERRO: cena do marcador não encontrada em %s" % MARKER_SCENE_PATH)
		return null
	var marker: InsightMarker = scene.instantiate() as InsightMarker
	add_child(marker)
	marker.clicked.connect(_on_marker_clicked.bind(head_id))
	marker.highlight_changed.connect(_on_marker_highlight_changed.bind(head_id))
	marker.rekindled.connect(_on_marker_rekindled.bind(head_id))
	_markers[head_id] = marker
	return marker


# Tira da órbita o orbe de uma cabeça que não tem mais nada a dizer aqui. Orbe liberado não emite
# highlight_changed, então a linha até a fonte é desligada aqui mesmo.
func _remove_marker(head_id: StringName) -> void:
	var marker: InsightMarker = _markers.get(head_id, null) as InsightMarker
	if marker != null:
		marker.queue_free()
	_markers.erase(head_id)
	if _highlighted_head == head_id:
		_set_highlighted_head(&"")


# Troca a cabeça em destaque e liga o redesenho por quadro só enquanto houver linha para desenhar.
func _set_highlighted_head(head_id: StringName) -> void:
	_highlighted_head = head_id
	set_process(head_id != &"")
	queue_redraw()


# Leva o clique ao Director com a oferta que este orbe representa agora.
func _on_marker_clicked(head_id: StringName) -> void:
	var offer: InsightOffer = _offers.get(head_id, null) as InsightOffer
	if offer == null:
		return
	InsightDirector.reveal(offer.insight, offer.source as InsightSource)


# Liga ou desliga a linha até a fonte conforme o orbe entra ou sai de destaque. Só apaga a linha se
# quem saiu de destaque é a cabeça que estava ligada: com dois orbes, entrar no segundo antes de sair
# do primeiro não pode apagar a linha nova.
func _on_marker_highlight_changed(is_highlighted: bool, head_id: StringName) -> void:
	if is_highlighted:
		_set_highlighted_head(head_id)
	elif _highlighted_head == head_id:
		_set_highlighted_head(&"")


# Registra no log a cabeça que voltou a ter novidade.
func _on_marker_rekindled(head_id: StringName) -> void:
	var offer: InsightOffer = _offers.get(head_id, null) as InsightOffer
	var insight_id: String = String(offer.insight.id) if offer != null else "?"
	print("[Insights] - Orbe da cabeça \"%s\" voltou a ter novidade (%s)" % [head_id, insight_id])


# Ordena dois orbes da esquerda para a direita.
func _compare_marker_positions(left: InsightMarker, right: InsightMarker) -> bool:
	return left.position.x < right.position.x


# Setter do teto de orbes. Nunca abaixo de 1 (zero esconderia todas as cabeças sem aviso), e pede a
# reavaliação para a mudança feita no Inspector ou no menu de debug aparecer na hora.
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
