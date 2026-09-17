# DialogueCatalog.gd — Acha o runner certo para uma conversa e monta o resolvedor de falantes
# padrão (SPEC §5.2, §9.1). A indexação de roteiros reais (res://dialogue/**/*.dialogue) entra
# junto com o addon Godot Dialogue Manager; até lá, só as conversas sintéticas de debug resolvem.
class_name DialogueCatalog
extends RefCounted

const NPC_ROSTER_PATH: String = "res://resources/npcs/npc_roster.tres"
const SPEAKERS_DIR: String = "res://resources/dialogue/speakers"

static var _speakers_cache: Dictionary = {}
static var _speakers_loaded: bool = false


# Prioridade (SPEC §5.2): conversa sintética de debug (__proto_*, __stress_*) -> MemoryRunner;
# roteiro real -> DialogueManagerRunner (ainda não instalado); senão null, com erro no log.
static func create_runner(conversation_id: StringName) -> DialogueRunner:
	var id_str: String = String(conversation_id)
	if id_str.begins_with("__proto_") or id_str.begins_with("__stress_"):
		var content: Dictionary = DialoguePrototypeData.get_content(conversation_id)
		if content.is_empty():
			push_error("[Dialogue] - Conversa sintética \"%s\" não encontrada" % conversation_id)
			return null
		return MemoryRunner.new(content)
	push_error("[Dialogue] - Nenhum runner disponível para \"%s\" (roteiro real exige o addon Godot Dialogue Manager)" % conversation_id)
	return null


static func make_default_resolver(style: DialogueStyle) -> DialogueSpeakerResolver:
	var roster: NPCRoster = load(NPC_ROSTER_PATH)
	return DialogueSpeakerResolver.new(
		roster,
		Callable(HeadRegistry, "get_head"),
		Callable(HeadRegistry, "has_head"),
		get_speakers(),
		style
	)


# Todos os DialogueSpeaker do projeto (res://resources/dialogue/speakers/), id -> recurso. Usado
# pelo resolvedor padrão e por "Validar estilo" (SPEC §15.3).
static func get_speakers() -> Dictionary:
	if _speakers_loaded:
		return _speakers_cache
	_speakers_loaded = true
	_speakers_cache = {}
	var dir: DirAccess = DirAccess.open(SPEAKERS_DIR)
	if dir == null:
		return _speakers_cache
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var speaker: DialogueSpeaker = load(SPEAKERS_DIR + "/" + file_name)
			if speaker != null and speaker.id != &"":
				_speakers_cache[speaker.id] = speaker
		file_name = dir.get_next()
	dir.list_dir_end()
	return _speakers_cache
