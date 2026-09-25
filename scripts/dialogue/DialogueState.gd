# DialogueState.gd — Escolhas e nós já visitados, sobrevivendo à troca de cena sem Autoload
# (V9 do SPEC): tudo "static". Se o Lead preferir Autoload no futuro, a API muda só de forma
# (static -> instância), não de assinatura.
class_name DialogueState
extends RefCounted

const SAVE_KEY: String = "dialogue"
const CHOSEN_KEY: String = "chosen"
const VISITED_KEY: String = "visited"

static var save_slot_path: String = ""  # vazio = SaveManager.save_file_1
static var autosave_enabled: bool = true

static var _chosen: Dictionary = {}
static var _visited: Dictionary = {}
static var _loaded: bool = false
static var _autosave_queued: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_from_slot()


static func was_chosen(choice_id: StringName) -> bool:
	ensure_loaded()
	return _chosen.has(choice_id)


static func mark_chosen(choice_id: StringName) -> void:
	ensure_loaded()
	if _chosen.has(choice_id):
		return
	_chosen[choice_id] = true
	_queue_autosave()


static func was_visited(node_id: StringName) -> bool:
	ensure_loaded()
	return _visited.has(node_id)


static func mark_visited(node_id: StringName) -> void:
	ensure_loaded()
	if _visited.has(node_id):
		return
	_visited[node_id] = true
	_queue_autosave()


static func reset_choices() -> void:
	ensure_loaded()
	_chosen.clear()
	_visited.clear()
	_queue_autosave()


static func to_dict() -> Dictionary:
	var chosen_ids: Array[String] = []
	for id: StringName in _chosen:
		chosen_ids.append(String(id))
	chosen_ids.sort()
	var visited_ids: Array[String] = []
	for id: StringName in _visited:
		visited_ids.append(String(id))
	visited_ids.sort()
	return { CHOSEN_KEY: chosen_ids, VISITED_KEY: visited_ids }


# StringName(str(x)): o save serializa por JSON, que devolve String, nunca StringName de volta.
static func from_dict(data: Dictionary) -> void:
	_chosen.clear()
	_visited.clear()
	for raw_id: Variant in data.get(CHOSEN_KEY, []):
		_chosen[StringName(str(raw_id))] = true
	for raw_id: Variant in data.get(VISITED_KEY, []):
		_visited[StringName(str(raw_id))] = true
	_loaded = true


static func _resolve_slot_path() -> String:
	return save_slot_path if save_slot_path != "" else SaveManager.save_file_1


# Carrega o resto do arquivo e regrava só a própria chave: o save é de todos os sistemas.
static func save_to_slot() -> void:
	var path: String = _resolve_slot_path()
	var data: Dictionary = SaveManager.load_game(path)
	data[SAVE_KEY] = to_dict()
	SaveManager.save_game(data, path)


static func load_from_slot() -> void:
	var path: String = _resolve_slot_path()
	var data: Dictionary = SaveManager.load_game(path)
	from_dict(data.get(SAVE_KEY, {}))


static func _queue_autosave() -> void:
	if not autosave_enabled or _autosave_queued:
		return
	_autosave_queued = true
	Engine.get_main_loop().process_frame.connect(Callable(DialogueState, "_flush_autosave"), CONNECT_ONE_SHOT)


static func _flush_autosave() -> void:
	_autosave_queued = false
	save_to_slot()
