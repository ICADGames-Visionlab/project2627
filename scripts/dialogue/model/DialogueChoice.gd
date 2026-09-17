# DialogueChoice.gd — Uma opção oferecida ao final de uma fala.
#
# Não guarda índice: a numeração exibida é responsabilidade da UI (DialogueChoiceLayout), porque só
# ela sabe quais opções estão visíveis no momento.
class_name DialogueChoice
extends RefCounted

var choice_id: StringName
var text_key: String
var tag_key: String
var is_available: bool
var show_when_unavailable: bool
var unavailable_reason_key: String
var was_chosen_before: bool
var is_system: bool
var logs_as_player_line: bool


func _init(p_choice_id: StringName, p_text_key: String, p_tag_key: String, p_is_available: bool,
		p_show_when_unavailable: bool, p_unavailable_reason_key: String, p_was_chosen_before: bool,
		p_is_system: bool, p_logs_as_player_line: bool) -> void:
	choice_id = p_choice_id
	text_key = p_text_key
	tag_key = p_tag_key
	is_available = p_is_available
	show_when_unavailable = p_show_when_unavailable
	unavailable_reason_key = p_unavailable_reason_key
	was_chosen_before = p_was_chosen_before
	is_system = p_is_system
	logs_as_player_line = p_logs_as_player_line


func _to_string() -> String:
	return "DialogueChoice(id=%s, disponivel=%s, sistema=%s)" % [choice_id, is_available, is_system]
