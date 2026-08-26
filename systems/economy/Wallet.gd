# Wallet.gd — Dono do estado de ouro do jogador.
# Não escuta nada: apenas publica a mudança. Quem chega depois consulta current_gold pelo
# grupo "wallet" em vez de esperar a próxima emissão.
class_name Wallet
extends Node

@export var starting_gold: int = 50

var current_gold: int = 0


func _enter_tree() -> void:
	add_to_group(&"wallet")


func _ready() -> void:
	current_gold = starting_gold


# Aplica uma variação de ouro e publica o valor novo junto do delta.
# O delta acompanha o valor porque vários ouvintes precisam da variação, não do total.
func add_gold(delta: int) -> void:
	if delta == 0:
		return
	current_gold = maxi(current_gold + delta, 0)
	EventBus.gold_changed.emit(current_gold, delta)
	print("[Economy] - Ouro alterado em %d (total %d)" % [delta, current_gold])
