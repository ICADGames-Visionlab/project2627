# DialogueRevealTimer.gd — Tempos do modo AUTO e do typewriter progressivo. Puro: não sabe nada de
# Label ou Tween, só devolve números a partir do texto já sem BBCode.
class_name DialogueRevealTimer
extends RefCounted

static func strip_bbcode(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(text, "", true)


# Tempo de leitura do modo AUTO: não é afetado pelo multiplicador de animação.
static func auto_delay(plain_text: String, style: DialogueStyle) -> float:
	return minf(style.auto_base_delay + style.auto_per_char * plain_text.length(), style.auto_max_delay)


# Tempo acumulado até mostrar o caractere i, com pausas depois de vírgula e de finalizadores.
# "..." conta como um finalizador só (uma pausa para os três pontos, não três).
static func build_schedule(plain_text: String, style: DialogueStyle) -> PackedFloat32Array:
	var schedule: PackedFloat32Array = PackedFloat32Array()
	var elapsed: float = 0.0
	var char_duration: float = 1.0 / style.reveal_chars_per_second
	var length: int = plain_text.length()
	var i: int = 0
	while i < length:
		var is_ellipsis: bool = plain_text.substr(i, 3) == "..."
		var run_length: int = 3 if is_ellipsis else 1
		for _j: int in range(run_length):
			elapsed += char_duration
			schedule.append(elapsed)
		if is_ellipsis:
			elapsed += style.reveal_pause_stop
		else:
			var c: String = plain_text[i]
			if c == ",":
				elapsed += style.reveal_pause_comma
			elif c == "." or c == "…" or c == "?" or c == "!":
				elapsed += style.reveal_pause_stop
		i += run_length
	return schedule
