# DialogueOption.gd — Uma opção clicável na lista (SPEC §7.5). O destaque é decidido pela
# DialogueOptionList (índice único, compartilhado); esta cena só sabe desenhar o estado que recebe.
# Em destaque a opção inverte: a caixa inteira vira a cor que o texto tinha em repouso e o texto
# vira a cor da caixa (option_hover_text_color).
class_name DialogueOption
extends PanelContainer

signal confirmed(choice: DialogueChoice)

@onready var _marker: Label = $Row/Marker
@onready var _number: Label = $Row/Number
@onready var _text: RichTextLabel = $Row/Text
@onready var _chosen_mark: Label = $Row/ChosenMark

var choice: DialogueChoice
var shortcut: int
var style: DialogueStyle
var is_highlighted: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	gui_input.connect(_on_gui_input)


func setup(p_choice: DialogueChoice, p_shortcut: int, p_style: DialogueStyle) -> void:
	choice = p_choice
	shortcut = p_shortcut
	style = p_style
	_chosen_mark.text = style.option_marker_chosen
	refresh()


func set_highlighted(value: bool) -> void:
	if value == is_highlighted:
		return
	is_highlighted = value
	refresh()


func refresh() -> void:
	if choice == null or style == null:
		return
	var available: bool = choice.is_available
	var highlighted: bool = is_highlighted and available
	mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	_number.text = tr(&"DIALOGUE_OPTION_FORMAT") % shortcut if (available and shortcut > 0) else ""
	_chosen_mark.visible = choice.was_chosen_before and available
	# Texto vazio em vez de visible = false: a coluna do marcador segue reservada, então entrar e
	# sair do destaque não empurra a linha para o lado.
	_marker.text = style.option_marker_hover if highlighted else ""

	var state_color: Color = _current_color()
	_number.add_theme_color_override("font_color", state_color)
	_marker.add_theme_color_override("font_color", state_color)
	_chosen_mark.add_theme_color_override("font_color", state_color)
	add_theme_stylebox_override("panel", _build_panel_box(highlighted))

	_text.clear()
	if not available:
		_text.push_color(style.option_disabled_color)
		_text.append_text("[%s] " % tr(choice.unavailable_reason_key))
		_text.pop()
	elif choice.tag_key != "":
		# A etiqueta também inverte no destaque: o dourado sobre o preenchimento não teria contraste.
		_text.push_color(state_color if highlighted else style.option_tag_color)
		_text.append_text("[%s] " % tr(choice.tag_key))
		_text.pop()
	_text.push_color(state_color)
	_text.append_text(tr(choice.text_key))
	_text.pop()


# A caixa em repouso é transparente, mas com as mesmas margens da caixa em destaque — sem isso a
# linha inteira daria um pulo de largura ao ganhar o preenchimento.
func _build_panel_box(highlighted: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _resting_color() if highlighted else Color(0, 0, 0, 0)
	box.content_margin_left = style.option_padding_h
	box.content_margin_right = style.option_padding_h
	box.content_margin_top = style.option_padding_v
	box.content_margin_bottom = style.option_padding_v
	return box


# Cor do texto fora do destaque — é ela que vira o fundo da caixa quando a opção é destacada.
func _resting_color() -> Color:
	if not choice.is_available:
		return style.option_disabled_color
	if choice.was_chosen_before:
		return style.option_chosen_color
	return style.option_color


func _current_color() -> Color:
	if is_highlighted and choice.is_available:
		return style.option_hover_text_color
	return _resting_color()


# Texto vira branco puro para o brilho de confirmação (SPEC §8.2), antes do pulso de escala.
func prepare_confirm_flash() -> void:
	_text.clear()
	_text.push_color(Color.WHITE)
	_text.append_text(tr(choice.text_key))
	_text.pop()


func _on_gui_input(event: InputEvent) -> void:
	if choice == null or not choice.is_available:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		confirmed.emit(choice)
