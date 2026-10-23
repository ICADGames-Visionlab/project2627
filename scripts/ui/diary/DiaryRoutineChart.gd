## DiaryRoutineChart - a tabela de rotina do diário, desenhada em _draw.
##
## Seis linhas (neutro, emoção 1 e emoção 2, cada uma em dia de trabalho e de folga) contra as horas
## do dia jogável, da hora de acordar até o horário máximo. Cada linha mostra a rotina que VALE pra
## aquela combinação (com o fallback do NPCRoutineResolver), cortada em trechos: um trecho que o
## jogador já viu aparece com o horário e o lugar; o resto vira um bloco cinza com "?". A linha
## vertical é o horário atual.
##
## É desenho, e não uma árvore de nós, porque é um gráfico: os trechos mudam de tamanho com o horário,
## e a montagem pura (build_row) fica separada e testável sem tela nenhuma.
class_name DiaryRoutineChart
extends Control

## Espaço para constantes

# Resolução da tabela, em minutos de jogo. O relógio anda de 10 em 10 e as entradas são de 5 em 5.
const CELL_MINUTES: int = 5

## Espaço para variáveis exportadas

@export var label_width: float = 170.0
@export var header_height: float = 60.0
@export var row_padding: float = 6.0
@export var hour_label_step: int = 2

@export_group("Cores")
@export var background_color: Color = Color(0.97, 0.95, 0.9, 1)
@export var grid_color: Color = Color(0.55, 0.47, 0.38, 0.35)
@export var ink_color: Color = Color(0.16, 0.09, 0.05, 1)
@export var soft_ink_color: Color = Color(0.4, 0.3, 0.2, 1)
@export var known_color: Color = Color(0.74, 0.68, 0.88, 1)
@export var known_edge_color: Color = Color(0.4, 0.3, 0.65, 1)
@export var unknown_color: Color = Color(0.83, 0.81, 0.79, 1)
@export var current_row_color: Color = Color(0.95, 0.85, 0.55, 0.45)
@export var now_line_color: Color = Color(0.1, 0.06, 0.04, 1)

@export_group("Fonte")
@export var label_font_size: int = 20
@export var small_font_size: int = 16
@export var unknown_font_size: int = 30

## Espaço para variáveis

var _definition: NPCDefinition
# Os blocos conhecidos desenhados por último, com o texto inteiro, pro tooltip.
var _hit_areas: Array[Dictionary] = []

## Espaço para funções nativas

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	_hit_areas.clear()
	if _definition == null or GameClock.settings == null:
		return

	var font: Font = get_theme_default_font()
	var wake_hour: int = GameClock.settings.wake_hour
	var day_length: int = GameClock.settings.day_length_minutes()
	var rows: Array[Vector2i] = _rows()
	var row_height: float = (size.y - header_height) / float(rows.size())
	var timeline: Rect2 = Rect2(label_width, header_height, size.x - label_width, size.y - header_height)
	var current_row: Vector2i = _current_row()
	var npc_id: StringName = _definition.id
	var is_seen: Callable = func(key: String) -> bool: return Diary.is_routine_seen(npc_id, key)

	# Cabeçalho das horas e grade.
	for hour_offset: int in range(0, ceili(day_length / 60.0) + 1):
		var x: float = timeline.position.x + timeline.size.x * (hour_offset * 60.0) / float(day_length)
		draw_line(Vector2(x, header_height * 0.65), Vector2(x, size.y), grid_color, 1.0)
		if hour_offset % hour_label_step == 0 and hour_offset * 60 < day_length:
			var label: String = tr(&"DIARY_ROUTINE_HOUR") % ((wake_hour + hour_offset) % 24)
			draw_string(font, Vector2(x + 4.0, header_height - 6.0), label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, small_font_size, soft_ink_color)

	for row_index: int in rows.size():
		var slot: int = rows[row_index].x
		var day_type: int = rows[row_index].y
		var top: float = header_height + row_height * row_index
		if rows[row_index] == current_row:
			draw_rect(Rect2(0.0, top, size.x, row_height), current_row_color)
		draw_line(Vector2(0.0, top), Vector2(size.x, top), grid_color, 1.0)
		_draw_row_label(font, slot, day_type, top, row_height)

		var segments: Array[Dictionary] = build_row(_definition, slot, day_type, wake_hour, day_length, is_seen)
		for segment: Dictionary in segments:
			var x0: float = timeline.position.x + timeline.size.x * float(segment["start"]) / float(day_length)
			var x1: float = timeline.position.x + timeline.size.x * float(segment["end"]) / float(day_length)
			var rect: Rect2 = Rect2(x0 + 1.0, top + row_padding, maxf(x1 - x0 - 2.0, 1.0), row_height - row_padding * 2.0)
			_draw_segment(font, rect, segment)

	# O horário atual.
	var now: int = GameClock.time.get_minutes_into_day()
	if now >= 0 and now <= day_length:
		var now_x: float = timeline.position.x + timeline.size.x * float(now) / float(day_length)
		draw_line(Vector2(now_x, small_font_size + 6.0), Vector2(now_x, size.y), now_line_color, 3.0)
		var now_label: String = tr(&"DIARY_ROUTINE_NOW")
		var label_size: Vector2 = font.get_string_size(now_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size)
		var label_x: float = clampf(now_x - label_size.x * 0.5, timeline.position.x, size.x - label_size.x)
		draw_string(font, Vector2(label_x, small_font_size + 2.0), now_label, HORIZONTAL_ALIGNMENT_LEFT,
			-1, small_font_size, now_line_color)

## Espaço para funções personalizadas

func configure(definition: NPCDefinition) -> void:
	_definition = definition
	queue_redraw()


# Os trechos de uma linha da tabela, em minutos do dia de jogo (0 = hora de acordar):
# [{ "start": int, "end": int, "known": bool, "time": String, "place": String, "label": String }, ...],
# cobrindo [0, day_length). label é "time place", o texto inteiro (tooltip). Trechos desconhecidos
# vizinhos viram um só, com os textos vazios. is_seen recebe a chave do trecho
# (Diary.routine_key) e diz se o jogador já o viu.
static func build_row(definition: NPCDefinition, slot: int, day_type: int, wake_hour: int,
		day_length: int, is_seen: Callable) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var routine: NPCRoutine = NPCRoutineResolver.resolve_routine(definition, slot, day_type) \
		if definition != null else null
	var ordered: Array[NPCRoutineEntry] = []
	if routine != null:
		ordered = NPCRoutineResolver.sorted_entries(routine, wake_hour)

	var minute: int = 0
	while minute < day_length:
		var part: String = ""
		var time: String = ""
		var place: String = ""
		if routine != null:
			for index: int in routine.exceptions.size():
				var exception: NPCRoutineException = routine.exceptions[index]
				if exception != null and exception.is_executable() and exception.is_active_at(minute, wake_hour):
					part = Diary.exception_part(index)
					time = "%02d:%02d" % [exception.start_hour, exception.start_minute]
					place = TranslationServer.translate(&"DIARY_ROUTINE_PATROL")
					break
			if part.is_empty() and not ordered.is_empty():
				var entry: NPCRoutineEntry = ordered[NPCRoutineResolver.current_index(ordered, minute, wake_hour)]
				part = Diary.entry_part(entry)
				time = entry.format_clock()
				place = place_name(entry.waypoint)

		var known: bool = not part.is_empty() and bool(is_seen.call(Diary.routine_key(slot, day_type, part)))
		var end: int = mini(minute + CELL_MINUTES, day_length)
		var identity: String = part if known else "?"
		var last: Dictionary = segments.back() if not segments.is_empty() else {}
		if not last.is_empty() and last["id"] == identity:
			last["end"] = end
		else:
			segments.append({ "id": identity, "start": minute, "end": end, "known": known,
				"time": time if known else "", "place": place if known else "",
				"label": "%s %s" % [time, place] if known else "" })
		minute = end
	return segments


# Nome do lugar de um waypoint, pelo CSV (DIARY_PLACE_<WAYPOINT>), com o id como último recurso.
static func place_name(waypoint: StringName) -> String:
	var key: String = "DIARY_PLACE_" + String(waypoint).to_upper()
	var translated: String = TranslationServer.translate(key)
	return String(waypoint) if translated == key else translated


# As seis linhas, como (slot, tipo de dia), na ordem da tabela.
func _rows() -> Array[Vector2i]:
	var rows: Array[Vector2i] = []
	for slot: int in NPCDefinition.EmotionSlot.values():
		for day_type: int in NPCDefinition.DayType.values():
			rows.append(Vector2i(slot, day_type))
	return rows


# A linha que vale hoje, destacada. Sem NPCDirector na cena (outra cena, sonho) não há destaque.
func _current_row() -> Vector2i:
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null or _definition == null or GameClock.is_dreaming():
		return Vector2i(-1, -1)
	return Vector2i(director.get_emotion_slot(_definition.id),
		NPCRoutineResolver.resolve_day_type(_definition, GameClock.time.get_weekday()))


func _draw_row_label(font: Font, slot: int, day_type: int, top: float, row_height: float) -> void:
	var emotion: EmotionDefinition = _definition.get_emotion(slot)
	var slot_name: String = emotion.get_display_name() if emotion != null else tr(&"DIARY_ROUTINE_NEUTRAL")
	var day_name: String = tr(&"DIARY_ROUTINE_WORKDAY") if day_type == NPCDefinition.DayType.WORKDAY \
		else tr(&"DIARY_ROUTINE_DAY_OFF")
	var middle: float = top + row_height * 0.5
	draw_string(font, Vector2(10.0, middle - 2.0), _fit(font, slot_name, label_width - 16.0, label_font_size),
		HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, ink_color)
	draw_string(font, Vector2(10.0, middle + small_font_size + 2.0), day_name, HORIZONTAL_ALIGNMENT_LEFT,
		-1, small_font_size, soft_ink_color)


func _draw_segment(font: Font, rect: Rect2, segment: Dictionary) -> void:
	if bool(segment["known"]):
		draw_rect(rect, known_color)
		draw_rect(Rect2(rect.position, Vector2(minf(4.0, rect.size.x), rect.size.y)), known_edge_color)
		_hit_areas.append({ "rect": rect, "text": String(segment["label"]) })
		# O horário numa linha e o lugar quebrado por palavra nas de baixo: um trecho de uma hora é
		# estreito demais pra "06:00 Casa do policial" numa linha só. O texto inteiro fica no tooltip.
		var width: float = rect.size.x - 12.0
		var lines: PackedStringArray = [_fit(font, String(segment["time"]), width, small_font_size)]
		var line_height: float = small_font_size + 3.0
		var max_lines: int = maxi(int((rect.size.y - 8.0) / line_height), 1)
		lines.append_array(_wrap(font, String(segment["place"]), width, small_font_size, max_lines - 1))
		var top: float = rect.get_center().y - line_height * lines.size() * 0.5 + small_font_size * 0.85
		for index: int in lines.size():
			draw_string(font, Vector2(rect.position.x + 8.0, top + line_height * index), lines[index],
				HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, ink_color)
		return
	draw_rect(rect, unknown_color)
	if rect.size.x > unknown_font_size:
		var mark_size: Vector2 = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, unknown_font_size)
		draw_string(font, Vector2(rect.get_center().x - mark_size.x * 0.5, rect.get_center().y + unknown_font_size * 0.35),
			"?", HORIZONTAL_ALIGNMENT_LEFT, -1, unknown_font_size, soft_ink_color)


# Quebra o texto por palavra em até max_lines linhas que caibam na largura. A última linha (ou uma
# palavra sozinha larga demais) é cortada com reticências.
func _wrap(font: Font, text: String, max_width: float, font_size: int, max_lines: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	if max_lines <= 0 or text.is_empty():
		return lines
	var current: String = ""
	var words: PackedStringArray = text.split(" ", false)
	for index: int in words.size():
		var candidate: String = words[index] if current.is_empty() else current + " " + words[index]
		if current.is_empty() or font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			current = candidate
			continue
		if lines.size() == max_lines - 1:
			# Sem linha sobrando: o resto vai junto pra última, que é cortada.
			current = " ".join(words.slice(index - current.split(" ", false).size()))
			break
		lines.append(_fit(font, current, max_width, font_size))
		current = words[index]
	if not current.is_empty():
		lines.append(_fit(font, current, max_width, font_size))
	return lines


# O texto inteiro do trecho sob o mouse: o bloco pode ter cortado o lugar.
func _get_tooltip(at_position: Vector2) -> String:
	for area: Dictionary in _hit_areas:
		if (area["rect"] as Rect2).has_point(at_position):
			return String(area["text"])
	return ""


# Corta o texto (com reticências) pra caber na largura. Trecho curto demais fica sem texto.
func _fit(font: Font, text: String, max_width: float, font_size: int) -> String:
	if max_width <= 0.0:
		return ""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var result: String = text
	while result.length() > 1:
		result = result.left(result.length() - 1)
		if font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return result + "…"
	return ""
