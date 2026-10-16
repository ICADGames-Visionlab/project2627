## Interactable - um objeto do mundo que o jogador pode examinar: um bilhete no chão, uma gaveta,
## uma mancha na parede. À primeira vista ele é só cenário; segurar o botão direito do mouse (ou Alt)
## faz brilhar todos os que estão na tela, e clicar num deles tem UMA de três consequências:
##
##   INSIGHT   o jogador recebe um insight (caixa no próprio objeto, ou fala de uma cabeça)
##   DIALOGUE  abre uma conversa da pasta dialogue/ (narração, o jogador pensando alto)
##   EVIDENCE  o objeto vai para o inventário como evidência e some do mundo
##
## COMO USAR: arraste scenes/interactables/Interactable.tscn para dentro do YSort da cena, posicione e
## escale como qualquer prop, escolha a textura e a consequência no Inspector. O triângulo amarelo na
## árvore de cena diz o que falta preencher.
##
## O objeto não lê teclado nem mouse: quem decide o que está no campo de visão, o que está sob o
## cursor e quando brilhar é o InteractableInteractor, filho do Player. Aqui mora só o que é do
## objeto: a aparência do contorno e o que acontece quando ele é acionado.
##
## NO SAVE: uma evidência já coletada não volta ao recarregar. Quem lembra disso é a GameSession
## (seção "pickups"), pelo caminho do nó na cena; o objeto em si não sabe de save nenhum. Renomear ou
## mover no editor um Interactable de evidência faz ele reaparecer para quem já o tinha coletado.
@tool
class_name Interactable
extends Node2D

## Espaço para enums

# O que acontece quando o jogador interage. Um objeto tem UMA consequência, e não uma lista: o
# jogador aprende o que o clique faz olhando o objeto, e um bilhete que às vezes vira fala e às
# vezes vira evidência seria imprevisível. Quem precisar dos dois efeitos encadeia pela flag
# (grants_flag), que o diálogo e os insights já sabem ler.
enum Outcome { INSIGHT, DIALOGUE, EVIDENCE }

## Espaço para constantes

# Grupo em que todo objeto interagível entra. É assim que o InteractableInteractor encontra os
# objetos da cena sem ninguém manter lista nenhuma.
const GROUP: StringName = &"interactables"

# Cena da fonte de insight criada sob demanda para a caixa de texto ter onde nascer (ver
# _reveal_insight). Carregada com load() na hora, como o InsightSource faz com o marcador.
const INSIGHT_SOURCE_SCENE_PATH: String = "res://scenes/insights/InsightSource.tscn"

# Cor do contorno quando o mouse está em cima: o mesmo branco do hover do NPC (NPC.tscn), para
# "isto é clicável" ter uma cara só no jogo inteiro.
const HOVER_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

# Folga transparente, em texels, posta em volta da textura em jogo (ver _padded_texture). É o teto de
# outline_width, para qualquer espessura de contorno caber.
const OUTLINE_PADDING: int = 8

## Espaço para variáveis exportadas

@export_group("Aparência")
# O desenho do objeto. Pode ficar vazio num objeto de evidência: aí ele usa o ícone do ItemData,
# que é o mesmo desenho que o jogador vai ver depois no inventário.
@export var texture: Texture2D:
	set(value):
		texture = value
		_apply_texture()
		_refresh_editor_state()

# Espessura do contorno, em texels da textura (ver resources/shaders/sprite_outline.gdshader). A
# espessura na tela é esta vezes a escala do nó, então um objeto escalado 6x com 1 texel já tem um
# contorno bem visível.
@export_range(0.0, 8.0, 0.5) var outline_width: float = 1.0

@export_group("Consequência")
@export var outcome: Outcome = Outcome.INSIGHT:
	set(value):
		outcome = value
		# Remonta o Inspector: cada consequência mostra só o campo que ela usa (_validate_property).
		notify_property_list_changed()
		_apply_texture()
		_refresh_editor_state()

# INSIGHT: o insight entregue. Passa pelo InsightDirector como qualquer outro, então marca o diário,
# concede a flag do próprio insight e toca o som da primeira leitura sem nada disso ser refeito aqui.
@export var insight: InsightData:
	set(value):
		insight = value
		_refresh_editor_state()

# DIALOGUE: id da conversa, o nome do arquivo em dialogue/ sem o .dlg.
@export var conversation_id: StringName = &"":
	set(value):
		conversation_id = value
		_refresh_editor_state()

# EVIDENCE: o item que vai para o inventário.
@export var evidence: ItemData:
	set(value):
		evidence = value
		_apply_texture()
		_refresh_editor_state()

# EVIDENCE: quantas unidades. Quase sempre 1 (evidência é única), mas um maço de bilhetes pode dar 3.
@export_range(1, 99, 1) var evidence_amount: int = 1

# Flag de mundo concedida ao interagir, em qualquer consequência. É a costura com o resto do jogo:
# uma opção de diálogo "Perguntar do bilhete" ou um insight que só abre depois de achar a pista
# leem esta flag, sem este script precisar conhecer nenhum dos dois.
@export var grants_flag: StringName = &""

@export_group("Abordagem")
# Distância da BORDA do desenho a partir da qual o jogador precisa andar até o objeto antes da
# consequência. Examinar é um gesto de perto: pegar um bilhete do outro lado da rua seria estranho.
# Medida da borda, e não do centro, para funcionar igual num bilhete no chão e numa caixa de
# correio alta: contando do centro, o jogador parava EM CIMA de um prop grande.
@export var approach_distance: float = 40.0

## Espaço para variáveis

# O objeto que está no meio de uma interação agora (andando até ele, por exemplo), em qualquer
# instância. Estático pelo mesmo motivo do NPCInteraction: dois cliques seguidos em objetos
# diferentes disputariam o mesmo Player. Guarda a instância, e não um bool, para o travamento se
# desfazer sozinho se o objeto sair da árvore no meio da caminhada (troca de cena): um bool ficaria
# preso em true e nenhum objeto do jogo voltaria a responder.
static var _active: Interactable = null

# Texturas já acolchoadas, por textura de origem (ver _padded_texture).
static var _padded_cache: Dictionary = {}

# Folga que a textura atual do sprite tem, em texels: OUTLINE_PADDING em jogo, zero no editor. As
# contas de área (clique, campo de visão, onde a caixa nasce) descontam isto para medir o DESENHO, e
# não a folga: senão um prop escalado 5x ganharia 40 px de área de clique vazia em volta.
var _padding: int = 0

var _is_hovered: bool = false
var _highlight_color: Color = Color.TRANSPARENT
var _brighten: float = 0.0
# Consequência bem configurada, calculada uma vez no _ready (a checagem de conversa lê o disco, e
# o hover pergunta isto a cada quadro).
var _is_configured: bool = false
# Âncora da caixa de texto do insight de ambiente, criada no primeiro uso (ver _reveal_insight).
var _insight_anchor: InsightSource = null

## Espaço para variáveis onready

@onready var _sprite: Sprite2D = $Sprite2D

## Espaço para funções nativas

func _ready() -> void:
	_apply_texture()
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	add_to_group(GROUP)
	_is_configured = _check_configured()
	if not _is_configured:
		push_warning("[Interactables] - \"%s\" sem consequência configurada; não vai brilhar nem responder ao clique" % name)
	_apply_outline()


func _exit_tree() -> void:
	if _active == self:
		_active = null


# Esconde do Inspector os campos das outras consequências. Mesmo padrão do head_id em InsightData:
# um formulário com campos que não fazem nada convida a preencher o campo errado.
func _validate_property(property: Dictionary) -> void:
	var name_to_outcome: Dictionary = {
		"insight": Outcome.INSIGHT,
		"conversation_id": Outcome.DIALOGUE,
		"evidence": Outcome.EVIDENCE,
		"evidence_amount": Outcome.EVIDENCE,
	}
	if name_to_outcome.has(property.name) and name_to_outcome[property.name] != outcome:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if _resolved_texture() == null:
		warnings.append("Sem textura: o objeto fica invisível (e sem textura não há o que clicar).")
	match outcome:
		Outcome.INSIGHT:
			if insight == null:
				warnings.append("Consequência Insight sem InsightData.")
		Outcome.DIALOGUE:
			if conversation_id == &"":
				warnings.append("Consequência Diálogo sem conversation_id.")
			elif not FileAccess.file_exists(DialogueCatalog.get_script_path(conversation_id)):
				warnings.append("Conversa \"%s\" não existe em %s." % [conversation_id, DialogueCatalog.get_script_path(conversation_id)])
		Outcome.EVIDENCE:
			if evidence == null:
				warnings.append("Consequência Evidência sem ItemData.")
	return warnings

## Espaço para funções personalizadas

# --- Consultas do InteractableInteractor ---

# Diz se o objeto pode brilhar e ser acionado agora: bem configurado, ainda no mundo e com algo
# desenhado.
func is_available() -> bool:
	return _is_configured and not is_queued_for_deletion() and _sprite.texture != null and is_visible_in_tree()


# O retângulo do desenho em coordenadas de tela (as mesmas de get_viewport().get_visible_rect() e da
# posição do mouse). É por ele que o Interactor decide "está no campo de visão" e "está sob o
# cursor". Retângulo, e não a silhueta: um objeto pequeno ou fino (um bilhete, um poste) seria
# difícil de acertar pixel a pixel, e errar o clique por dois pixels de transparência frustra mais
# do que acertar um canto vazio.
func get_screen_rect() -> Rect2:
	return _sprite.get_global_transform_with_canvas() * _drawing_rect()


# --- Aparência ---

# Contorno branco de hover (o mesmo do NPC). Tem prioridade sobre o brilho: com vários objetos
# brilhando, é ele que diz qual deles o clique vai pegar.
func set_hovered(hovered: bool) -> void:
	if _is_hovered == hovered:
		return
	_is_hovered = hovered
	_apply_outline()


# Brilho do "mostrar interagíveis". color.a e brighten vêm já pulsando do Interactor: o pulso é um
# só para todos os objetos, senão cada um piscaria num compasso e a tela viraria um pisca-pisca.
func set_highlight(color: Color, brighten: float) -> void:
	_highlight_color = color
	_brighten = brighten
	_apply_outline()


func clear_highlight() -> void:
	set_highlight(Color.TRANSPARENT, 0.0)


# --- Interação ---

# Diz se algum objeto está no meio de uma interação (o jogador andando até ele).
static func is_any_interaction_running() -> bool:
	return _active != null and is_instance_valid(_active)


# Aciona o objeto: se o jogador está longe, anda até perto dele primeiro, e só então aplica a
# consequência. Chamado pelo InteractableInteractor ao clicar.
func interact(player: Player) -> void:
	if not is_available() or is_any_interaction_running():
		return
	_active = self
	print("[Interactables] - Interagindo com \"%s\" (%s)" % [name, Outcome.keys()[outcome]])

	if player != null and distance_from_drawing(player.global_position) > approach_distance:
		# Um destino antigo do clique para andar seria retomado assim que a aproximação terminasse,
		# e o jogador sairia andando para longe do objeto que acabou de examinar.
		player.cancel_click_destination()
		player.start_conversation_approach(_approach_point(player.global_position))
		await player.conversation_approach_arrived

	# A caminhada pode ter terminado depois de o objeto sair da árvore (troca de cena no meio).
	if _active == self:
		_active = null
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_run_outcome(player)


# Distância de um ponto do mundo até o retângulo do desenho (zero se o ponto está dentro dele).
# Público porque é a medida que decide "perto o bastante"; o teste de integração confere por ela.
func distance_from_drawing(point: Vector2) -> float:
	var rect: Rect2 = _world_rect()
	return point.distance_to(point.clamp(rect.position, rect.end))


# Onde o jogador para: no ponto da borda do desenho mais perto de onde ele vem, afastado metade de
# approach_distance. Metade, e não o limite exato, para a folga de chegada do Player (alguns pixels)
# não deixar o jogador ainda "longe" ao parar.
func _approach_point(from: Vector2) -> Vector2:
	var rect: Rect2 = _world_rect()
	var edge: Vector2 = from.clamp(rect.position, rect.end)
	var direction: Vector2 = from - edge
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return edge + direction.normalized() * approach_distance * 0.5


# Aplica a consequência. A flag é concedida ANTES: uma conversa aberta por este objeto pode ter
# opção condicionada a ela, e as condições do primeiro nó são avaliadas assim que a conversa abre.
# A evidência confere o inventário antes de tudo, para uma falha não conceder a flag de uma pista
# que o jogador não pegou.
func _run_outcome(player: Player) -> void:
	var inventory: Inventory = null
	if outcome == Outcome.EVIDENCE:
		if player != null:
			inventory = player.get_node_or_null(^"Inventory") as Inventory
		if inventory == null:
			push_warning("[Interactables] - \"%s\": jogador sem Inventory; evidência não coletada" % name)
			return

	if grants_flag != &"":
		InsightJournal.grant_flag(grants_flag)

	match outcome:
		Outcome.INSIGHT:
			_reveal_insight()
		Outcome.DIALOGUE:
			_start_dialogue()
		Outcome.EVIDENCE:
			_collect_evidence(inventory)


# Entrega o insight pelo InsightDirector, o único caminho para um insight chegar à tela (diário,
# flag do insight e som vêm junto). O Director precisa de uma InsightSource para abrir a caixa de
# ambiente, porque é a fonte que sabe onde a caixa fica no mundo. Uma fonte FIXA na cena do objeto
# desenharia o orbe verde de insight em cima dele o tempo todo e entregaria o objeto que era para
# estar escondido; por isso a fonte é criada aqui, na primeira leitura, com a lista de insights
# VAZIA: o Director não tem o que escolher nela, então ela nunca desenha orbe, e serve só de
# âncora para a caixa.
func _reveal_insight() -> void:
	if _insight_anchor == null or not is_instance_valid(_insight_anchor):
		var scene: PackedScene = load(INSIGHT_SOURCE_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[Interactables] - ERRO: cena da fonte de insight não encontrada em %s" % INSIGHT_SOURCE_SCENE_PATH)
			return
		_insight_anchor = scene.instantiate() as InsightSource
		_insight_anchor.name = &"InsightAnchor"
		# top_level: a caixa não herda a escala do objeto (um prop escalado 6x teria uma caixa 6x
		# maior) e é desenhada por cima do Y-sort, sem ficar escondida atrás de um prédio mais abaixo
		# na tela.
		_insight_anchor.top_level = true
		_insight_anchor.marker_offset = Vector2.ZERO
		add_child(_insight_anchor)
	_insight_anchor.global_position = _top_center()
	InsightDirector.reveal(insight, _insight_anchor)


# Abre a conversa. initiator vazio, como no comando de debug: não há NPC puxando a conversa, então
# ninguém é segurado nem virado para o jogador; o roteiro fala pela narração ou pelo "player".
func _start_dialogue() -> void:
	EventBus.conversation_requested.emit(conversation_id, &"")


# Põe a evidência no inventário e tira o objeto do mundo. O inventário emite item_added, que a
# InventoryUI já escuta.
func _collect_evidence(inventory: Inventory) -> void:
	inventory.add_item(evidence, evidence_amount)
	print("[Interactables] - \"%s\" coletado como evidência \"%s\" (x%d)" % [name, evidence.id, evidence_amount])
	queue_free()


# --- Internos ---

# Liga o contorno do shader de destaque (o mesmo do hover do NPC) e o clarão do brilho. Hover ganha
# do brilho; sem nenhum dos dois, espessura zero, que é o shader desligado.
func _apply_outline() -> void:
	if not is_node_ready() or Engine.is_editor_hint():
		return
	var material: ShaderMaterial = _sprite.material as ShaderMaterial
	if material == null:
		return
	var color: Color = Color.TRANSPARENT
	if _is_hovered:
		color = HOVER_COLOR
	elif _highlight_color.a > 0.0:
		color = _highlight_color
	material.set_shader_parameter(&"outline_color", color)
	material.set_shader_parameter(&"outline_width", outline_width if color.a > 0.0 else 0.0)
	# self_modulate acima de 1 clareia o desenho: é o "brilhar" além do contorno. No sprite, e não no
	# nó, para não clarear a caixa de texto do insight, que é filha deste nó.
	var brighten: float = _brighten if not _is_hovered else 0.0
	_sprite.self_modulate = Color(1.0 + brighten, 1.0 + brighten, 1.0 + brighten, 1.0)


# Põe no sprite a textura escolhida, ou o ícone da evidência quando ela ficou vazia. Também no
# editor, para o objeto aparecer na cena enquanto é montado; o acolchoamento (ver _padded_texture)
# só em jogo, onde o contorno existe.
func _apply_texture() -> void:
	if not is_node_ready():
		return
	var resolved: Texture2D = _resolved_texture()
	_padding = 0
	if resolved != null and not Engine.is_editor_hint():
		var padded: Texture2D = _padded_texture(resolved)
		if padded != resolved:
			_padding = OUTLINE_PADDING
		resolved = padded
	_sprite.texture = resolved


# A textura com uma borda transparente em volta. O shader de contorno só pinta DENTRO da textura (ele
# acende o texel transparente vizinho de um opaco), e os props do pacote isométrico são recortados
# rente ao desenho: sem folga, o contorno sairia cortado justamente nas bordas de fora. A folga é a
# espessura máxima do contorno (8 texels, o teto de outline_width), então qualquer espessura cabe.
# O Sprite2D é centralizado, então a borda cresce igual para os dois lados e o desenho não sai do
# lugar. Guardado por textura (_padded_cache), para dez objetos com o mesmo sprite gerarem uma imagem
# só.
func _padded_texture(source: Texture2D) -> Texture2D:
	if _padded_cache.has(source):
		return _padded_cache[source] as Texture2D
	var image: Image = source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var padded: Image = Image.create_empty(image.get_width() + OUTLINE_PADDING * 2,
		image.get_height() + OUTLINE_PADDING * 2, false, Image.FORMAT_RGBA8)
	padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(OUTLINE_PADDING, OUTLINE_PADDING))
	var result: ImageTexture = ImageTexture.create_from_image(padded)
	_padded_cache[source] = result
	return result


func _resolved_texture() -> Texture2D:
	if texture != null:
		return texture
	if outcome == Outcome.EVIDENCE and evidence != null:
		return evidence.icon
	return null


# Diz se a consequência escolhida tem o que precisa. A conversa é conferida no disco: um
# conversation_id com erro de digitação abriria a tela de diálogo vazia.
func _check_configured() -> bool:
	match outcome:
		Outcome.INSIGHT:
			return insight != null
		Outcome.DIALOGUE:
			return conversation_id != &"" and FileAccess.file_exists(DialogueCatalog.get_script_path(conversation_id))
		Outcome.EVIDENCE:
			return evidence != null
	return false


# Ponto do mundo no topo do desenho, centralizado: onde a caixa do insight nasce.
func _top_center() -> Vector2:
	var rect: Rect2 = _drawing_rect()
	return _sprite.to_global(Vector2(rect.get_center().x, rect.position.y))


# O retângulo do desenho em coordenadas do mundo (a caixa que o envolve, se o objeto estiver girado).
func _world_rect() -> Rect2:
	return _sprite.global_transform * _drawing_rect()


# O retângulo do desenho no espaço do sprite, sem a folga transparente do contorno.
func _drawing_rect() -> Rect2:
	return _sprite.get_rect().grow(-float(_padding))


# Recalcula o triângulo amarelo depois de uma edição no Inspector. Sem isto ele só apareceria na
# próxima vez que a cena fosse aberta.
func _refresh_editor_state() -> void:
	if is_node_ready() and Engine.is_editor_hint():
		update_configuration_warnings()
