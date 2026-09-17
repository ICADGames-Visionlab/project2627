# DialoguePrototypeData.gd — Conversa fixa __proto_garte (SPEC §15.6), a mesma do exemplo de
# roteiro do PRD/SPEC §5.4.5, só que em formato de Dictionary para o MemoryRunner. Cobre fala,
# opção com tag, SHOW_DISABLED, grant de flag e fim — o que o critério de aceite da fase 1 pede.
class_name DialoguePrototypeData
extends RefCounted

const _PROTO_GARTE: Dictionary = {
	"start": &"n1",
	"nodes": {
		&"n1": {
			"line": [&"GARTE_DIVIDA_01", &"npc_garte", "DEMO_GARTE_01"],
			"choices": [
				{ "id": &"c_real", "text": "DEMO_OPT_REAL", "next": &"n_real" },
				{
					"id": &"c_auth", "text": "DEMO_OPT_AUTH", "tag": "DIALOGUE_TAG_AUTHORITY",
					"if_flag": &"badge_found", "show_disabled": true, "reason": "DEMO_REASON_BADGE",
					"grant": &"garte_intimidated", "next": &"n_auth",
				},
				{ "id": &"c_exit", "text": "DEMO_OPT_EXIT", "next": &"END" },
			],
		},
		&"n_real": { "line": [&"GARTE_DIVIDA_02", &"npc_garte", "DEMO_GARTE_02"] },
		&"n_auth": { "line": [&"GARTE_DIVIDA_03", &"npc_garte", "DEMO_GARTE_03"] },
	},
}


static func get_content(conversation_id: StringName) -> Dictionary:
	if conversation_id == &"__proto_garte":
		return _PROTO_GARTE
	if conversation_id == &"__stress_text":
		return _build_stress_text()
	return {}


# __stress_text (SPEC §15.6): a fala mais longa (sem BBCode) no idioma ativo agora, entre as chaves
# já usadas pelas conversas sintéticas, com o nome de falante mais longo do roster. Recalculado a
# cada chamada (nunca cacheado) para refletir o idioma ativo no momento em que o teste é aberto.
static func _build_stress_text() -> Dictionary:
	var longest_key: String = ""
	var longest_length: int = -1
	for key: String in _collect_keys():
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


# Chaves de texto já usadas nas conversas sintéticas (falas e opções de _PROTO_GARTE).
static func _collect_keys() -> PackedStringArray:
	var keys: PackedStringArray = []
	for node: Dictionary in (_PROTO_GARTE.get("nodes", {}) as Dictionary).values():
		if node.has("line"):
			keys.append((node["line"] as Array)[2])
		for choice: Dictionary in (node.get("choices", []) as Array):
			if choice.has("text"):
				keys.append(choice["text"])
			if choice.has("reason"):
				keys.append(choice["reason"])
	return keys


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
