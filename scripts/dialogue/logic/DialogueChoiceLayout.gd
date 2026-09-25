# DialogueChoiceLayout.gd — Numeração das opções visíveis. Puro, sem cena: o autoteste cobre a
# regra "sem buracos" sem precisar montar a lista de UI.
class_name DialogueChoiceLayout
extends RefCounted

const MAX_SHORTCUTS: int = 9


class VisibleChoice:
	var choice: DialogueChoice
	var shortcut: int  # 1..9, ou 0 quando não tem atalho (indisponível ou 10ª em diante)

	func _init(p_choice: DialogueChoice, p_shortcut: int) -> void:
		choice = p_choice
		shortcut = p_shortcut


# Descarta indisponíveis escondidas, numera só as disponíveis a partir de 1, sem buracos.
static func build(choices: Array[DialogueChoice]) -> Array[VisibleChoice]:
	var result: Array[VisibleChoice] = []
	var next_shortcut: int = 1
	for choice: DialogueChoice in choices:
		if not choice.is_available and not choice.show_when_unavailable:
			continue
		var assigned: int = 0
		if choice.is_available:
			if next_shortcut <= MAX_SHORTCUTS:
				assigned = next_shortcut
				next_shortcut += 1
			else:
				push_warning("[Dialogue] - AVISO: mais de %d opções disponíveis; \"%s\" ficou sem atalho" % [MAX_SHORTCUTS, choice.choice_id])
		result.append(VisibleChoice.new(choice, assigned))
	return result
