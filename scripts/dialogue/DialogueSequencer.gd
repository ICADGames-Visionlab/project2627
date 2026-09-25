# DialogueSequencer.gd — Fila de estágios animados (tween, espera, chamada) com "adiantar" (SPEC
# §8.3). Os tweens usam owner.create_tween(), que herda o process_mode do dono e congela com a
# pausa; as esperas usam SceneTreeTimer com process_always = false pelo mesmo motivo.
class_name DialogueSequencer
extends RefCounted

signal finished

var _owner: Node
var _stages: Array[Dictionary] = []
var _running: bool = false
var _current_tween: Tween
var _current_wait_skippable: bool = false
var _skip_requested: bool = false


func _init(owner: Node) -> void:
	_owner = owner


func add_tween_stage(build: Callable) -> void:
	_stages.append({ "kind": "tween", "build": build })


func add_wait_stage(seconds: float, skippable: bool) -> void:
	_stages.append({ "kind": "wait", "seconds": seconds, "skippable": skippable })


func add_call_stage(callable: Callable) -> void:
	_stages.append({ "kind": "call", "callable": callable })


func run() -> void:
	if _running:
		return
	_running = true
	_run_stages()


func is_running() -> bool:
	return _running


# Completa só o estágio corrente: Tween.custom_step(9999) ou encerra a espera se skippable.
func skip_current() -> void:
	if not _running:
		return
	if _current_tween != null and is_instance_valid(_current_tween) and _current_tween.is_valid():
		_current_tween.custom_step(9999.0)
	elif _current_wait_skippable:
		_skip_requested = true


func _run_stages() -> void:
	for stage: Dictionary in _stages:
		match stage["kind"]:
			"tween":
				_current_tween = _owner.create_tween()
				(stage["build"] as Callable).call(_current_tween)
				await _current_tween.finished
				_current_tween = null
			"wait":
				await _run_wait_stage(stage["seconds"], stage["skippable"])
			"call":
				(stage["callable"] as Callable).call()
	_stages.clear()
	_running = false
	finished.emit()


func _run_wait_stage(seconds: float, skippable: bool) -> void:
	_skip_requested = false
	_current_wait_skippable = skippable
	if seconds > 0.0:
		var timer: SceneTreeTimer = _owner.get_tree().create_timer(seconds, false, false, false)
		while not _skip_requested and timer.time_left > 0.0:
			await _owner.get_tree().process_frame
	_current_wait_skippable = false
