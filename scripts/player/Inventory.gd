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

# Emitido quando uma quantidade de um item entra no inventário (pickup ou comando de debug).
# Ouvinte: InventoryUI, para redesenhar o slot.
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
# Precisa ser maior que a soma dos dois raios de colisão (CapsuleShape2D do Player, radius 14, +
# CircleShape2D do ItemPickup, radius 24 — ver Player.tscn e ItemPickup.tscn). Sem essa folga, o
# pickup nasce sobrepondo o colisor do próprio dono e a Area2D dele dispara o pickup de volta no
# mesmo frame em que foi largado.
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
# de "cheio" ainda, ver docs/Inventory.md). Público: chamado pelo ItemPickup ao ser coletado, e
# pelo comando de debug "dar_evidencia".
func add_item(item: ItemData, amount: int = 1) -> void:
	if item == null or amount <= 0:
		return

	var stack: ItemStack = _stacks.get(item.id)
	if stack == null:
		stack = ItemStack.new(item, 0)
		_stacks[item.id] = stack

	stack.amount = mini(stack.amount + amount, item.max_stack)
	item_added.emit(item, amount)
	print("[Inventory] - Item \"%s\" adicionado (x%d, total %d)" % [item.id, amount, stack.amount])


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
# inventário. Devolve false (sem efeito nenhum) se não houver unidades suficientes.
func drop_item(item_id: StringName, amount: int = 1) -> bool:
	var stack: ItemStack = _stacks.get(item_id)
	if stack == null or amount <= 0 or stack.amount < amount:
		return false

	var item: ItemData = stack.item
	_remove_from_stack(stack, amount)

	var scene: PackedScene = pickup_scene
	if scene == null:
		scene = load(PICKUP_SCENE_PATH) as PackedScene
	var pickup: ItemPickup = scene.instantiate() as ItemPickup
	pickup.item = item
	pickup.amount = amount
	pickup.global_position = _get_drop_position()
	get_tree().current_scene.add_child(pickup)

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
func _on_debug_give_item(item_id: String, amount: int) -> void:
	for item: ItemData in debug_item_catalog:
		if String(item.id) == item_id:
			add_item(item, amount)
			return
	push_warning("[Inventory] - Comando de debug: item \"%s\" não está em debug_item_catalog" % item_id)


# Lista de ids sugeridos pro comando de debug, a partir de debug_item_catalog.
func _debug_item_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for item: ItemData in debug_item_catalog:
		ids.append(String(item.id))
	return ids
