# DialogueSpeaker.gd — Falante de diálogo que não é o jogador, um NPC do roster nem uma cabeça de
# insight (ex.: um narrador). Carregado pelo DialogueCatalog a partir de
# res://resources/dialogue/speakers/<id>.tres (SPEC §6.3).
@tool
class_name DialogueSpeaker
extends Resource

@export var id: StringName = &""
@export var name_key: String = ""
@export var name_color: Color = Color.WHITE:
	set(value):
		name_color = value
		_refresh_summary()

## Só leitura: contraste no pior caso contra dialogue_style.tres. Editar aqui não faz nada.
@export_multiline var resumo: String = ""


func _init() -> void:
	_refresh_summary()


func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY


func _refresh_summary() -> void:
	var style: DialogueStyle = load("res://resources/dialogue/dialogue_style.tres")
	if style == null:
		resumo = "Sem dialogue_style.tres padrão para calcular o contraste."
		notify_property_list_changed()
		return
	var ratio: float = DialogueContrast.worst_case_ratio(name_color, 1.0, style, 0.82)
	if ratio >= style.min_contrast_ratio:
		resumo = "Contraste no pior caso: %.1f:1 ✓" % ratio
	else:
		resumo = "ATENÇÃO: %.1f:1 (mínimo %.1f:1)" % [ratio, style.min_contrast_ratio]
	notify_property_list_changed()
