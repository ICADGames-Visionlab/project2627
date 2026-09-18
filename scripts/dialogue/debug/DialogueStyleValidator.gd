# DialogueStyleValidator.gd — "Validar estilo" (SPEC §15.3): contraste WCAG de cada cor do
# DialogueStyle e de cada falante do projeto (NPCs, cabeças, DialogueSpeaker), sempre no pior caso
# de fundo (ver DialogueContrast.worst_case_ratio, min_panel_alpha = 0.82 = limite inferior da
# preferência de opacidade, §14).
class_name DialogueStyleValidator
extends RefCounted

const MIN_PANEL_ALPHA: float = 0.82


class Result:
	var label: String
	var ratio: float
	var passed: bool

	func _init(p_label: String, p_ratio: float, p_passed: bool) -> void:
		label = p_label
		ratio = p_ratio
		passed = p_passed


static func run(style: DialogueStyle) -> Array[Result]:
	var results: Array[Result] = []
	_check_with_past(results, style, style.text_color, "text_color")
	_check_with_past(results, style, style.narration_color, "narration_color")
	_check_with_past(results, style, style.player_name_color, "player_name_color")
	_check(results, style, style.option_color, 1.0, "option_color")
	_check(results, style, style.option_chosen_color, 1.0, "option_chosen_color")
	_check(results, style, style.option_disabled_color, 1.0, "option_disabled_color")
	_check(results, style, style.option_tag_color, 1.0, "option_tag_color")
	# No destaque a caixa vira a cor de repouso do texto, então o texto invertido é conferido contra
	# os dois preenchimentos possíveis: opção nova e opção já escolhida.
	_check_direct(results, style, style.option_hover_text_color, style.option_color,
		"option_hover_text_color sobre option_color")
	_check_direct(results, style, style.option_hover_text_color, style.option_chosen_color,
		"option_hover_text_color sobre option_chosen_color")

	var roster: NPCRoster = load(DialogueCatalog.NPC_ROSTER_PATH)
	if roster != null:
		for definition: NPCDefinition in roster.npcs:
			if definition != null:
				_check_with_past(results, style, definition.dialogue_color, "%s.dialogue_color" % definition.id)

	for head: HeadData in HeadRegistry.get_all_heads():
		_check_with_past(results, style, head.color, "head:%s.color" % head.id)

	for speaker: DialogueSpeaker in DialogueCatalog.get_speakers().values():
		_check_with_past(results, style, speaker.name_color, "%s.name_color" % speaker.id)

	return results


static func report(style: DialogueStyle) -> String:
	var results: Array[Result] = run(style)
	var failed: int = 0
	var lines: PackedStringArray = []
	for result: Result in results:
		if not result.passed:
			failed += 1
		var mark: String = "✓" if result.passed else "✗"
		lines.append("  %s %s:1  %s" % [mark, "%.1f" % result.ratio, result.label])
	var summary: String = "[Dialogue] - Validar estilo: %d/%d cores acima de %.1f:1" % [
		results.size() - failed, results.size(), style.min_contrast_ratio
	]
	return summary + "\n" + "\n".join(lines)


static func _check(results: Array[Result], style: DialogueStyle, color: Color, alpha: float, label: String) -> void:
	var ratio: float = DialogueContrast.worst_case_ratio(color, alpha, style, MIN_PANEL_ALPHA)
	results.append(Result.new(label, ratio, ratio >= style.min_contrast_ratio))


# Confere uma cor em alfa cheio e na alfa de fala passada (past_alpha) — a maioria das cores do
# texto tem os dois estados possíveis no log (SPEC §9.3).
static func _check_with_past(results: Array[Result], style: DialogueStyle, color: Color, label: String) -> void:
	_check(results, style, color, 1.0, label)
	_check(results, style, color, style.past_alpha, label + " (passada)")


# Contraste direto entre duas cores sólidas (texto em destaque sobre o preenchimento do destaque),
# sem passar pelo pior caso de fundo — as duas já são opacas e uma cobre a outra.
static func _check_direct(results: Array[Result], style: DialogueStyle, foreground: Color,
		background: Color, label: String) -> void:
	var ratio: float = DialogueContrast.ratio(foreground, background)
	results.append(Result.new(label, ratio, ratio >= style.min_contrast_ratio))
