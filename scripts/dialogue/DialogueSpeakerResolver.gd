# DialogueSpeakerResolver.gd — De um speaker_id para nome e cor exibidos (SPEC §9.1, com a
# correção V3: "player" é sempre VOCÊ; "head:<id>" força a busca no HeadRegistry). Puro e com
# dependências injetáveis, para o autoteste passar dublês em vez de NPCRoster/HeadRegistry reais.
class_name DialogueSpeakerResolver
extends RefCounted

enum Kind { PLAYER, NPC, HEAD, SPEAKER, NARRATION, UNKNOWN }


class Resolved:
	var kind: Kind
	var name_key: String
	var color: Color
	var is_blocked: bool

	func _init(p_kind: Kind, p_name_key: String, p_color: Color, p_is_blocked: bool = false) -> void:
		kind = p_kind
		name_key = p_name_key
		color = p_color
		is_blocked = p_is_blocked


var _roster: NPCRoster
var _get_head: Callable
var _has_head: Callable
var _speakers: Dictionary
var _style: DialogueStyle
var _warned_unknown: Dictionary = {}


func _init(p_roster: NPCRoster, p_heads: Callable, p_has_head: Callable, p_speakers: Dictionary,
		p_style: DialogueStyle) -> void:
	_roster = p_roster
	_get_head = p_heads
	_has_head = p_has_head
	_speakers = p_speakers
	_style = p_style


func resolve(speaker_id: StringName) -> Resolved:
	if speaker_id == &"":
		return Resolved.new(Kind.NARRATION, "", _style.narration_color)
	if speaker_id == &"player":
		return Resolved.new(Kind.PLAYER, "DIALOGUE_SPEAKER_PLAYER", _style.player_name_color)

	var id_str: String = String(speaker_id)
	if id_str.begins_with("head:"):
		var head_id: StringName = StringName(id_str.substr(5))
		var forced_head: Resolved = _head_resolved(head_id)
		return forced_head if forced_head != null else _unknown(speaker_id)

	if _roster != null:
		var npc: NPCDefinition = _roster.find(speaker_id)
		if npc != null:
			return Resolved.new(Kind.NPC, String(npc.name_key), npc.dialogue_color)

	var head_resolved: Resolved = _head_resolved(speaker_id)
	if head_resolved != null:
		return head_resolved

	if _speakers.has(speaker_id):
		var speaker: DialogueSpeaker = _speakers[speaker_id]
		return Resolved.new(Kind.SPEAKER, speaker.name_key, speaker.name_color)

	return _unknown(speaker_id)


func _head_resolved(head_id: StringName) -> Resolved:
	var head: Variant = _get_head.call(head_id)
	if head == null:
		return null
	return Resolved.new(Kind.HEAD, head.display_name_key, head.color, not _has_head.call(head_id))


func _unknown(speaker_id: StringName) -> Resolved:
	if not _warned_unknown.has(speaker_id):
		_warned_unknown[speaker_id] = true
		push_warning("[Dialogue] - AVISO: falante \"%s\" desconhecido" % speaker_id)
	return Resolved.new(Kind.UNKNOWN, String(speaker_id), _style.fallback_speaker_color)
