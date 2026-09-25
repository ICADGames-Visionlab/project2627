## Waypoint - um ponto nomeado da cena que as rotinas de NPC apontam: a bancada da loja, o banco da
## praça, a cama da casa.
##
## COMO USAR:
##   1. Adicione um Marker2D com este script na cena, em cima do lugar exato (no chão, não na
##      cabeça — o NPC vai parar com os pés aqui).
##   2. Dê a ele um NOME descritivo. O nome do nó É o identificador usado nas rotinas.
##   3. No .tres da rotina, escreva esse mesmo nome no campo "waypoint".
##
## É só isso: o nó se registra sozinho num grupo e o NPCDirector acha pelo nome. Se você preferir
## que o identificador seja diferente do nome do nó (renomear o nó sem quebrar as rotinas, por
## exemplo), preencha "waypoint_id".
##
## No editor ele desenha o próprio identificador ao lado da cruz, e reclama se dois waypoints da
## mesma cena tiverem o mesmo identificador — que é o erro fácil de cometer e difícil de perceber,
## porque o NPC iria pro primeiro que aparecesse na varredura.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name Waypoint
extends Marker2D

## Espaço para constantes

# Grupo em que todo waypoint se registra, pro NPCDirector achar sem NodePath exportado em cada um.
const GROUP: StringName = &"npc_waypoint"

# Cor do desenho de editor. Verde-água pra não se confundir com o verde do caminho do Pathfinder
# nem com o laranja dos obstáculos.
const EDITOR_COLOR: Color = Color(0.25, 0.85, 0.75, 0.9)

## Espaço para variáveis exportadas

## Identificador usado nas rotinas. Vazio (o normal) significa "use o nome do nó".
@export var waypoint_id: StringName = &"":
	set(value):
		waypoint_id = value
		update_configuration_warnings()
		queue_redraw()

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)
	update_configuration_warnings()


func _draw() -> void:
	# Só serve pra montar a cena: em jogo o waypoint é invisível.
	if not Engine.is_editor_hint():
		return

	var font: Font = ThemeDB.fallback_font
	draw_circle(Vector2.ZERO, 6.0, EDITOR_COLOR)
	draw_string(font, Vector2(10.0, -6.0), String(get_id()), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, EDITOR_COLOR)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not is_inside_tree():
		return warnings

	var id: StringName = get_id()
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other: Waypoint = node as Waypoint
		if other != null and other != self and other.get_id() == id:
			warnings.append(
				"Já existe outro waypoint com o identificador \"%s\" (%s). " % [id, other.name]
				+ "As rotinas apontam pelo identificador, então o NPC iria para um dos dois sem critério.")
			break

	return warnings

## Espaço para funções personalizadas

# O identificador deste waypoint: o campo waypoint_id, ou o nome do nó quando ele está vazio.
func get_id() -> StringName:
	if waypoint_id != &"":
		return waypoint_id
	return name


# O waypoint de um identificador na cena atual, ou null se não existir. É por aqui que o NPCDirector
# transforma o nome escrito no .tres numa posição no mundo.
static func find(tree: SceneTree, id: StringName) -> Waypoint:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var waypoint: Waypoint = node as Waypoint
		if waypoint != null and waypoint.get_id() == id:
			return waypoint
	return null


# Os identificadores de todos os waypoints da cena atual, em ordem alfabética. Usado pelo comando
# "Listar waypoints da cena" do menu de debug — é o que o design consulta pra saber o que digitar.
static func collect_ids(tree: SceneTree) -> PackedStringArray:
	var ids: PackedStringArray = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		var waypoint: Waypoint = node as Waypoint
		if waypoint != null:
			ids.append(String(waypoint.get_id()))
	ids.sort()
	return ids
