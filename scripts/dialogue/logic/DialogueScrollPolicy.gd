# DialogueScrollPolicy.gd — Decide se o log deve rolar ou só acender o indicador "↓", conforme a
# tabela do SPEC §9.5. Puro: a tela só chama decide() com os números do ScrollBar.
class_name DialogueScrollPolicy
extends RefCounted

enum Reason { NEW_LINE, CHOICES_SHOWN, NUMBER_KEY, JUMP_TO_END }
enum Action { NONE, SCROLL_TO_END, SHOW_INDICATOR }

var _stick_threshold: float


func _init(p_stick_threshold: float) -> void:
	_stick_threshold = p_stick_threshold


func is_stuck(scroll_value: float, max_scroll: float) -> bool:
	return (max_scroll - scroll_value) <= _stick_threshold


# NUMBER_KEY grudado: NONE, a escolha segue. NUMBER_KEY lendo o histórico: SCROLL_TO_END, e é a
# tela quem cancela a escolha ao ver esse resultado para essa razão.
func decide(reason: Reason, scroll_value: float, max_scroll: float) -> Action:
	var stuck: bool = is_stuck(scroll_value, max_scroll)
	match reason:
		Reason.NEW_LINE:
			return Action.SCROLL_TO_END if stuck else Action.SHOW_INDICATOR
		Reason.CHOICES_SHOWN, Reason.JUMP_TO_END:
			return Action.SCROLL_TO_END
		Reason.NUMBER_KEY:
			return Action.NONE if stuck else Action.SCROLL_TO_END
	return Action.NONE
