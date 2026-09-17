# DialogueLog.gd — Histórico rolável de falas (SPEC §7.3). style e policy são atribuídos pela
# DialogueScreen logo após instanciar, antes de qualquer append_line.
class_name DialogueLog
extends ScrollContainer

const ENTRY_SCENE: PackedScene = preload("res://scenes/dialogue/DialogueEntry.tscn")

signal new_lines_pending_changed(count: int)
signal reached_bottom

var style: DialogueStyle:
	set(value):
		style = value
		if is_node_ready() and style != null:
			_list.add_theme_constant_override("separation", int(style.entry_spacing))
var policy: DialogueScrollPolicy

@onready var _list: VBoxContainer = $List

var _entries: Array[DialogueEntry] = []
var _pending_count: int = 0
var _trim_label: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	follow_focus = false


# Adiciona a fala; a decisão de rolar ou só acender o indicador roda um frame depois, quando o
# ScrollContainer já recalculou o range a partir do novo filho.
func append_line(line: DialogueLine, resolved: DialogueSpeakerResolver.Resolved,
		exchange_index: int) -> DialogueEntry:
	var entry: DialogueEntry = ENTRY_SCENE.instantiate()
	_list.add_child(entry)
	entry.setup(line, resolved, exchange_index, style)
	_entries.append(entry)
	_trim()
	_react_to_new_line.call_deferred(entry)
	return entry


func _react_to_new_line(entry: DialogueEntry) -> void:
	await get_tree().process_frame
	var max_scroll: float = get_max_scroll()
	var action: DialogueScrollPolicy.Action = policy.decide(
		DialogueScrollPolicy.Reason.NEW_LINE, scroll_vertical, max_scroll
	)
	if action == DialogueScrollPolicy.Action.SCROLL_TO_END:
		scroll_to_end(true)
	elif action == DialogueScrollPolicy.Action.SHOW_INDICATOR:
		_pending_count += 1
		new_lines_pending_changed.emit(_pending_count)
	if is_instance_valid(entry):
		entry.play_enter(style.scaled(style.entry_fade_in, GameManager.dialogue_animation_multiplier))


func set_current_exchange(current: int) -> void:
	for entry: DialogueEntry in _entries:
		entry.set_past(entry.exchange_index < current - 1)


func scroll_to_end(animated: bool) -> void:
	var target: float = get_max_scroll()
	if animated and style != null:
		create_tween().tween_property(self, "scroll_vertical", target, style.stick_scroll_duration)
	else:
		scroll_vertical = int(target)
	_pending_count = 0
	new_lines_pending_changed.emit(0)
	reached_bottom.emit()


func is_at_bottom() -> bool:
	return policy.is_stuck(scroll_vertical, get_max_scroll())


func get_max_scroll() -> float:
	var bar: VScrollBar = get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func clear_entries() -> void:
	for entry: DialogueEntry in _entries:
		entry.queue_free()
	_entries.clear()
	if _trim_label != null:
		_trim_label.queue_free()
		_trim_label = null
	_pending_count = 0


func refresh_all() -> void:
	for entry: DialogueEntry in _entries:
		entry.refresh()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or style == null:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var direction: int = -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
	var line_height: float = style.effective_body_size(1.0) * style.line_spacing
	var target: float = clampf(scroll_vertical + direction * style.wheel_lines * line_height, 0.0, get_max_scroll())
	create_tween().tween_property(self, "scroll_vertical", target, style.stick_scroll_duration)
	accept_event()


# Remove as mais antigas acima de max_log_entries e mostra "… falas anteriores".
func _trim() -> void:
	var max_entries: int = style.max_log_entries if style != null else 300
	if _entries.size() <= max_entries:
		return
	while _entries.size() > max_entries:
		_entries.pop_front().queue_free()
	if _trim_label == null:
		_trim_label = Label.new()
		_trim_label.modulate.a = 0.6
		_list.add_child(_trim_label)
		_list.move_child(_trim_label, 0)
	_trim_label.text = tr(&"DIALOGUE_LOG_TRIMMED")
