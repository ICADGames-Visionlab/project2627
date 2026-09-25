# ItemStack.gd — quantidade de um ItemData guardada numa única pilha do inventário.
#
# RefCounted com dois campos em vez de um Dictionary solto de propósito: o inventário precisa
# mudar "amount" em cada pickup/drop/destroy sem perder a referência ao ItemData dono, e tipar os
# dois campos deixa isso explícito — mesma lógica dos payloads de evento documentados em
# docs/event_bus.md ("Regras de parâmetro": nada de Dictionary como "saco de dados" sem tipo).
class_name ItemStack
extends RefCounted

var item: ItemData
var amount: int


func _init(p_item: ItemData, p_amount: int) -> void:
	item = p_item
	amount = p_amount


# Sem isso, imprimir uma pilha no console (debug) mostra "<RefCounted#...>" e não ajuda em nada.
func _to_string() -> String:
	return "ItemStack(%s x%d)" % [item.id if item != null else "?", amount]
