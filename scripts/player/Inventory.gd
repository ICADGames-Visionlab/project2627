## Inventory - inventário de um personagem: guarda itens (ItemData) e suas quantidades, e expõe
## as três ações que o jogador tem sobre eles: pegar (add_item, chamado pelo ItemPickup), largar
## (drop_item) e destruir (destroy_item).
##
## NÃO é Singleton de propósito. GUIDELINE_PROGRAMACAO.md (seção "Singletons") lista Inventário
## como exemplo do que NÃO deve virar Autoload: cada personagem que precisa de inventário tem a
## sua própria instância, como filho direto na cena (hoje só o Player). Um Singleton obrigaria
## toda chamada a resolver "de qual personagem?" — o acoplamento que a seção de Singletons pede
## para evitar.
##
## COMO USAR: já vem como filho "Inventory" do Player.tscn, nenhuma configuração extra é
## necessária. Quem precisa da instância sem ter um caminho direto na árvore (hoje só a
## InventoryUI) encontra pelo grupo GROUP_NAME — o mesmo padrão do exemplo "Wallet" documentado em
## docs/event_bus.md, seção "Escutar direito". Ver docs/Inventory.md para a documentação completa.
class_name Inventory
extends Node

## Espaço para sinais

# Emitido quando uma quantidade de um item entra no inventário (pickup ou comando de debug). O
# "amount" é a quantidade REALMENTE adicionada, não a pedida — se a pilha satura em
# item.max_stack, o excedente não é contado aqui. Ouvinte: InventoryUI, para redesenhar o slot.
signal item_added(item: ItemData, amount: int)

# Emitido quando o jogador larga um item no mundo (ele deixa de estar no inventário e vira um
# ItemPickup na cena atual). Ouvinte: InventoryUI.
signal item_dropped(item: ItemData, amount: int)

# Emitido quando o jogador destrói um item (ele deixa de existir, sem virar ItemPickup). Ouvinte:
# InventoryUI; no futuro, possivelmente um sistema de missões reagindo a evidência descartada.
signal item_destroyed(item: ItemData, amount: int)

## Espaço para variáveis

# Nome do grupo em que toda instância de Inventory entra (ver _enter_tree). É assim que a
# InventoryUI encontra o inventário do jogador sem precisar de uma referência exportada.
const GROUP_NAME: StringName = &"inventory"

# Caminho da cena instanciada no chão quando um item é largado (drop_item). Carregado sob demanda
# com load() dentro de drop_item() — e NÃO com preload() no topo do script — de propósito:
# ItemPickup.gd referencia a classe Inventory (Inventory.GROUP_NAME, "as Inventory"), então um
# preload() aqui em cima criaria uma dependência circular em tempo de COMPILAÇÃO entre os dois
# scripts (Inventory precisaria de ItemPickup já compilado, que precisa de Inventory já
# compilado — nenhum dos dois termina). load() dentro de uma função só roda em runtime, quando os
# dois já compilaram; mesmo resultado, sem o ciclo.
const PICKUP_SCENE_PATH: String = "res://scenes/items/ItemPickup.tscn"

# Distância, em pixels, entre o dono deste inventário e o ItemPickup instanciado por drop_item().
# O colisor do Player (CapsuleShape2D, radius 14, height 56 — ver Player.tscn) está rotacionado 90°
# (rotation = 1.5707964), então a meia-extensão HORIZONTAL do Player é height / 2 = 28px, e não o
# radius. Largando de lado — o caso comum, já que _get_drop_position() usa a direção da
# velocidade — a folga mínima real é 28 (Player) + 24 (raio do CircleShape2D do ItemPickup) = 52px.
# 56 dá só 4px de margem sobre esse mínimo. NÃO reduza este valor achando que o piso é
# radius + radius = 38: esse número ignora a rotação do colisor e reabre o bug de o item voltar
# pro inventário sozinho assim que é largado.
const DROP_OFFSET_DISTANCE: float = 56.0

# Cena instanciada no chão quando um item é largado. Exportado para poder trocar por uma variante
# diferente por personagem; deixado vazio (null) por padrão — drop_item() carrega
# PICKUP_SCENE_PATH sob demanda quando este campo não foi preenchido no Inspector (ver comentário
# de PICKUP_SCENE_PATH acima).
@export var pickup_scene: PackedScene

# Itens conhecidos por este inventário só para fins de debug: alimenta as sugestões e a busca do
# comando de console "dar_evidencia" (ver _register_debug_commands). Não é o catálogo do jogo
# inteiro, só o que foi arrastado aqui pra teste — vazio não quebra nada, só faz o comando não
# encontrar item nenhum. Já vem com o item de exemplo do projeto pra dar pra testar sem precisar
# abrir o Inspector. ItemData.gd não referencia Inventory nem ItemPickup, então preload() aqui não
# tem o problema de ciclo do pickup_scene acima.
#
# Pode conter entradas null: um clique em "Add Element" no Inspector cria uma entrada vazia antes
# de alguém arrastar o .tres pra ela. Todo código que itera este array (_on_debug_give_item,
# _debug_item_ids) precisa pular entradas null.
@export var debug_item_catalog: Array[ItemData] = [preload("res://items/EvidenciaExemplo.tres")]

# Pilhas atuais, indexadas pelo id do item. Uma pilha só por item — ver "Limitações atuais" em
# docs/Inventory.md para como isso escalaria para múltiplas pilhas do mesmo item.
var _stacks: Dictionary[StringName, ItemStack] = {}

## Espaço para funções nativas

func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	_register_debug_commands()

## Espaço para funções personalizadas

# --- API pública ---

# Adiciona amount unidades de item ao inventário, criando a pilha se for a primeira unidade do
# item. A quantidade satura em item.max_stack (excedente é descartado — inventário sem conceito
# de "cheio" ainda, ver docs/Inventory.md). Emite item_added só com o que REALMENTE entrou — se a
# pilha já estava no máximo, nada entra e o sinal não é emitido (quem escuta, como a UI ou um
# futuro sistema de missões, não pode contar uma adição que não aconteceu). Público: chamado pelo
# ItemPickup ao ser coletado, e pelo comando de debug "dar_evidencia".
func add_item(item: ItemData, amount: int = 1) -> void:
	if item == null or amount <= 0:
		return

	var stack: ItemStack = _stacks.get(item.id)
	if stack == null:
		stack = ItemStack.new(item, 0)
		_stacks[item.id] = stack

	var previous_amount: int = stack.amount
	stack.amount = mini(stack.amount + amount, item.max_stack)
	var added: int = stack.amount - previous_amount
	if added <= 0:
		return

	item_added.emit(item, added)
	print("[Inventory] - Item \"%s\" adicionado (x%d, total %d)" % [item.id, added, stack.amount])


# Diz se o inventário tem ao menos amount unidades do item indicado.
func has_item(item_id: StringName, amount: int = 1) -> bool:
	var stack: ItemStack = _stacks.get(item_id)
	return stack != null and stack.amount >= amount


# Quantidade atual de um item (0 se o inventário não tiver nenhuma unidade dele).
func get_amount(item_id: StringName) -> int:
	var stack: ItemStack = _stacks.get(item_id)
	return stack.amount if stack != null else 0


# Todas as pilhas não vazias, para a UI desenhar a lista de evidências.
func get_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for stack: ItemStack in _stacks.values():
		if stack.amount > 0:
			result.append(stack)
	return result


# Remove amount unidades do item e instancia um ItemPickup no mundo, na posição do dono deste
# inventário. Devolve false (sem efeito nenhum, item continua no inventário) se não houver
# unidades suficientes OU se o ItemPickup não puder ser criado (cena não carrega, raiz errada, sem
# container pra receber o nó). A pilha só é decrementada DEPOIS que o pickup já existe e está na
# árvore, nunca antes — largar não pode fazer o item desaparecer do jogo inteiro.
func drop_item(item_id: StringName, amount: int = 1) -> bool:
	var stack: ItemStack = _stacks.get(item_id)
	if stack == null or amount <= 0 or stack.amount < amount:
		return false

	var item: ItemData = stack.item
	if not _spawn_pickup(item, amount):
		return false

	_remove_from_stack(stack, amount)
	item_dropped.emit(item, amount)
	print("[Inventory] - Item \"%s\" largado (x%d)" % [item_id, amount])
	return true


# Remove amount unidades do item sem devolvê-las ao mundo. Devolve false (sem efeito nenhum) se
# não houver unidades suficientes, ou se o item não permitir destruição (ItemData.destructible).
func destroy_item(item_id: StringName, amount: int = 1) -> bool:
	var stack: ItemStack = _stacks.get(item_id)
	if stack == null or amount <= 0 or stack.amount < amount:
		return false
	if not stack.item.destructible:
		push_warning("[Inventory] - Tentativa de destruir item não destrutível \"%s\"" % item_id)
		return false

	var item: ItemData = stack.item
	_remove_from_stack(stack, amount)

	item_destroyed.emit(item, amount)
	print("[Inventory] - Item \"%s\" destruído (x%d)" % [item_id, amount])
	return true


# --- Internos ---

# Tira amount unidades de uma pilha e apaga a entrada do Dictionary quando ela zera, pra
# get_stacks()/has_item() não precisarem filtrar pilhas vazias em todo lugar que consultam.
func _remove_from_stack(stack: ItemStack, amount: int) -> void:
	stack.amount -= amount
	if stack.amount <= 0:
		_stacks.erase(stack.item.id)


# Instancia um ItemPickup para (item, amount) e o adiciona ao container correto da árvore
# (ver _get_drop_container), sem tocar no inventário. Devolve false sem criar nada se a cena de
# pickup não carregar, se a raiz dela não for um ItemPickup (ex: pickup_scene preenchido no
# Inspector com uma cena diferente), ou se não houver um container válido pra receber o nó (ex:
# durante o fade de troca de cena do GameManager). Chamado só por drop_item(), sempre ANTES de
# decrementar a pilha.
func _spawn_pickup(item: ItemData, amount: int) -> bool:
	var scene: PackedScene = pickup_scene
	if scene == null:
		scene = load(PICKUP_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("[Inventory] - drop_item: não foi possível carregar \"%s\"; item mantido no inventário" % PICKUP_SCENE_PATH)
		return false

	var pickup: ItemPickup = scene.instantiate() as ItemPickup
	if pickup == null:
		push_warning("[Inventory] - drop_item: a raiz da cena de pickup não é um ItemPickup; item mantido no inventário")
		return false

	var container: Node = _get_drop_container()
	if container == null or not container.is_inside_tree():
		push_warning("[Inventory] - drop_item: sem container válido para o pickup (troca de cena em andamento?); item mantido no inventário")
		pickup.queue_free()
		return false

	pickup.item = item
	pickup.amount = amount
	pickup.global_position = _get_drop_position()
	container.add_child(pickup)
	return true


# Nó onde um ItemPickup largado deve entrar: o mesmo pai do dono deste inventário — hoje, o YSort
# de main.tscn (ver main.tscn e Structure.gd) — e NÃO get_tree().current_scene. Tudo que participa
# do Y-sort (Player, Structure) vive DENTRO do YSort, não como filho direto da cena; um pickup
# adicionado fora dele nasce depois do YSort na ordem de filhos e desenha por cima de tudo,
# independente da posição no mundo. Cai em current_scene se o dono não tiver um pai — só evita
# crash, não deveria acontecer hoje (Inventory só existe dentro de Player.tscn, sempre instanciado
# dentro do YSort).
func _get_drop_container() -> Node:
	var owner_node: Node = get_parent()
	if owner_node != null and owner_node.get_parent() != null:
		return owner_node.get_parent()
	return get_tree().current_scene


# Posição onde um item largado deve aparecer: um pouco afastada do dono deste inventário (ver
# DROP_OFFSET_DISTANCE), na direção pra onde ele está se movendo — ou "pra baixo" (Vector2.DOWN)
# se estiver parado. NUNCA em cima do próprio dono: ver o comentário de DROP_OFFSET_DISTANCE para
# o porquê. Cai na origem se o dono não for um Node2D — só evita crash, não deveria acontecer hoje
# (Inventory só existe dentro de Player.tscn).
func _get_drop_position() -> Vector2:
	var owner_node: Node2D = get_parent() as Node2D
	if owner_node == null:
		return Vector2.ZERO

	var direction: Vector2 = Vector2.DOWN
	var owner_body: CharacterBody2D = owner_node as CharacterBody2D
	if owner_body != null and owner_body.velocity.length() > 0.01:
		direction = owner_body.velocity.normalized()

	return owner_node.global_position + direction * DROP_OFFSET_DISTANCE


# Registra o comando de debug "dar_evidencia" no DebugMenu (F4/F1). Existe só para testar o
# inventário sem precisar espalhar ItemPickup pelo mapa; a lista de itens sugeridos vem de
# debug_item_catalog, preenchido no Inspector. register_input já não faz nada em build de
# release, então não precisa de guarda extra aqui.
func _register_debug_commands() -> void:
	var id_param: DebugParam = DebugParam.string_value("id do item", "", _debug_item_ids)
	var amount_param: DebugParam = DebugParam.int_value("quantidade", 1, 1, 99)
	var params: Array[DebugParam] = [id_param, amount_param]
	DebugMenu.register_input(&"Inventário", "Dar evidência", _on_debug_give_item, params)


# Callable do comando de debug acima: procura o item por id em debug_item_catalog e adiciona.
# Pula entradas null (ver comentário de debug_item_catalog) — sem essa checagem, item.id numa
# entrada vazia derruba o Debug Console inteiro assim que ele é aberto.
func _on_debug_give_item(item_id: String, amount: int) -> void:
	for item: ItemData in debug_item_catalog:
		if item == null:
			continue
		if String(item.id) == item_id:
			add_item(item, amount)
			return
	push_warning("[Inventory] - Comando de debug: item \"%s\" não está em debug_item_catalog" % item_id)


# Lista de ids sugeridos pro comando de debug, a partir de debug_item_catalog. Pula entradas null
# pelo mesmo motivo de _on_debug_give_item.
func _debug_item_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for item: ItemData in debug_item_catalog:
		if item == null:
			continue
		ids.append(String(item.id))
	return ids
