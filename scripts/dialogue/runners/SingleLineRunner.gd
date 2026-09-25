# SingleLineRunner.gd — Ponte dos insights de personagem para a tela de diálogo (SPEC §5.5): uma
# única fala de uma cabeça, com "Encerrar" como única saída. Não passa por DialogueState (não marca
# visitado nem escolhido) porque uma fala de insight não é uma conversa navegável.
class_name SingleLineRunner
extends DialogueRunner

var _head_id: StringName
var _text_key: String


func _init(head_id: StringName, text_key: String) -> void:
	_head_id = head_id
	_text_key = text_key
	conversation_id = StringName("insight:" + text_key)


func _start(_start_node_id: StringName) -> void:
	var line: DialogueLine = DialogueLine.new(
		StringName("insight:" + _text_key), StringName("head:" + String(_head_id)), _text_key
	)
	var end_choice: DialogueChoice = DialogueChoice.new(
		&"__end", "DIALOGUE_END", "", true, false, "", false, true, false
	)
	var step: DialogueStep = DialogueStep.new(
		[line], [end_choice], DialogueStep.AdvanceMode.CONTINUE, true, conversation_id
	)
	call_deferred("_deferred_emit_step", step)
