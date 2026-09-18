# MemoryRunner.gd — Lê uma conversa a partir de um Dictionary (SPEC §5.3). Roda todo roteiro .dlg
# (o DialogueScriptParser produz este formato) e as conversas sintéticas de debug
# (DialoguePrototypeData). Formato do conteúdo:
#
#   {
#       "start": &"n1",
#       "nodes": {
#           &"n1": {
#               "line": [line_id, speaker_id, text_key, tags (opcional)],
#               "choices": [
#                   { "id": &"...", "text": "CHAVE", "next": &"n2" },
#                   # opcionais: "tag", "if_flag", "show_disabled", "reason", "grant"
#               ],
#           },
#           &"n2": { "line": [...], "next": &"n3", "advance": "auto" },
#       },
#   }
#
# Nó sem "choices" avança por "next" (com Continuar, ou sozinho se "advance" for "auto"); sem
# "next", ou com "next" = &"END", encerra a conversa.
class_name MemoryRunner
extends DialogueRunner

var _content: Dictionary
var _choice_meta: Dictionary  # choice_id -> { "next": StringName, "grant": StringName }
var _pending_advance_target: StringName = &""


func _init(content: Dictionary) -> void:
	_content = content


func _start(start_node_id: StringName) -> void:
	var node_id: StringName = start_node_id if start_node_id != &"" else _content.get("start", &"")
	_goto(node_id)


func _advance() -> void:
	_goto(_pending_advance_target)


func _choose(choice_id: StringName) -> void:
	var meta: Dictionary = _choice_meta.get(choice_id, {})
	var grant: StringName = meta.get("grant", &"")
	if grant != &"" and game_state != null:
		game_state.grant_flag(String(grant))
	_goto(meta.get("next", &""))


func get_node_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for id: StringName in (_content.get("nodes", {}) as Dictionary).keys():
		ids.append(String(id))
	return ids


func _goto(node_id: StringName) -> void:
	if node_id == &"END":
		_emit_step(DialogueStep.new([] as Array[DialogueLine], [_end_choice()] as Array[DialogueChoice],
			DialogueStep.AdvanceMode.CONTINUE, true, &"END"))
		return
	var nodes: Dictionary = _content.get("nodes", {})
	if not nodes.has(node_id):
		failed.emit("[MemoryRunner] Nó \"%s\" não existe" % node_id)
		return
	_build_and_emit(node_id, nodes[node_id])


func _build_and_emit(node_id: StringName, node: Dictionary) -> void:
	var lines: Array[DialogueLine] = []
	if node.has("line"):
		var raw: Array = node["line"]
		var tags: PackedStringArray = raw[3] if raw.size() > 3 else PackedStringArray()
		lines.append(DialogueLine.new(raw[0], raw[1], raw[2], tags))

	var next_id: StringName = node.get("next", &"")
	var raw_choices: Array = node.get("choices", [])
	var choices: Array[DialogueChoice] = []
	var is_end: bool = false
	var advance_mode: DialogueStep.AdvanceMode = DialogueStep.AdvanceMode.CONTINUE

	if not raw_choices.is_empty():
		for c: Dictionary in raw_choices:
			var choice_id: StringName = c["id"]
			var is_available: bool = true
			if c.has("if_flag") and game_state != null:
				is_available = game_state.has_flag(String(c["if_flag"]))
			choices.append(DialogueChoice.new(
				choice_id, c["text"], c.get("tag", ""), is_available,
				c.get("show_disabled", false), c.get("reason", ""), false, false, true
			))
			_choice_meta[choice_id] = { "next": c.get("next", &""), "grant": c.get("grant", &"") }
	else:
		is_end = (next_id == &"" or next_id == &"END")
		_pending_advance_target = next_id
		if is_end:
			choices.append(_end_choice())
		elif String(node.get("advance", "continue")) == "auto":
			advance_mode = DialogueStep.AdvanceMode.AUTO
		else:
			choices.append(DialogueChoice.new(&"__continue", "DIALOGUE_CONTINUE", "", true, false, "", false, true, false))

	_emit_step(DialogueStep.new(lines, choices, advance_mode, is_end, node_id))


func _end_choice() -> DialogueChoice:
	return DialogueChoice.new(&"__end", "DIALOGUE_END", "", true, false, "", false, true, false)
