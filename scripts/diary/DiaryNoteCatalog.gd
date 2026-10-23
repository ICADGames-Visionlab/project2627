## DiaryNoteCatalog - acha as anotações pessoais (DiaryNote) varrendo res://resources/diary/notas/.
##
## Mesmo jeito do ItemCatalog: dado estático, sem estado de partida, então funções static com cache
## bastam. O save guarda só o id da anotação, e o diário volta do id pro recurso por aqui.
class_name DiaryNoteCatalog
extends RefCounted

## Espaço para constantes

const NOTES_DIR: String = "res://resources/diary/notas/"

## Espaço para variáveis

static var _notes: Dictionary[StringName, DiaryNote] = {}
static var _loaded: bool = false

## Espaço para funções personalizadas

static func find_note(note_id: StringName) -> DiaryNote:
	_ensure_loaded()
	return _notes.get(note_id)


# Todas as anotações, em ordem de id (estável entre execuções).
static func load_all() -> Array[DiaryNote]:
	_ensure_loaded()
	var result: Array[DiaryNote] = []
	for note: DiaryNote in _notes.values():
		result.append(note)
	result.sort_custom(func(left: DiaryNote, right: DiaryNote) -> bool:
		return String(left.id) < String(right.id))
	return result


# As anotações que um fato do jogo dispara (ver DiaryNote.matches).
static func find_triggered(trigger: DiaryNote.Trigger, trigger_id: StringName = &"") -> Array[DiaryNote]:
	var result: Array[DiaryNote] = []
	for note: DiaryNote in load_all():
		if note.matches(trigger, trigger_id):
			result.append(note)
	return result


static func clear_cache() -> void:
	_notes.clear()
	_loaded = false


# O trim_suffix(".remap") é o mesmo cuidado do ItemCatalog: na build exportada os .tres viram
# .tres.remap, e sem ele a varredura funcionaria no editor e voltaria vazia no jogo.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not DirAccess.dir_exists_absolute(NOTES_DIR):
		push_warning("[Diary] - AVISO: pasta de anotações \"%s\" não existe" % NOTES_DIR)
		return
	for file_name: String in DirAccess.get_files_at(NOTES_DIR):
		var clean_name: String = file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres") and not clean_name.ends_with(".res"):
			continue
		var note: DiaryNote = ResourceLoader.load(NOTES_DIR + clean_name) as DiaryNote
		if note == null or note.id == &"":
			push_warning("[Diary] - AVISO: \"%s\" não é uma DiaryNote com id" % (NOTES_DIR + clean_name))
			continue
		if _notes.has(note.id):
			push_warning("[Diary] - AVISO: id de anotação repetido: \"%s\"" % note.id)
			continue
		_notes[note.id] = note
	print("[Diary] - Catálogo de anotações: %d anotação(ões) em %s" % [_notes.size(), NOTES_DIR])
