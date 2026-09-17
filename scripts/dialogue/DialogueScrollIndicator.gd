# DialogueScrollIndicator.gd — Botão flutuante "↓" com contador (SPEC §7.6). Não conhece o
# DialogueLog: a tela conecta new_lines_pending_changed a set_pending_count e pressed ao próprio
# scroll_to_end, para este nó não precisar de referência cruzada.
class_name DialogueScrollIndicator
extends Button


func _ready() -> void:
	visible = false


func set_pending_count(count: int) -> void:
	visible = count > 0
	if count > 0:
		text = "↓ " + (tr(&"DIALOGUE_NEW_LINES") % count)
