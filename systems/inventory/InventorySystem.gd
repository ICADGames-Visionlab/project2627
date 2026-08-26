# InventorySystem.gd — Dono do estado do inventário do jogador.
# Reage ao fato "produção coletada" e publica o fato "item entrou": nenhum dos dois sistemas
# conhece o outro. Esta é a única cadeia de dois saltos da validação, e é o limite — um evento
# pode gerar no máximo mais um.
class_name InventorySystem
extends Node

@export var max_amount_per_item: int = 999

var _items: Dictionary = {}


func _ready() -> void:
	EventBus.production_collected.connect(_on_production_collected)


# Adiciona itens ao inventário e publica o resultado consolidado.
# Devolve false quando o limite por item é ultrapassado.
func add_item(item_id: StringName, amount: int, source: StringName) -> bool:
	var current: int = get_amount(item_id)
	if current + amount > max_amount_per_item:
		print("[Inventory] - Item \"%s\" recusado: limite de %d atingido" % [item_id, max_amount_per_item])
		return false

	var total: int = current + amount
	_items[item_id] = total
	EventBus.item_added.emit(ItemTransactionEvent.new(item_id, amount, source, total))
	print("[Inventory] - Item \"%s\" x%d adicionado ao inventário (total %d)" % [item_id, amount, total])
	return true


# Remove itens do inventário. Devolve false se não houver quantidade suficiente.
#
# Repare na assimetria com add_item: a entrada publica um evento e a saída não. Não é
# esquecimento — é a regra "evento existe porque alguém escuta". Ninguém reage a remoção
# nesta validação, então o evento não existe. Ele nasce no dia em que houver um ouvinte.
func remove_item(item_id: StringName, amount: int) -> bool:
	var current: int = get_amount(item_id)
	if current < amount:
		return false

	var total: int = current - amount
	if total == 0:
		_items.erase(item_id)
	else:
		_items[item_id] = total
	print("[Inventory] - Item \"%s\" x%d removido do inventário (total %d)" % [item_id, amount, total])
	return true


func get_amount(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))


# Converte a coleta de produção em entrada de inventário.
# A fonte de produção não sabe que o inventário existe.
func _on_production_collected(event: ProductionCollectedEvent) -> void:
	add_item(event.product_id, event.amount, &"production")
