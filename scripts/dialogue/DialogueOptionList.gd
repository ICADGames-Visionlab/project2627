# DialogueOptionList.gd — Lista de opções com destaque lógico único (SPEC §7.5): o foco nunca é do
# Godot, é gerido aqui, para hover do mouse e navegação por teclado nunca destacarem duas opções.
class_name DialogueOptionList
extends VBoxContainer

const OPTION_SCENE: PackedScene = preload("res://scenes/dialogue/DialogueOption.tscn")

signal option_confirmed(choice: DialogueChoice)
signal highlight_changed(choice: DialogueChoice)

var _options: Array[DialogueOption] = []
var _highlight_index: int = -1


func show_choices(visible_choices: Array[DialogueChoiceLayout.VisibleChoice], style: DialogueStyle,
		start_focus_on_first: bool) -> void:
	clear()
	for vc: DialogueChoiceLayout.VisibleChoice in visible_choices:
		var option: DialogueOption = OPTION_SCENE.instantiate()
		add_child(option)
		option.setup(vc.choice, vc.shortcut, style)
		option.mouse_entered.connect(_on_option_mouse_entered.bind(option))
		option.confirmed.connect(_on_option_confirmed)
		_options.append(option)
	if start_focus_on_first:
		_highlight_first_available()


# Pula indisponíveis; não dá a volta infinita se nada estiver disponível.
func move_highlight(delta: int) -> void:
	if _options.is_empty():
		return
	var count: int = _options.size()
	var index: int = _highlight_index
	for _i: int in range(count):
		index = (index + delta + count) % count
		if _options[index].choice.is_available:
			_set_highlight(index)
			return


func confirm_highlighted() -> void:
	if _highlight_index < 0 or _highlight_index >= _options.size():
		return
	var option: DialogueOption = _options[_highlight_index]
	if option.choice.is_available:
		option_confirmed.emit(option.choice)


func confirm_shortcut(number: int) -> bool:
	for option: DialogueOption in _options:
		if option.shortcut == number and option.choice.is_available:
			option_confirmed.emit(option.choice)
			return true
	return false


func has_highlight() -> bool:
	return _highlight_index >= 0


func only_system_choice() -> DialogueChoice:
	if _options.size() != 1 or not _options[0].choice.is_system:
		return null
	return _options[0].choice


# Brilho da opção escolhida (some para o sequenciador, com confirm_flash de duração total) mais o
# fade das outras, que roda em paralelo sem bloquear o estágio.
func play_confirm(choice: DialogueChoice, sequencer: DialogueSequencer) -> void:
	var chosen_option: DialogueOption = _find_option(choice)
	if chosen_option == null:
		return
	var style: DialogueStyle = chosen_option.style
	var multiplier: float = GameManager.dialogue_animation_multiplier
	var others_fade_out: float = style.scaled(style.others_fade_out, multiplier)
	for option: DialogueOption in _options:
		if option != chosen_option:
			create_tween().tween_property(option, "modulate:a", 0.0, others_fade_out)
	chosen_option.prepare_confirm_flash()
	chosen_option.pivot_offset = chosen_option.size / 2.0
	var half_flash: float = style.scaled(style.confirm_flash, multiplier) * 0.5
	sequencer.add_tween_stage(func(tween: Tween) -> void:
		tween.tween_property(chosen_option, "scale", Vector2.ONE * style.confirm_pulse_scale, half_flash)
		tween.tween_property(chosen_option, "scale", Vector2.ONE, half_flash)
	)


func clear() -> void:
	for option: DialogueOption in _options:
		option.queue_free()
	_options.clear()
	_highlight_index = -1


func _find_option(choice: DialogueChoice) -> DialogueOption:
	for option: DialogueOption in _options:
		if option.choice == choice:
			return option
	return null


func _highlight_first_available() -> void:
	for i: int in _options.size():
		if _options[i].choice.is_available:
			_set_highlight(i)
			return


func _set_highlight(index: int) -> void:
	if _highlight_index >= 0 and _highlight_index < _options.size():
		_options[_highlight_index].set_highlighted(false)
	_highlight_index = index
	if index >= 0 and index < _options.size():
		_options[index].set_highlighted(true)
		highlight_changed.emit(_options[index].choice)


func _on_option_mouse_entered(option: DialogueOption) -> void:
	if not option.choice.is_available:
		return
	var index: int = _options.find(option)
	if index >= 0:
		_set_highlight(index)


func _on_option_confirmed(choice: DialogueChoice) -> void:
	option_confirmed.emit(choice)
