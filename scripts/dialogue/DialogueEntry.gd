# DialogueEntry.gd — Uma fala dentro do log (SPEC §7.4). Duas colunas (Name + Text) para hanging
# indent determinístico; nome longo demais faz a Row virar vertical (Row é um BoxContainer puro,
# então alternar vertical/horizontal é só um bool, sem trocar de nó).
class_name DialogueEntry
extends MarginContainer

signal reveal_finished

enum EntryState { ENTERING, CURRENT, PAST }

static var show_ids: bool = false

@onready var _row: BoxContainer = $Row
@onready var _name_label: RichTextLabel = $Row/Name
@onready var _text_label: RichTextLabel = $Row/Text
@onready var _id_label: Label = $Row/IdLabel

var exchange_index: int = 0

var _style: DialogueStyle
var _line: DialogueLine
var _resolved: DialogueSpeakerResolver.Resolved
var _state: EntryState = EntryState.ENTERING
var _reveal_schedule: PackedFloat32Array = PackedFloat32Array()
var _reveal_elapsed: float = 0.0
var _revealing: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	resized.connect(_update_layout_mode)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_process(false)


func setup(line: DialogueLine, resolved: DialogueSpeakerResolver.Resolved, p_exchange_index: int,
		style: DialogueStyle) -> void:
	_line = line
	_resolved = resolved
	_style = style
	exchange_index = p_exchange_index
	modulate.a = 0.0
	_id_label.text = String(line.line_id)
	_id_label.visible = show_ids
	refresh()


# Reconstrói o texto de tudo (troca de idioma, escala, fonte). Cor sempre por push_color, nunca por
# BBCode vindo do GD.
func refresh() -> void:
	if _line == null:
		return
	var content: String = _sanitized_text()
	_text_label.clear()
	if _line.is_narration():
		_name_label.visible = false
		_text_label.push_color(_style.narration_color)
		_text_label.push_italics()
		_text_label.append_text(content)
		_text_label.pop()
		_text_label.pop()
	else:
		_name_label.visible = true
		_name_label.clear()
		_name_label.push_color(_resolved.color)
		_name_label.append_text("[b]%s[/b]%s" % [tr(_resolved.name_key).to_upper(), tr(&"DIALOGUE_SPEAKER_SEPARATOR")])
		_name_label.pop()
		_text_label.push_color(_style.text_color)
		_text_label.append_text(content)
		_text_label.pop()
	call_deferred("_update_layout_mode")


func play_enter(duration: float) -> void:
	var target_y: float = position.y
	modulate.a = 0.0
	position.y = target_y + _style.entry_slide_px
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, duration)
	tween.tween_property(self, "position:y", target_y, duration)


func set_past(is_past: bool) -> void:
	_state = EntryState.PAST if is_past else EntryState.CURRENT
	var target_alpha: float = _style.past_alpha if is_past else 1.0
	create_tween().tween_property(self, "modulate:a", target_alpha, _style.hover_out)


func start_reveal() -> void:
	var plain: String = DialogueRevealTimer.strip_bbcode(_sanitized_text())
	_reveal_schedule = DialogueRevealTimer.build_schedule(plain, _style)
	_reveal_elapsed = 0.0
	_revealing = true
	_text_label.visible_characters = 0
	set_process(true)


func complete_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	set_process(false)
	_text_label.visible_characters = -1
	reveal_finished.emit()


func is_revealing() -> bool:
	return _revealing


# Duração total do cronograma de revelação (0 se a fala nunca foi revelada com start_reveal()).
# Usado pelo modo AUTO para não somar a espera de leitura à animação (SPEC §9.6): o tempo já gasto
# revelando conta como parte do tempo de leitura, não além dele.
func get_reveal_duration() -> float:
	return _reveal_schedule[-1] if not _reveal_schedule.is_empty() else 0.0


func _process(delta: float) -> void:
	if not _revealing:
		set_process(false)
		return
	_reveal_elapsed += delta
	var count: int = 0
	while count < _reveal_schedule.size() and _reveal_schedule[count] <= _reveal_elapsed:
		count += 1
	_text_label.visible_characters = count
	if count >= _reveal_schedule.size():
		complete_reveal()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh()


func _update_layout_mode() -> void:
	if _style == null or not _name_label.visible:
		return
	var available: float = size.x
	if available <= 0.0:
		return
	var name_width: float = _name_label.get_minimum_size().x
	_row.vertical = name_width > _style.max_name_column_ratio * available


func _sanitized_text() -> String:
	return DialogueEntry.sanitize_bbcode(tr(_line.text_key), _line.line_id)


# Remove qualquer tag BBCode fora da lista permitida (i, b) e loga o corte.
static func sanitize_bbcode(text: String, line_id: StringName) -> String:
	var regex := RegEx.new()
	regex.compile("\\[(/?)(\\w+)[^\\]]*\\]")
	var removed: PackedStringArray = []
	var result: String = text
	for m: RegExMatch in regex.search_all(text):
		var tag_name: String = m.get_string(2).to_lower()
		if tag_name != "i" and tag_name != "b":
			removed.append(m.get_string())
	for tag: String in removed:
		result = result.replace(tag, "")
	if not removed.is_empty():
		print("[Dialogue] - AVISO: tag %s removida da fala \"%s\"" % [", ".join(removed), line_id])
	return result


func _on_mouse_entered() -> void:
	if _state != EntryState.PAST or _style == null:
		return
	create_tween().tween_property(self, "modulate:a", _style.past_hover_alpha, _style.hover_out)


func _on_mouse_exited() -> void:
	if _state != EntryState.PAST or _style == null:
		return
	create_tween().tween_property(self, "modulate:a", _style.past_alpha, _style.hover_out)
