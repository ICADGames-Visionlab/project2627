# WorldClock.gd — Relógio do mundo: avança o dia e anuncia as transições do ciclo.
# É o dono do estado "dia atual"; o bus só transporta a mudança.
# Fica no grupo "world_clock" para que sistemas criados depois consultem o valor inicial
# em vez de esperar a próxima emissão.
class_name WorldClock
extends Node

# Duração de um dia de jogo em segundos reais.
@export var day_duration_seconds: float = 300.0
# Fração do dia a partir da qual anoitece.
@export var night_starts_at_ratio: float = 0.75
# Anuncia o dia inicial ao entrar em cena. A emissão é diferida de propósito (ver _ready).
@export var announce_initial_day: bool = true

var current_day: int = 1

var _elapsed: float = 0.0
var _night_announced: bool = false


func _enter_tree() -> void:
	# Registro no grupo acontece em _enter_tree, e não em _ready, porque a engine propaga
	# _enter_tree para toda a árvore antes de qualquer _ready: assim nenhum sistema consegue
	# rodar seu _ready antes do relógio existir para consulta.
	add_to_group(&"world_clock")


func _ready() -> void:
	# A primeira emissão é adiada de propósito: em _ready os demais sistemas ainda não
	# conectaram seus listeners, e um day_started emitido agora não seria ouvido por ninguém.
	if announce_initial_day:
		EventBus.day_started.emit.call_deferred(current_day)


func _process(delta: float) -> void:
	_elapsed += delta
	if not _night_announced and _elapsed >= day_duration_seconds * night_starts_at_ratio:
		_night_announced = true
		EventBus.night_started.emit()
	if _elapsed >= day_duration_seconds:
		advance_day()


# Fecha o dia corrente e abre o próximo. Nenhum listener pode depender da ordem em que os
# outros listeners deste mesmo evento rodam.
func advance_day() -> void:
	current_day += 1
	_elapsed = 0.0
	_night_announced = false
	EventBus.day_started.emit(current_day)
	print("[World] - Dia %d iniciado" % current_day)
