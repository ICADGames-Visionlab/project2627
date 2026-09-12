## Structure - estrutura do cenário (prédio, muro, torre) que participa do Y-sort e fica
## transparente sozinha quando o jogador passa atrás dela.
##
## COMO USAR:
##   1. StaticBody2D com este script, dentro de um nó com y_sort_enabled (o YSort de main.tscn).
##   2. Um Sprite2D filho, com a arte.
##   3. Um CollisionPolygon2D filho, com o losango da base.
##   4. A ORIGEM DO NÓ tem que ficar no centro da base (não em 0,0 com o sprite deslocado).
##
## O passo 4 é o único fácil de errar, e é o que faz o Y-sort funcionar: o Godot ordena pelo
## global_position.y do nó, não por onde o sprite é desenhado. Se a origem estiver longe da base,
## o editor avisa (ver _get_configuration_warnings) em vez de o prédio sortear errado calado.
##
## Nada além disso precisa ser configurado: a área que detecta o jogador é construída em tempo de
## execução a partir da silhueta da estrutura (ver _build_occluder_polygon).
##
## Se alguma estrutura tiver um formato que a silhueta automática não acerta, basta adicionar uma
## Area2D filha à mão com a shape que você quiser — se existir uma, o script usa ela e não gera
## nada.
@tool
class_name Structure
extends StaticBody2D

## Espaço para variáveis

# Distância máxima, em pixels, entre a origem do nó e o centro da base antes do editor reclamar.
const ORIGIN_TOLERANCE: float = 24.0

# Opacidade da estrutura enquanto o jogador está atrás dela. 0 some de vez; o padrão deixa a
# silhueta visível, que é o normal em jogo isométrico — o jogador precisa continuar entendendo
# que tem um prédio ali.
@export_range(0.0, 1.0, 0.05) var occluded_alpha: float = 0.35

# Duração do fade (nos dois sentidos), em segundos. Curto de propósito: transição longa demais
# faz a estrutura "piscar" quando o jogador anda rente à borda.
@export var fade_duration: float = 0.15

var _sprite: Sprite2D
var _player: Player
var _is_occluded: bool = false
var _fade_tween: Tween

## Espaço para funções nativas

func _ready() -> void:
	_sprite = _find_sprite()
	update_configuration_warnings()

	if Engine.is_editor_hint():
		return

	if _sprite == null:
		push_error("[Structure] - \"%s\" não tem um Sprite2D filho; transparência desativada" % name)
		return

	var detector: Area2D = _find_detector()
	if detector == null:
		detector = _build_player_detector()
		add_child(detector)
	detector.body_entered.connect(_on_body_entered)
	detector.body_exited.connect(_on_body_exited)
	# Só custa CPU enquanto tem alguém dentro da área (ver _on_body_entered/_on_body_exited).
	set_process(false)


# Roda apenas enquanto o jogador está dentro da área da estrutura. Reavalia todo frame porque o
# jogador pode atravessar a linha de ordenação sem sair da área — andando de um lado pro outro
# por trás do prédio, por exemplo.
func _process(_delta: float) -> void:
	_set_occluded(_is_player_behind())


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if _find_sprite() == null:
		warnings.append("Falta um Sprite2D filho com a arte da estrutura.")

	var polygon: CollisionPolygon2D = _find_polygon()
	if polygon == null:
		warnings.append("Falta um CollisionPolygon2D filho com o losango da base.")
	else:
		var base_center: Vector2 = _get_base_center(polygon)
		if base_center.length() > ORIGIN_TOLERANCE:
			warnings.append(
				"A origem do nó está a %.0f px do centro da base %s. O Y-sort ordena pela origem, "
				% [base_center.length(), base_center]
				+ "então a estrutura vai passar na frente/atrás do jogador na hora errada. "
				+ "Mova o nó pro centro da base e compense o deslocamento no Sprite2D e no polígono."
			)

	return warnings

## Espaço para funções personalizadas

# Diz se o jogador está atrás desta estrutura, usando exatamente o mesmo critério do Y-sort: quem
# tem o Y global menor está mais ao fundo. Amarrar as duas coisas na mesma conta garante que a
# transparência nunca discorde de quem foi desenhado por cima.
func _is_player_behind() -> bool:
	return _player != null and _player.global_position.y < global_position.y


# Liga/desliga a transparência, ignorando chamadas que não mudam nada (o _process repete a mesma
# resposta a maior parte dos frames).
func _set_occluded(occluded: bool) -> void:
	if occluded == _is_occluded:
		return

	_is_occluded = occluded
	_fade_to(occluded_alpha if occluded else 1.0)


# Anima modulate.a até o valor pedido. modulate é herdado pelos filhos, então some o sprite
# inteiro sem precisar mexer em cada um. Mata o tween anterior pra não empilhar animações quando
# o jogador fica entrando e saindo depressa.
func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", target_alpha, fade_duration)


# Monta a Area2D que detecta o jogador, com o formato da silhueta da estrutura.
func _build_player_detector() -> Area2D:
	var collision_polygon: CollisionPolygon2D = CollisionPolygon2D.new()
	collision_polygon.polygon = _build_occluder_polygon()

	var detector: Area2D = Area2D.new()
	detector.name = &"PlayerDetector"
	detector.add_child(collision_polygon)
	return detector


# Silhueta que a estrutura ocupa na tela: o losango da base extrudado pra cima até o topo da arte.
#
# É a forma de um prisma isométrico visto de frente — e é bem mais justa que o retângulo do
# Sprite2D, porque a arte de um prédio em losango deixa os quatro cantos da textura vazios. Com o
# retângulo, o jogador começava a apagar o prédio andando por um canto onde não tem prédio nenhum.
#
# As duas medidas já existem na cena e não precisam ser desenhadas de novo: a planta baixa vem do
# CollisionPolygon2D que a colisão já usa, e a altura vem do pixel opaco mais alto da textura.
func _build_occluder_polygon() -> PackedVector2Array:
	var polygon: CollisionPolygon2D = _find_polygon()
	if polygon == null:
		# Sem planta baixa não dá pra montar o prisma; cai no retângulo opaco da arte, que ainda é
		# melhor que a textura inteira.
		var fallback: Rect2 = _get_art_rect()
		return PackedVector2Array([
			fallback.position,
			Vector2(fallback.end.x, fallback.position.y),
			fallback.end,
			Vector2(fallback.position.x, fallback.end.y),
		])

	var base: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in polygon.polygon:
		base.append(polygon.transform * point)

	# Altura da extrusão: do canto mais ao fundo da base até o topo da arte. Usar o canto mais ao
	# fundo (e não o centro) faz o topo do prisma encostar exatamente no topo do desenho.
	var base_top_y: float = base[0].y
	for point: Vector2 in base:
		base_top_y = minf(base_top_y, point.y)
	var height: float = maxf(base_top_y - _get_art_rect().position.y, 0.0)

	# A silhueta é o fecho convexo da base com ela mesma deslocada pra cima — o mesmo prisma que o
	# desenho representa.
	var silhouette: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in base:
		silhouette.append(point)
		silhouette.append(point - Vector2(0.0, height))
	return Geometry2D.convex_hull(silhouette)


# Retângulo da arte de fato desenhada (ignorando a transparência em volta), em coordenadas locais
# da estrutura. Cai no retângulo cheio do Sprite2D quando não dá pra inspecionar os pixels.
func _get_art_rect() -> Rect2:
	var full_rect: Rect2 = _sprite.transform * _sprite.get_rect()
	if _sprite.texture == null or _sprite.region_enabled:
		return full_rect

	var image: Image = _sprite.texture.get_image()
	if image == null:
		return full_rect
	if image.is_compressed() and image.decompress() != OK:
		return full_rect

	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return full_rect

	# get_used_rect() vem em pixels da textura; get_rect().position é onde o pixel (0,0) cai em
	# coordenadas locais do sprite (já considerando centered e offset).
	var texture_origin: Vector2 = _sprite.get_rect().position
	return _sprite.transform * Rect2(texture_origin + Vector2(used.position), Vector2(used.size))


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		set_process(true)


func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return

	_player = null
	set_process(false)
	_set_occluded(false)


# Centro do losango da base, em coordenadas locais. É a âncora de chão que a origem do nó deveria
# estar ocupando.
func _get_base_center(polygon: CollisionPolygon2D) -> Vector2:
	var points: PackedVector2Array = polygon.polygon
	if points.is_empty():
		return Vector2.ZERO

	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		sum += point
	return polygon.transform * (sum / points.size())


func _find_detector() -> Area2D:
	for child: Node in get_children():
		if child is Area2D:
			return child
	return null


func _find_sprite() -> Sprite2D:
	for child: Node in get_children():
		if child is Sprite2D:
			return child
	return null


func _find_polygon() -> CollisionPolygon2D:
	for child: Node in get_children():
		if child is CollisionPolygon2D:
			return child
	return null
