# DialogueExchangeTracker.gd — Divide o log em "troca atual" (acesa) e "trocas passadas"
# (esmaecidas). Ver SPEC §9.3 para o exemplo completo de como o índice avança a cada escolha.
class_name DialogueExchangeTracker
extends RefCounted

var current_exchange: int = 0


# Chamado DEPOIS de adicionar a fala VOCÊ ao log: ela fecha a troca a que pertence.
func end_exchange() -> void:
	current_exchange += 1


func is_past(entry_exchange: int) -> bool:
	return entry_exchange < current_exchange - 1
