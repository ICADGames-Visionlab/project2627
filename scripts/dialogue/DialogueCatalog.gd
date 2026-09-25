# DialogueCatalog.gd — Acha o runner certo para uma conversa e monta o resolvedor de falantes
# padrão (SPEC §5.2, §9.1). D1 decidido: sem o addon Godot Dialogue Manager. Roteiro real é um
# arquivo de texto em res://dialogue/<id>.dlg (formato próprio, ver DialogueScriptParser.gd),
# convertido pro mesmo Dictionary do MemoryRunner — não existe um "runner do addon" nem nunca vai
# existir.
class_name DialogueCatalog
extends RefCounted

const NPC_ROSTER_PATH: String = "res://resources/npcs/npc_roster.tres"
const SPEAKERS_DIR: String = "res://resources/dialogue/speakers"
const SCRIPTS_DIR: String = "res://dialogue"

static var _speakers_cache: Dictionary = {}
static var _speakers_loaded: bool = false


# Prioridade (SPEC §5.2): conversa sintética de debug (__stress_*) -> MemoryRunner com o
# conteúdo do DialoguePrototypeData; senão, procura res://dialogue/<id>.dlg e faz o parser. Sem
# addon: não há terceira opção.
static func create_runner(conversation_id: StringName) -> DialogueRunner:
	var id_str: String = String(conversation_id)
	if id_str.begins_with("__stress_"):
		var content: Dictionary = DialoguePrototypeData.get_content(conversation_id)
		if content.is_empty():
			push_error("[Dialogue] - Conversa sintética \"%s\" não encontrada" % conversation_id)
			return null
		return MemoryRunner.new(content)
	return _create_script_runner(conversation_id)


static func get_script_path(conversation_id: StringName) -> String:
	return "%s/%s.dlg" % [SCRIPTS_DIR, conversation_id]


# O elenco declarado no roteiro (linha "participants:"), sem montar a conversa. Usado pela
# NPCInteraction, que precisa saber quem mais entra na roda antes de a tela abrir. Conversa
# sintética ou roteiro inexistente não têm elenco declarado.
static func read_participants(conversation_id: StringName) -> Array[StringName]:
	var path: String = get_script_path(conversation_id)
	if not FileAccess.file_exists(path):
		return []
	return DialogueScriptParser.parse_participants(FileAccess.get_file_as_string(path))


# O elenco de NPCs de uma conversa: os que o roteiro declara, mais quem a puxou quando ele não está
# na lista. Os dois caminhos que precisam do elenco (a abordagem, que lê o arquivo, e a tela, que já
# tem o roteiro parseado) passam por aqui para não divergirem nessa regra.
static func cast_for(declared: Array[StringName], initiator_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = declared.duplicate()
	if initiator_id != &"" and not ids.has(initiator_id):
		ids.append(initiator_id)
	return ids


static func _create_script_runner(conversation_id: StringName) -> DialogueRunner:
	var path: String = get_script_path(conversation_id)
	if not FileAccess.file_exists(path):
		push_error("[Dialogue] - Roteiro \"%s\" não encontrado em \"%s\"" % [conversation_id, path])
		return null
	var source: String = FileAccess.get_file_as_string(path)
	var result: DialogueScriptParser.Result = DialogueScriptParser.parse(source, conversation_id)
	if not result.ok():
		for error: DialogueScriptParser.ParseError in result.errors:
			push_error("[Dialogue] - %s: %s" % [path, error])
		return null
	return MemoryRunner.new(result.content)


# Todos os arquivos .dlg em res://dialogue/, sem a extensão — usado por "Validar conversas" e pelas
# sugestões dos comandos de debug (SPEC §15.2).
static func list_script_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(SCRIPTS_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".dlg"):
			ids.append(file_name.trim_suffix(".dlg"))
		file_name = dir.get_next()
	dir.list_dir_end()
	return ids


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
