# EventBusOverlay.gd — Painel de debug que expõe os contadores do EventBusLogger em runtime.
# Motivação: o histórico circular e os contadores só têm valor se dá para olhar para eles sem
# parar o jogo. Alternado pela ação "debug_toggle_event_bus" (F3).
#
# Os textos deste painel são intencionalmente hardcoded: a exigência de tr() do Guideline vale
# para texto exibido ao jogador, e este overlay não existe em build de release.
extends CanvasLayer

# Intervalo de atualização. Propositalmente alto: a UI de debug não pode distorcer a métrica
# de tempo por frame que ela própria existe para medir.
@export var refresh_interval_seconds: float = 0.25
@export var history_lines: int = 20
@export var top_events_lines: int = 10

var _logger: EventBusLogger
var _elapsed: float = 0.0

@onready var _content: RichTextLabel = $Panel/Margin/Content


func _process(delta: float) -> void:
	if _logger == null or not visible:
		return
	_elapsed += delta
	if _elapsed < refresh_interval_seconds:
		return
	_elapsed = 0.0
	_content.text = _build_report()


# Liga o overlay à instrumentação. Chamado pelo próprio logger ao instanciar a cena.
func attach_to_logger(logger: EventBusLogger) -> void:
	_logger = logger


# Monta o relatório completo exibido no painel: contadores, ranking, alertas e histórico.
func _build_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]EventBus — debug[/b]")
	lines.append("Eventos instrumentados: %d" % _logger.get_tracked_event_count())
	lines.append("Emissões no último frame: %d" % _logger.get_last_frame_emissions())
	lines.append("")
	lines.append_array(_build_silent_section())
	lines.append("")
	lines.append_array(_build_top_section())
	lines.append("")
	lines.append_array(_build_history_section())
	return "\n".join(lines)


# Lista os eventos já emitidos sem nenhum listener — quase sempre fiação esquecida.
func _build_silent_section() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var silent: Array = _logger.get_silent_events()
	if silent.is_empty():
		lines.append("[b]Eventos sem listener:[/b] nenhum")
		return lines
	lines.append("[b]Eventos sem listener:[/b]")
	for key: StringName in silent:
		lines.append("  %s" % key)
	return lines


# Ranking dos eventos mais emitidos na sessão, para identificar candidatos a batching (P2).
func _build_top_section() -> PackedStringArray:
	var totals: Dictionary = _logger.get_total_by_event()
	var keys: Array = totals.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(totals[a]) > int(totals[b]))

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Mais emitidos:[/b]")
	for index: int in mini(top_events_lines, keys.size()):
		var key: StringName = keys[index]
		lines.append("  %-38s %d" % [key, int(totals[key])])
	return lines


# Últimas emissões em ordem cronológica: é o que permite reconstruir uma cascata depois do fato.
func _build_history_section() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Histórico:[/b]")
	for record: EventBusLogger.EventRecord in _logger.get_recent_history(history_lines):
		lines.append("  f%d %-32s → %d  %s" % [
			record.frame, record.event_name, record.listeners, record.payload_text
		])
	return lines
