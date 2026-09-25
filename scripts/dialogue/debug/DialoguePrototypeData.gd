# DialoguePrototypeData.gd — Conversas sintéticas de debug (SPEC §15.6), no formato de Dictionary
# que o MemoryRunner consome (documentado em MemoryRunner.gd). Hoje só __stress_text.
class_name DialoguePrototypeData
extends RefCounted


static func get_content(conversation_id: StringName) -> Dictionary:
	if conversation_id == &"__stress_text":
		return _build_stress_text()
	return {}


# __stress_text (SPEC §15.6): a fala mais longa (sem BBCode) no idioma ativo agora, entre todas as
# chaves do translations.csv, com o nome de falante mais longo do roster. Recalculado a cada
# chamada (nunca cacheado) para refletir o idioma ativo no momento em que o teste é aberto.
static func _build_stress_text() -> Dictionary:
	var longest_key: String = ""
	var longest_length: int = -1
	for key: String in DialogueValidator.read_csv_rows().keys():
		var length: int = DialogueRevealTimer.strip_bbcode(TranslationServer.translate(key)).length()
		if length > longest_length:
			longest_length = length
			longest_key = key
	if longest_key == "":
		return {}
	return {
		"start": &"n1",
		"nodes": { &"n1": { "line": [&"STRESS_01", _longest_named_speaker_id(), longest_key] } },
	}


# Id do NPC do roster com o nome exibido mais longo, ou o narrador se o roster estiver vazio.
static func _longest_named_speaker_id() -> StringName:
	var roster: NPCRoster = load(DialogueCatalog.NPC_ROSTER_PATH)
	var best_id: StringName = &"narrator"
	var best_length: int = -1
	if roster != null:
		for definition: NPCDefinition in roster.npcs:
			if definition == null:
				continue
			var length: int = definition.get_display_name().length()
			if length > best_length:
				best_length = length
				best_id = definition.id
	return best_id
