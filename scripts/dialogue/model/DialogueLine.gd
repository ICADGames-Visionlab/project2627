# DialogueLine.gd — Uma fala dentro de uma etapa de conversa.
#
# Guarda ids e chaves, nunca texto traduzido: quem exibe chama tr(text_key) na hora de desenhar,
# para a troca de idioma com a conversa aberta redesenhar tudo sem reabrir o runner.
class_name DialogueLine
extends RefCounted

var line_id: StringName
var speaker_id: StringName
var text_key: String
var tags: PackedStringArray


func _init(p_line_id: StringName, p_speaker_id: StringName, p_text_key: String,
		p_tags: PackedStringArray = PackedStringArray()) -> void:
	line_id = p_line_id
	speaker_id = p_speaker_id
	text_key = p_text_key
	tags = p_tags


# Valor da tag "nome=valor". Tag sem "=" devolve "" quando existe; tag ausente devolve default.
func get_tag(tag_name: String, default: String = "") -> String:
	for tag: String in tags:
		if tag == tag_name:
			return ""
		if tag.begins_with(tag_name + "="):
			return tag.substr(tag_name.length() + 1)
	return default


func has_tag(tag_name: String) -> bool:
	for tag: String in tags:
		if tag == tag_name or tag.begins_with(tag_name + "="):
			return true
	return false


func is_narration() -> bool:
	return speaker_id == &""


func _to_string() -> String:
	return "DialogueLine(id=%s, falante=%s, texto=%s)" % [line_id, speaker_id, text_key]
