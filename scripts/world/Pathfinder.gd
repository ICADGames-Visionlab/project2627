## Pathfinder - busca de caminho A* sobre grafo de visibilidade. Independente de tiles.
##
## COMO USAR (qualquer agente — Player, NPC, o que vier):
##
##     var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP)
##     var caminho: PackedVector2Array = pathfinder.find_path(global_position, destino, [get_rid()])
##
## O terceiro argumento nao e opcional na pratica: o agente PRECISA se excluir. A linha de visao e
## testada por raycast, e um raio que nasce dentro do colisor de quem perguntou bate nele mesmo.
## Sem se excluir, o agente nao enxerga lugar nenhum e todo caminho volta vazio.
##
## O retorno são os pontos a percorrer em ordem, já sem a posição de partida. Vazio significa que
## não há caminho. Nada aqui conhece o Player: quem chama só precisa de duas posições no mundo.
##
## POR QUE NÃO É BASEADO EM TILES
##
## Uma grade cobrindo o mapa gasta memória proporcional à ÁREA e dá caminhos em escadinha que
## precisam de suavização depois. Aqui o grafo é proporcional ao número de CANTOS de obstáculo —
## uns poucos nós num mapa inteiro — e o caminho já sai reto e ótimo, porque num plano com
## obstáculos poligonais o menor caminho sempre passa raspando nos cantos. Também não depende do
## TileMapLayer: obstáculo é qualquer corpo com CollisionPolygon2D, em qualquer posição, inclusive
## fora do grid.
##
## COMO O GRAFO É MONTADO
##
##   1. Junta os CollisionPolygon2D dos corpos que estão na máscara de obstáculo.
##   2. Infla cada um por agent_radius, pro caminho não passar colado na parede.
##   3. Os cantos dos polígonos inflados viram os nós — descartando os que caem dentro de outro
##      obstáculo, que seriam inalcançáveis.
##   4. Dois nós viram aresta quando há linha de visão entre eles, testada por raycast contra as
##      colisões de verdade. Usar o espaço de física em vez de refazer interseção na mão faz o
##      grafo respeitar qualquer shape que entrar na cena, sem precisar ensinar geometria nova aqui.
##
## O custo é O(n²) em raycasts, mas roda uma vez só no _ready. Se o cenário mudar em runtime
## (prédio destruído, ponte que abre), chame rebuild().
class_name Pathfinder
extends Node2D

## Espaço para variáveis

# Grupo em que este nó se registra, pros agentes o encontrarem sem precisar de um NodePath
# exportado em cada um.
const GROUP: StringName = &"pathfinder"

# Distância que os obstáculos são inflados, em pixels de tela.
#
# Não basta igualar ao "raio" do agente: os nós do grafo ficam EM CIMA da borda inflada, e o agente
# corta a curva ao mirar neles, então a folga que sobra no trajeto é sempre menor que este valor.
# Medido nesta cena, a perda chega a ~12 px. Como o colisor do Player tem meia-largura de 28, um
# agent_radius de 32 deixava a folga real em 20 px e o personagem raspava a parede em toda curva —
# e raspar derruba a velocidade, o que fazia o Player desistir do caminho no meio.
#
# Regra prática: meia-largura do maior agente + ~20 px de margem pro corte de curva.
#
# Nota pra quem for afinar: a inflação é uniforme, mas o chão é isométrico (achatado 2:1). Isso
# deixa a folga vertical mais generosa que a horizontal — erra pro lado seguro, que é o certo aqui.
# O custo de exagerar é fechar passagens estreitas: vãos menores que 2 x agent_radius somem do grafo.
@export var agent_radius: float = 48.0

# Camadas de física que contam como obstáculo. Só corpos nestas camadas entram no grafo e cortam
# linha de visão.
@export_flags_2d_physics var obstacle_mask: int = 1

# Seção em que os controles deste sistema aparecem no menu de debug (F4).
const DEBUG_SECTION: StringName = &"Navegação"

# Desenha o último caminho traçado por cima da cena. Também ligável pelo menu de debug.
@export var draw_path: bool = false:
	set(value):
		draw_path = value
		queue_redraw()

# Desenha o grafo inteiro — obstáculos inflados, nós e arestas. Separado do caminho porque é bem
# mais poluído: cresce com o número de cantos do cenário, não com o tamanho de um trajeto.
@export var draw_graph: bool = false:
	set(value):
		draw_graph = value
		queue_redraw()

# Quanto o polígono de folga é "afinado" para virar o polígono de passagem livre. Os nós ficam em
# cima da borda inflada, então sem essa margem um trecho que só costeia a borda seria lido como
# invasão por erro de arredondamento.
const CLEARANCE_TOLERANCE: float = 4.0

var _astar: AStar2D = AStar2D.new()
var _inflated_obstacles: Array[PackedVector2Array] = []

# Os mesmos obstáculos, encolhidos por CLEARANCE_TOLERANCE. Nenhuma aresta do grafo pode entrar
# aqui: é o que impede a corda entre dois vértices não vizinhos (ver _fits_agent).
var _clearance_obstacles: Array[PackedVector2Array] = []
var _last_path: PackedVector2Array = PackedVector2Array()

# De onde o último caminho foi pedido. Guardado só pro desenho de debug: find_path() devolve a rota
# sem a origem, e sem ela a linha desenhada não teria começo.
var _last_path_origin: Vector2 = Vector2.ZERO

# Corpos da cena que nao sao obstaculo (os agentes, basicamente). Ficam fora de todo raycast de
# linha de visao: sem isso, um NPC parado em cima de uma aresta do grafo derrubaria essa aresta no
# rebuild, e o grafo passaria a depender de onde cada um estava naquele instante.
var _ignored_rids: Array[RID] = []
var _obstacle_bodies: Array[PhysicsBody2D] = []

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Controles deste sistema no menu de debug (F4). Registrados antes do await pra já
		# existirem na primeira vez que alguém abrir o menu.
		DebugMenu.register_toggle(DEBUG_SECTION, "Desenhar caminho", _set_draw_path, draw_path)
		DebugMenu.register_toggle(DEBUG_SECTION, "Desenhar grafo", _set_draw_graph, draw_graph)
		DebugMenu.register_action(DEBUG_SECTION, "Remontar grafo", rebuild)

	# Espera um frame antes de varrer: estruturas instanciadas junto com a cena ainda podem estar
	# entrando na árvore, e um colisor que chegue depois ficaria de fora do grafo.
	await get_tree().process_frame
	rebuild()


func _draw() -> void:
	if draw_graph:
		# Laranja: a folga inflada em volta de cada obstáculo — a borda por onde o caminho passa.
		for obstacle: PackedVector2Array in _inflated_obstacles:
			var outline: PackedVector2Array = _to_local_points(obstacle)
			outline.append(outline[0])
			draw_polyline(outline, Color(1.0, 0.5, 0.0, 0.6), 3.0)

		# Azul: os nós e as arestas que o A* percorre.
		for id: int in _astar.get_point_ids():
			var origin: Vector2 = to_local(_astar.get_point_position(id))
			for other_id: int in _astar.get_point_connections(id):
				if other_id > id: # cada aresta desenhada uma vez só
					draw_line(origin, to_local(_astar.get_point_position(other_id)), Color(0.3, 0.7, 1.0, 0.25), 1.5)
			draw_circle(origin, 8.0, Color(0.3, 0.7, 1.0, 0.9))

	# Verde: o último caminho traçado. Desenhado a partir de onde ele foi PEDIDO — find_path()
	# devolve a rota sem a origem (o agente já está nela), e sem repor esse primeiro trecho aqui a
	# linha nasceria solta no meio do mapa, que é justo o que atrapalha na hora de depurar.
	#
	# É a rota como foi pedida, não o que falta percorrer: ela não encurta conforme o agente anda,
	# de propósito, pra dar pra ver a decisão inteira que o A* tomou.
	if draw_path and not _last_path.is_empty():
		var path: PackedVector2Array = _to_local_points(_last_path)
		path.insert(0, to_local(_last_path_origin))

		draw_polyline(path, Color(0.2, 1.0, 0.4, 0.9), 5.0)
		for point: Vector2 in path:
			draw_circle(point, 10.0, Color(0.2, 1.0, 0.4, 0.9))
		draw_circle(path[0], 18.0, Color(0.2, 1.0, 0.4, 0.35))            # origem
		draw_circle(path[path.size() - 1], 26.0, Color(0.2, 1.0, 0.4, 0.35)) # destino

## Espaço para funções personalizadas

# Caminho de "from" até "to", como a lista de pontos a percorrer em ordem (sem incluir "from").
# Devolve vazio quando não existe caminho.
# "exclude" deve conter o RID de quem esta pedindo o caminho (veja o cabecalho do arquivo).
func find_path(from: Vector2, to: Vector2, exclude: Array[RID] = []) -> PackedVector2Array:
	_last_path_origin = from

	# Sem obstáculo no meio o caminho é a reta, e nem vale montar consulta no grafo. É o caso mais
	# comum num mapa aberto, então vem primeiro.
	if _has_line_of_sight(from, to, exclude):
		return _remember_path(PackedVector2Array([to]))

	if _astar.get_point_count() == 0:
		return _remember_path(PackedVector2Array())

	# Clicou em cima de um prédio: em vez de ignorar o clique, mira no ponto acessível mais próximo.
	var goal: Vector2 = to
	if _is_inside_any_obstacle(goal):
		goal = _astar.get_point_position(_astar.get_closest_point(goal))

	# Início e destino entram no grafo só pra esta consulta, e saem logo em seguida.
	var from_id: int = _add_temporary_point(from, exclude)
	var goal_id: int = _add_temporary_point(goal, exclude)
	var path: PackedVector2Array = _astar.get_point_path(from_id, goal_id)
	_astar.remove_point(from_id)
	_astar.remove_point(goal_id)

	if path.size() <= 1:
		return _remember_path(PackedVector2Array())

	# O primeiro ponto é a própria posição de partida — o agente já está nele.
	return _remember_path(path.slice(1))


# Remonta o grafo do zero. Chame quando o cenário mudar em runtime.
func rebuild() -> void:
	_astar.clear()
	_inflated_obstacles.clear()
	_clearance_obstacles.clear()

	for polygon: PackedVector2Array in _collect_obstacle_polygons():
		for inflated: PackedVector2Array in Geometry2D.offset_polygon(polygon, agent_radius):
			_inflated_obstacles.append(inflated)
		for clearance: PackedVector2Array in Geometry2D.offset_polygon(polygon, agent_radius - CLEARANCE_TOLERANCE):
			_clearance_obstacles.append(clearance)

	for index: int in _inflated_obstacles.size():
		for corner: Vector2 in _inflated_obstacles[index]:
			# Canto que cai dentro de outro obstáculo é inalcançável: só sujaria o grafo.
			if not _is_inside_any_obstacle(corner, index):
				_astar.add_point(_astar.get_available_point_id(), corner)

	# Depois da coleta dos obstaculos: precisa saber quem E obstaculo pra saber quem ignorar.
	_collect_ignored_bodies()

	var edges: int = _connect_visible_points()
	queue_redraw()
	print("[Pathfinder] - Grafo montado: %d obstáculos, %d nós, %d arestas"
		% [_inflated_obstacles.size(), _astar.get_point_count(), edges])


# Junta os polígonos de colisão que contam como obstáculo, em coordenadas globais. A varredura sai
# do nó pai, então basta pendurar o Pathfinder na raiz da cena de gameplay.
func _collect_obstacle_polygons() -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	_obstacle_bodies.clear()

	for node: Node in get_parent().find_children("*", "CollisionPolygon2D", true, false):
		var collision_polygon: CollisionPolygon2D = node as CollisionPolygon2D

		# PhysicsBody2D, e não CollisionObject2D: Area2D é gatilho, nunca bloqueia passagem. Sem
		# esse filtro a área de oclusão que o Structure monta em runtime entraria como obstáculo e
		# o agente desviaria de um prédio inteiro que ele só precisa deixar transparente.
		var body: PhysicsBody2D = collision_polygon.get_parent() as PhysicsBody2D
		if body == null or (body.collision_layer & obstacle_mask) == 0:
			continue

		var global_points: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in collision_polygon.polygon:
			global_points.append(collision_polygon.global_transform * point)
		polygons.append(global_points)
		_obstacle_bodies.append(body)

	return polygons


# Liga todo par de nós que se enxerga. Devolve quantas arestas criou.
func _connect_visible_points() -> int:
	var ids: PackedInt64Array = _astar.get_point_ids()
	var edges: int = 0

	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var from: Vector2 = _astar.get_point_position(ids[i])
			var to: Vector2 = _astar.get_point_position(ids[j])
			if _has_line_of_sight(from, to) and _fits_agent(from, to):
				_astar.connect_points(ids[i], ids[j])
				edges += 1

	return edges


# Diz se o agente CABE no trecho, e não apenas se ele é visível.
#
# O raycast sozinho não garante isso: raio é uma linha sem espessura, então ele aprova a CORDA
# entre dois vértices não vizinhos do polígono inflado — um atalho que corta o interior da folga e
# passa raspando na quina do prédio. Como o agente tem largura, ele encalha ali: bate na quina,
# desliza pro lado errado e o caminho é abandonado. A folga inflada existe pra ser contornada pela
# borda, não atravessada por dentro.
#
# O teste é contra os obstáculos encolhidos, e não os inflados, justamente pra que um trecho que
# costeia a borda (que é o caminho certo) não seja confundido com invasão.
func _fits_agent(from: Vector2, to: Vector2) -> bool:
	for obstacle: PackedVector2Array in _clearance_obstacles:
		# Trecho inteiro contido no obstáculo: não cruza aresta nenhuma, mas está por dentro.
		if Geometry2D.is_point_in_polygon((from + to) * 0.5, obstacle):
			return false

		for index: int in obstacle.size():
			var edge_start: Vector2 = obstacle[index]
			var edge_end: Vector2 = obstacle[(index + 1) % obstacle.size()]
			if Geometry2D.segment_intersects_segment(from, to, edge_start, edge_end) != null:
				return false

	return true


# Põe um ponto avulso no grafo, ligado a tudo que ele enxerga. Usado pro início e o destino de uma
# consulta, que não são cantos de obstáculo e por isso não moram no grafo.
func _add_temporary_point(position: Vector2, exclude: Array[RID] = []) -> int:
	var id: int = _astar.get_available_point_id()
	_astar.add_point(id, position)
	var connections: int = 0

	for other_id: int in _astar.get_point_ids():
		if other_id == id:
			continue
		var other: Vector2 = _astar.get_point_position(other_id)
		if _has_line_of_sight(position, other, exclude) and _fits_agent(position, other):
			_astar.connect_points(id, other_id)
			connections += 1

	# Agente encostado na parede (ou destino clicado rente a ela): o ponto já nasce dentro da folga,
	# então exigir folga em todos os trechos deixaria ele sem saída nenhuma. Aqui o critério afrouxa
	# pra só linha de visão — o primeiro trecho pode raspar, e é o move_and_slide que resolve;
	# do segundo em diante o caminho volta a ser o do grafo, que respeita a folga.
	if connections == 0:
		for other_id: int in _astar.get_point_ids():
			if other_id != id and _has_line_of_sight(position, _astar.get_point_position(other_id), exclude):
				_astar.connect_points(id, other_id)

	return id


# Linha de visão por raycast contra as colisões reais. hit_from_inside cobre o caso de o segmento
# começar dentro de um obstáculo, que sem isso passaria como visível.
func _has_line_of_sight(from: Vector2, to: Vector2, exclude: Array[RID] = []) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, obstacle_mask)
	query.hit_from_inside = true
	# hit_from_inside e justamente o que torna a exclusao obrigatoria: o raio nasce dentro do
	# colisor de quem perguntou e bateria nele mesmo.
	query.exclude = _ignored_rids + exclude
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# Lista os corpos da cena que nao sao obstaculo, pra tira-los de todo raycast. Enquanto obstaculos
# e agentes dividirem a mesma camada de fisica isto e necessario; o jeito robusto de resolver de
# vez e dar aos obstaculos uma camada so deles e apontar obstacle_mask pra ela.
func _collect_ignored_bodies() -> void:
	_ignored_rids.clear()

	for node: Node in get_parent().find_children("*", "PhysicsBody2D", true, false):
		var body: PhysicsBody2D = node as PhysicsBody2D
		if not _obstacle_bodies.has(body):
			_ignored_rids.append(body.get_rid())


# Diz se o ponto está dentro de algum obstáculo inflado. skip_index serve pra testar um canto sem
# contar o polígono de onde ele veio — o canto está sempre na borda do próprio polígono, e esse
# caso é ambíguo.
func _is_inside_any_obstacle(point: Vector2, skip_index: int = -1) -> bool:
	for index: int in _inflated_obstacles.size():
		if index != skip_index and Geometry2D.is_point_in_polygon(point, _inflated_obstacles[index]):
			return true
	return false


func _remember_path(path: PackedVector2Array) -> PackedVector2Array:
	_last_path = path
	queue_redraw()
	return path


# Recebem o estado novo do interruptor do menu de debug. O setter da propriedade já chama
# queue_redraw(), então não tem nada a fazer além de repassar.
func _set_draw_path(enabled: bool) -> void:
	draw_path = enabled


func _set_draw_graph(enabled: bool) -> void:
	draw_graph = enabled


func _to_local_points(points: PackedVector2Array) -> PackedVector2Array:
	var local_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		local_points.append(to_local(point))
	return local_points
