## GameSession - Liga e desliga o relógio junto com a cena de jogo, e guarda no save onde o jogador
## está (participante "world" do SaveManager) e o que ficou no chão (participante "pickups").
##
## COMO USAR: um nó com este script dentro da cena de gameplay, em qualquer lugar da árvore.
## Só isso. Ele chama GameClock.start_session() ao entrar e stop_session() ao sair, e entra no save
## no _ready() e sai no _exit_tree(). Numa cena que não seja a cidade, ajuste location_id no Inspector
## e ponha o local em LOCATION_SCENES.
##
## POR QUE ISTO EXISTE EM VEZ DE O RELÓGIO SE LIGAR SOZINHO: o GameClock é Autoload, ou seja,
## existe desde o boot do jogo — inclusive no menu principal e na tela de loading, que são cenas
## comuns e não pausa. Se ele começasse a contar no próprio _ready(), o tempo passaria enquanto o
## jogador escolhe o slot de save. Quem sabe que uma partida começou é a cena de jogo, então é
## ela que avisa.
##
## Efeito colateral bem-vindo: rodar a cena de jogo direto pelo editor (F6) também liga o
## relógio, sem precisar passar pelo menu. Mas F6 não abre partida: sem sessão, nada é carregado nem
## gravado. Para jogar com progresso, F4 -> Save -> "Continuar slot".
##
## A SEÇÃO "world" DO SAVE: o id do local (não o caminho da cena: renomear um .tscn não quebra save)
## e a última posição segura do Player (ver Player.get_last_safe_position()). O Player é achado pelo
## grupo, então a cena não precisa ligar nada no Inspector. LOCATION_SCENES é a única tabela de
## locais do jogo: o menu de slots escolhe a cena e o nome do local por ela.
##
## A SEÇÃO "pickups" DO SAVE: os itens no chão de cada local (ItemPickup, achados pelo grupo). Fica
## fora de "world" porque guarda TODOS os locais, não só o atual: o que o jogador largou na cidade
## continua lá enquanto ele está em outro lugar. Por local, duas listas:
##   - collected: itens postos na cena no editor que o jogador já pegou, pelo caminho do nó a partir
##     da raiz da cena. Na volta, eles são tirados da cena. Renomear ou mover um desses nós faz ele
##     reaparecer para quem já o pegou.
##   - dropped: itens que o jogador largou, inteiros (id do item, quantidade e posição). Na volta,
##     são recriados.
## A gravação é um retrato da cena no instante em que o SaveManager grava, junto com o inventário:
## pegar ou largar um item nunca deixa o item nos dois lugares, nem em nenhum.
##
## QUEM ABRE O DIA SEGUINTE NÃO É ESTE ARQUIVO, É A CAMA (ver Bed.gd). Ao bater no horário
## máximo o relógio congela e o jogo fica esperando: o jogador continua andando, mas o tempo não
## anda mais até ele ir dormir. Virar o dia por conta própria aqui tiraria do jogador a única
## decisão que o sistema de tempo cobra dele.
class_name GameSession
extends Node

## Espaço para constantes

# Chave da seção no save. É contrato do arquivo: renomear pede um passo de migração no SaveManager.
const SAVE_KEY: String = "world"
# Campos da seção: o id do local (String) e a posição, como [x, y] (Vector2 não sobrevive ao JSON).
const LOCATION_KEY: String = "location"
const POSITION_KEY: String = "position"

# Local de um novo jogo, e o destino de um save sem local ou com um local que o jogo não conhece.
const DEFAULT_LOCATION: StringName = &"city"

# Local -> cena. Única tabela de locais do jogo; o menu de slots abre e rotula por ela.
const LOCATION_SCENES: Dictionary = { &"city": "res://scenes/City.tscn" }

# Prefixo da chave de tradução do nome do local (LOCATION_CITY no translations.csv).
const LOCATION_LABEL_PREFIX: String = "LOCATION_"

# Chave da seção dos itens no chão: { id do local: { collected: [...], dropped: [...] } }.
const PICKUPS_SAVE_KEY: String = "pickups"
const COLLECTED_KEY: String = "collected"
const DROPPED_KEY: String = "dropped"
# Campos de cada item largado, além de POSITION_KEY.
const ITEM_KEY: String = "item"
const AMOUNT_KEY: String = "amount"

## Espaço para variáveis exportadas

# Que local esta cena de jogo é. O padrão cobre City.tscn sem editar a cena.
@export var location_id: StringName = DEFAULT_LOCATION

## Espaço para variáveis

# Seção "pickups" como chegou do save. Só os OUTROS locais são lidos daqui na gravação: o deste é
# sempre retrato da cena.
var _pickups_by_location: Dictionary = {}
# Itens postos nesta cena que estavam no chão quando a partida carregou: caminho -> ItemPickup. Um
# que saiu da árvore desde então foi pego.
var _placed_pickups: Dictionary = {}
# Caminhos dos itens postos nesta cena que o jogador já tinha pego antes de a partida carregar.
var _collected_ids: Array[String] = []

## Espaço para funções nativas

func _ready() -> void:
	# Com partida aberta, o registro já entrega a seção "world" (registro tardio do SaveManager) e a
	# posição é restaurada aqui, antes do primeiro quadro de física do Player.
	SaveManager.register_participant(SAVE_KEY, _to_save, _from_save)
	SaveManager.register_participant(PICKUPS_SAVE_KEY, _pickups_to_save, _pickups_from_save)
	# Adiado de propósito: start_session() anuncia time_changed, e o _ready() dos irmãos que
	# escutam o relógio (HUD, NPCs) pode ainda não ter rodado — _ready corre na ordem da árvore,
	# e depender dela seria um bug esperando a primeira vez que alguém arrastar um nó. O
	# call_deferred cai no fim do frame, com a cena inteira já montada e conectada.
	GameClock.start_session.call_deferred()


func _exit_tree() -> void:
	# As seções ficam no SaveManager como estavam na última gravação: sair da cena não apaga o local
	# nem o que ficou no chão.
	SaveManager.unregister_participant(SAVE_KEY)
	SaveManager.unregister_participant(PICKUPS_SAVE_KEY)
	GameClock.stop_session()

## Espaço para funções personalizadas

# Cena do local salvo na seção "world". Local vazio ou desconhecido (novo jogo, save v0, save de
# outra branch) cai em DEFAULT_LOCATION: abrir a cidade é melhor que não abrir nada.
static func scene_path_for(world: Dictionary) -> String:
	var path: String = LOCATION_SCENES[_resolve_location(world)]
	return path


# Chave de tradução do nome do local salvo: LOCATION_ + id em maiúsculas (LOCATION_CITY). Usa o
# mesmo fallback de scene_path_for(), então o menu mostra o nome do lugar onde o jogo vai abrir.
static func location_label_key(world: Dictionary) -> String:
	return LOCATION_LABEL_PREFIX + String(_resolve_location(world)).to_upper()


# O id de local da seção, se o jogo conhece esse local; senão DEFAULT_LOCATION. O id volta do JSON
# como String e as chaves da tabela são StringName, por isso a conversão antes de consultar.
static func _resolve_location(world: Dictionary) -> StringName:
	var location: StringName = StringName(str(world.get(LOCATION_KEY, "")))
	if LOCATION_SCENES.has(location):
		return location
	return DEFAULT_LOCATION


# Seção "world" do save: o local e a última posição segura do Player. Sem Player na cena, só o local.
func _to_save() -> Dictionary:
	var data: Dictionary = { LOCATION_KEY: String(location_id) }
	var player: Player = _find_player()
	if player != null:
		var position: Vector2 = player.get_last_safe_position()
		data[POSITION_KEY] = [position.x, position.y]
	return data


# Recebe a seção "world". Local salvo diferente deste ({} de novo jogo, save v0, ou uma porta no
# futuro): o Player fica no ponto de partida da cena e isto pede gravação, porque entrar num local é
# gesto — o pedido espera o fade da troca de cena acabar. Mesmo local com uma posição de dois
# números: o Player volta para ela (e ele mesmo confere se não caiu dentro de uma parede).
func _from_save(data: Dictionary) -> void:
	var saved_location: StringName = StringName(str(data.get(LOCATION_KEY, "")))
	if saved_location != location_id:
		print("[GameSession] - Local salvo \"%s\" não é \"%s\"; jogador no ponto de partida" % [
			saved_location, location_id])
		SaveManager.request_save()
		return

	var raw_position: Variant = data.get(POSITION_KEY)
	var player: Player = _find_player()
	if player == null or not _is_position_pair(raw_position):
		print("[GameSession] - Sem posição salva utilizável em \"%s\"; jogador no ponto de partida" % location_id)
		return
	var pair: Array = raw_position
	player.restore_position(Vector2(float(pair[0]), float(pair[1])))


# Seção "pickups" do save: os outros locais como chegaram, e este como está agora. Os pegos são os
# que já estavam pegos ao carregar mais os postos na cena que saíram da árvore desde então; os
# largados são todos os pickups criados com o jogo rodando que ainda estão no chão.
func _pickups_to_save() -> Dictionary:
	var collected: Array[String] = _collected_ids.duplicate()
	for pickup_id: String in _placed_pickups:
		# Variant antes do tipo: um pickup pego já foi liberado, e atribuir objeto liberado a uma
		# variável tipada é erro.
		var node: Variant = _placed_pickups[pickup_id]
		if not is_instance_valid(node) or not _is_on_the_ground(node as ItemPickup):
			collected.append(pickup_id)
	collected.sort()

	var dropped: Array[Dictionary] = []
	for pickup: ItemPickup in _find_pickups():
		if pickup.is_placed_in_scene() or pickup.item == null:
			continue
		dropped.append({
			ITEM_KEY: String(pickup.item.id),
			AMOUNT_KEY: pickup.amount,
			POSITION_KEY: [pickup.global_position.x, pickup.global_position.y],
		})

	var result: Dictionary = _pickups_by_location.duplicate(true)
	result[String(location_id)] = { COLLECTED_KEY: collected, DROPPED_KEY: dropped }
	return result


# Recebe a seção "pickups". {} é o novo jogo: todo item posto na cena fica no chão e nada largado
# volta. Tira da cena os itens que o jogador já pegou e recria os que ele largou. Os largados que já
# estivessem na cena saem antes: só existem se a mesma cena receber a seção de novo, e ficariam em
# dobro.
func _pickups_from_save(data: Dictionary) -> void:
	_pickups_by_location = data
	var entry: Dictionary = _location_pickups(data)
	_collected_ids.clear()
	var saved_collected: Variant = entry.get(COLLECTED_KEY, [])
	if saved_collected is Array:
		for raw_id: Variant in saved_collected:
			_collected_ids.append(str(raw_id))

	_placed_pickups.clear()
	var removed: int = 0
	for pickup: ItemPickup in _find_pickups():
		if not pickup.is_placed_in_scene():
			pickup.queue_free()
			continue
		var pickup_id: String = _pickup_id(pickup)
		if _collected_ids.has(pickup_id):
			pickup.queue_free()
			removed += 1
		else:
			_placed_pickups[pickup_id] = pickup

	var saved_dropped: Variant = entry.get(DROPPED_KEY, [])
	var dropped: Array = saved_dropped if saved_dropped is Array else []
	print("[GameSession] - Itens no chão de \"%s\": %d já pego(s) tirado(s) da cena, %d largado(s) a recriar"
		% [location_id, removed, dropped.size()])
	# Adiado: com a cena ainda montando, o pai dos itens pode estar no meio do _ready dos filhos, e
	# add_child() nele falharia ("Parent node is busy setting up children").
	_spawn_dropped_pickups.call_deferred(dropped)


# Recria no chão os itens que o jogador largou, como vieram do save. Entrada inválida (item que o
# ItemCatalog não acha mais, quantidade ou posição que não são números) é ignorada, sem erro.
func _spawn_dropped_pickups(dropped: Array) -> void:
	if not is_inside_tree() or dropped.is_empty():
		return
	var scene: PackedScene = load(Inventory.PICKUP_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[GameSession] - ERRO: cena de pickup não encontrada em %s" % Inventory.PICKUP_SCENE_PATH)
		return
	var container: Node = _drop_container()
	for raw_drop: Variant in dropped:
		var drop: Dictionary = raw_drop if raw_drop is Dictionary else {}
		var item: ItemData = ItemCatalog.find_item(StringName(str(drop.get(ITEM_KEY, ""))))
		var raw_amount: Variant = drop.get(AMOUNT_KEY)
		var raw_position: Variant = drop.get(POSITION_KEY)
		if item == null or not (raw_amount is float or raw_amount is int) or not _is_position_pair(raw_position):
			print("[GameSession] - Item largado inválido no save ignorado: %s" % [raw_drop])
			continue
		var pickup: ItemPickup = scene.instantiate() as ItemPickup
		var pair: Array = raw_position
		pickup.item = item
		pickup.amount = clampi(int(raw_amount), 1, item.max_stack)
		pickup.global_position = Vector2(float(pair[0]), float(pair[1]))
		container.add_child(pickup)


# A entrada deste local na seção "pickups", ou {} se ele não tem nenhuma (ou se ela não é objeto).
func _location_pickups(data: Dictionary) -> Dictionary:
	var entry: Variant = data.get(String(location_id), {})
	return entry if entry is Dictionary else {}


# Todos os ItemPickup desta cena que ainda estão no chão.
func _find_pickups() -> Array[ItemPickup]:
	var result: Array[ItemPickup] = []
	for node: Node in get_tree().get_nodes_in_group(ItemPickup.GROUP):
		var pickup: ItemPickup = node as ItemPickup
		if _is_on_the_ground(pickup):
			result.append(pickup)
	return result


# O pickup ainda está no chão: na árvore e não pego (pegar chama queue_free, e o nó só sai no fim do
# frame).
static func _is_on_the_ground(pickup: ItemPickup) -> bool:
	return pickup != null and pickup.is_inside_tree() and not pickup.is_queued_for_deletion()


# Id de um item posto na cena: o caminho do nó a partir da raiz da cena do local
# ("YSort/Evidencias/Bilhete"). Estável enquanto ninguém renomear nem mover o nó no editor.
func _pickup_id(pickup: ItemPickup) -> String:
	return String(_scene_root().get_path_to(pickup))


# Raiz da cena do local: o owner desta GameSession, que é posta direto na cena. A cena atual só
# entra se a GameSession tiver sido criada por código.
func _scene_root() -> Node:
	return owner if owner != null else get_tree().current_scene


# Onde um item largado recriado do save entra: o mesmo pai do Player (o YSort), pelo mesmo motivo do
# Inventory._get_drop_container(): fora do YSort ele desenharia por cima de tudo.
func _drop_container() -> Node:
	var player: Player = _find_player()
	if player != null and player.get_parent() != null:
		return player.get_parent()
	return _scene_root()


# O Player da cena, pelo grupo (mesmo jeito do NPCInteraction), ou null numa cena sem jogador.
func _find_player() -> Player:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Player.GROUP) as Player


# A posição do save é uma lista de exatamente dois números? Qualquer outra coisa (save editado à mão,
# formato futuro) é tratada como posição ausente, não como erro.
static func _is_position_pair(value: Variant) -> bool:
	if value is not Array:
		return false
	var pair: Array = value
	if pair.size() != 2:
		return false
	return (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int)
