# InsightSource.gd — O ponto do mundo que tem algo a dizer.
#
# É a única coisa que o designer manipula para criar conteúdo: arrasta a cena pronta para dentro do
# objeto (ou do NPC), posiciona, e preenche a lista de InsightData. Forma, camadas e marcador já vêm
# configurados; nenhum passo exige abrir um script.
#
# Ela é o gatilho dos DOIS canais — é ela que sabe que existe algo a dizer sobre aquele ponto. O que
# muda entre os canais é onde o orbe é desenhado: o de ambiente nasce aqui, no objeto; o de
# personagem nasce na órbita do jogador. Gatilho e âncora deixam de ser o mesmo lugar, e é por isso
# que o gizmo do editor desenha os dois casos de forma diferente.
#
# O raio da Area2D é uma coisa só com o alcance de clique do orbe de ambiente: dentro dele o orbe
# aceita clique, fora dele fica visível e apagado, servindo de convite para ir até lá.
#
# O guia completo está em docs/insights.md.
@tool
class_name InsightSource
extends Area2D

const MARKER_SCENE_PATH: String = "res://scenes/insights/InsightMarker.tscn"
const BUBBLE_SCENE_PATH: String = "res://scenes/insights/InsightBubble.tscn"
# Cores do gizmo do editor. Não são as cores do jogo: o orbe de personagem é desenhado branco aqui
# de propósito, porque a cor de verdade depende de qual cabeça vai falar em runtime.
const EDITOR_ENVIRONMENT_GIZMO_COLOR: Color = Color(0.35, 0.85, 0.45)
const EDITOR_CHARACTER_GIZMO_COLOR: Color = Color(0.9, 0.9, 0.95)
const EDITOR_RADIUS_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)

@export_group("Conteúdo")
@export var insights: Array[InsightData] = []:
	set = _set_insights

@export_group("Alcance")
# Distância em que o jogador pode clicar o orbe de ambiente e em que as cabeças passam a ter algo a
# dizer sobre este ponto.
@export var interaction_radius: float = 260.0:
	set = _set_interaction_radius

@export_group("Marcador")
# Onde o orbe de ambiente nasce, relativo a esta fonte. Serve para tirá-lo de dentro do objeto (uma
# placa, um telhado) sem mexer na posição da fonte, que é o centro do raio.
@export var marker_offset: Vector2 = Vector2(0.0, -60.0):
	set = _set_marker_offset

var _marker: InsightMarker = null
var _bubble: InsightBubble = null
var _current_insight: InsightData = null
var _player_in_range: bool = false

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_update_shape()
	if Engine.is_editor_hint():
		update_configuration_warnings()
		queue_redraw()
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	EventBus.insight_revealed.connect(_on_insight_revealed)
	InsightDirector.register_source(self)
	_check_initial_overlap.call_deferred()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	InsightDirector.unregister_source(self)


func _draw() -> void:
	# Em jogo, o raio só aparece com o interruptor do menu de debug ligado. A ordem da comparação
	# importa: dentro do editor o Autoload não existe, e o curto-circuito é o que evita o erro.
	if Engine.is_editor_hint() or InsightDirector.is_drawing_click_radius():
		draw_arc(Vector2.ZERO, interaction_radius, 0.0, TAU, 64, EDITOR_RADIUS_COLOR, 2.0, true)
	if not Engine.is_editor_hint():
		return
	if _has_channel(InsightData.Channel.ENVIRONMENT):
		draw_circle(marker_offset, 10.0, EDITOR_ENVIRONMENT_GIZMO_COLOR)
	if _has_channel(InsightData.Channel.CHARACTER):
		# Círculo vazado com uma seta saindo dele: o orbe de personagem NÃO vai aparecer aqui, vai
		# aparecer orbitando o jogador. Deixar isso visível no editor é mais barato que explicar.
		var anchor: Vector2 = marker_offset + Vector2(0.0, -34.0)
		draw_arc(anchor, 10.0, 0.0, TAU, 24, EDITOR_CHARACTER_GIZMO_COLOR, 2.0, true)
		draw_line(anchor + Vector2(14.0, 0.0), anchor + Vector2(40.0, 0.0), EDITOR_CHARACTER_GIZMO_COLOR, 2.0, true)
		draw_line(anchor + Vector2(40.0, 0.0), anchor + Vector2(32.0, -6.0), EDITOR_CHARACTER_GIZMO_COLOR, 2.0, true)
		draw_line(anchor + Vector2(40.0, 0.0), anchor + Vector2(32.0, 6.0), EDITOR_CHARACTER_GIZMO_COLOR, 2.0, true)


# Avisos na árvore de cena do editor. Cada linha aqui é um "sumiu e não sei por quê" que deixa de
# acontecer: as cinco portas do sistema falham todas do mesmo jeito, com silêncio, e um triângulo
# amarelo antes de rodar o jogo é a única resposta barata.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if insights.is_empty():
		warnings.append("Nenhum InsightData atribuído: esta fonte não vai mostrar nada.")
		return warnings
	var known_head_ids: Dictionary = _known_head_ids()
	var project_id_counts: Dictionary = _project_insight_id_counts()
	for index: int in insights.size():
		var insight: InsightData = insights[index]
		if insight == null:
			warnings.append("Insight %d está vazio." % index)
			continue
		var label: String = String(insight.id) if insight.id != &"" else "insight %d" % index
		if insight.id == &"":
			warnings.append("%s: sem id." % label)
		elif int(project_id_counts.get(insight.id, 0)) > 1:
			warnings.append("%s: id repetido em outro insight do projeto." % label)
		if insight.text_key.is_empty():
			warnings.append("%s: text_key vazio." % label)
		elif not InsightCatalog.has_translation_key(insight.text_key):
			warnings.append("%s: text_key \"%s\" não existe no translations.csv." % [label, insight.text_key])
		if insight.is_character():
			if insight.head_id == &"":
				warnings.append("%s: canal de personagem sem head_id." % label)
			elif not known_head_ids.has(insight.head_id):
				warnings.append("%s: head_id \"%s\" não corresponde a nenhuma cabeça." % [label, insight.head_id])
	return warnings


# Diz se o jogador está dentro do raio desta fonte. É a mesma condição para o clique do orbe de
# ambiente e para as cabeças terem algo a dizer sobre este ponto.
func is_player_in_range() -> bool:
	return _player_in_range


# Reavalia o marcador de ambiente desta fonte: qual insight vale agora, se ele já foi lido e se dá
# para clicar daqui. Chamado pelo InsightDirector — a fonte nunca decide sozinha o que está aberto.
func refresh_marker() -> void:
	if Engine.is_editor_hint():
		return
	_current_insight = InsightDirector.pick_environment(self)
	if _current_insight == null:
		if _marker != null:
			_marker.queue_free()
			_marker = null
		queue_redraw()
		return
	if _marker == null:
		_create_marker()
	_marker.configure(InsightDirector.ENVIRONMENT_COLOR, "")
	_marker.set_read(not InsightDirector.is_new(_current_insight))
	_marker.set_clickable(_player_in_range)
	queue_redraw()


# Abre a caixa de texto no lugar desta fonte. Quem chama é o InsightDirector, que resolveu a escolha
# mas não conhece a caixa: a fonte é que sabe onde ela está no mundo.
func open_bubble(insight: InsightData) -> void:
	if _bubble != null:
		_bubble.close()
	var scene: PackedScene = load(BUBBLE_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Insights] - ERRO: cena da caixa não encontrada em %s" % BUBBLE_SCENE_PATH)
		return
	_bubble = scene.instantiate() as InsightBubble
	_bubble.position = marker_offset
	add_child(_bubble)
	_bubble.closed.connect(_on_bubble_closed)
	_bubble.show_text(insight.text_key)


# Instancia o orbe de ambiente desta fonte. Um orbe por fonte, não um por insight: quatro insights
# no mesmo objeto mostram um marcador só, e a escolha do conteúdo acontece no clique.
func _create_marker() -> void:
	var scene: PackedScene = load(MARKER_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Insights] - ERRO: cena do marcador não encontrada em %s" % MARKER_SCENE_PATH)
		return
	_marker = scene.instantiate() as InsightMarker
	_marker.position = marker_offset
	add_child(_marker)
	_marker.clicked.connect(_on_marker_clicked)


# Leva o clique do orbe ao Director, que é quem decide o que é lido e anuncia o fato.
func _on_marker_clicked() -> void:
	InsightDirector.reveal(_current_insight, self)


# Esquece a caixa fechada. Sem isto, a próxima abertura tentaria fechar um nó já liberado.
func _on_bubble_closed() -> void:
	_bubble = null


# Reage à leitura de qualquer insight desta fonte para o orbe virar vazado no mesmo instante — sem
# esperar a reavaliação geral, que só chega no fim do frame.
func _on_insight_revealed(event: InsightRevealedEvent) -> void:
	if event.source_id == get_instance_id():
		refresh_marker()


# Entrada do jogador no raio. O teste de tipo existe porque a máscara da Area2D pega qualquer corpo
# da camada do mundo, e prédio não é jogador.
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_set_player_in_range(true)


# Saída do jogador do raio.
func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_set_player_in_range(false)


# Registra a mudança de proximidade e pede a reavaliação. Sair do raio fecha a caixa aberta: ler de
# longe o texto de algo que ficou para trás é o tipo de coisa que faz o jogador achar que o sistema
# está quebrado.
func _set_player_in_range(in_range: bool) -> void:
	if _player_in_range == in_range:
		return
	_player_in_range = in_range
	if not in_range and _bubble != null:
		_bubble.close()
	InsightDirector.request_refresh()


# Confere se o jogador já estava dentro do raio quando a cena carregou. body_entered só avisa
# entradas, então sem isto uma fonte que nasce em cima do jogador ficaria muda até ele sair e voltar.
func _check_initial_overlap() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		if body is Player:
			_set_player_in_range(true)
			return


# Mantém a forma da Area2D do tamanho do raio exposto no Inspector. A forma da cena é
# resource_local_to_scene, então cada fonte já recebe a própria cópia e mexer num raio não mexe no
# de todas as fontes do jogo. A comparação antes de escrever existe para não sujar a cena aberta no
# editor a cada abertura.
func _update_shape() -> void:
	if _collision_shape == null:
		return
	var circle: CircleShape2D = _collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		_collision_shape.shape = circle
	if not is_equal_approx(circle.radius, interaction_radius):
		circle.radius = interaction_radius


# Diz se esta fonte tem ao menos um insight do canal, para o gizmo do editor saber o que desenhar.
func _has_channel(channel: InsightData.Channel) -> bool:
	for insight: InsightData in insights:
		if insight != null and insight.channel == channel:
			return true
	return false


# Ids de cabeça que existem no projeto, para o aviso de configuração conferir head_id sem depender
# do HeadRegistry (que é Autoload e não existe dentro do editor).
func _known_head_ids() -> Dictionary:
	var result: Dictionary = {}
	for head: HeadData in InsightCatalog.load_all_heads():
		result[head.id] = true
	return result


# Quantas vezes cada id aparece no projeto inteiro. É o que permite acusar id repetido de dentro do
# editor, antes de o repetido virar um insight que nunca aparece.
func _project_insight_id_counts() -> Dictionary:
	var counts: Dictionary = {}
	for insight: InsightData in InsightCatalog.load_all_insights():
		counts[insight.id] = int(counts.get(insight.id, 0)) + 1
	return counts


func _set_insights(value: Array[InsightData]) -> void:
	insights = value
	_refresh_editor_state()


func _set_interaction_radius(value: float) -> void:
	interaction_radius = maxf(value, 0.0)
	if is_node_ready():
		_update_shape()
	_refresh_editor_state()


func _set_marker_offset(value: Vector2) -> void:
	marker_offset = value
	if _marker != null:
		_marker.position = marker_offset
	if _bubble != null:
		_bubble.position = marker_offset
	_refresh_editor_state()


# Redesenha o gizmo e recalcula os avisos depois de uma edição no Inspector. Sem isto, o triângulo
# amarelo só apareceria na próxima vez que a cena fosse aberta.
func _refresh_editor_state() -> void:
	if not is_node_ready():
		return
	queue_redraw()
	if Engine.is_editor_hint():
		update_configuration_warnings()
