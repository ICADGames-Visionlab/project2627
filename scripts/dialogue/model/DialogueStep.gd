# DialogueStep.gd — O que um runner entrega de cada vez que a conversa avança.
#
# Toda etapa tem no máximo uma fala (SPEC §4.3): uma sequência de falas vira várias etapas
# seguidas, para a tela ter sempre um único caminho de animação por etapa.
class_name DialogueStep
extends RefCounted

enum AdvanceMode { CONTINUE, AUTO }

var lines: Array[DialogueLine]
var choices: Array[DialogueChoice]
var advance_mode: AdvanceMode
var is_end: bool
var node_id: StringName


func _init(p_lines: Array[DialogueLine], p_choices: Array[DialogueChoice],
		p_advance_mode: AdvanceMode, p_is_end: bool, p_node_id: StringName) -> void:
	lines = p_lines
	choices = p_choices
	advance_mode = p_advance_mode
	is_end = p_is_end
	node_id = p_node_id


func _to_string() -> String:
	return "DialogueStep(no=%s, falas=%d, escolhas=%d, fim=%s)" % [
		node_id, lines.size(), choices.size(), is_end
	]
