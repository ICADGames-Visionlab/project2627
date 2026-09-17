# DialogueInputGate.gd — Trava de entrada depois de uma confirmação. Recebe o tempo de fora (a
# tela usa um relógio próprio que só anda enquanto ela processa) para a pausa não "gastar" a trava.
class_name DialogueInputGate
extends RefCounted

var _unlock_at: float = -1.0


func arm(now_seconds: float, lock_seconds: float) -> void:
	_unlock_at = now_seconds + lock_seconds


func is_locked(now_seconds: float) -> bool:
	return now_seconds < _unlock_at


func disarm() -> void:
	_unlock_at = -1.0
