## ProfilingBlank - uma lacuna da página do profiling: o buraco onde uma palavra do glossário cai.
##
## COMO USAR: ninguém instancia isto à mão. A ProfilingPage cria uma lacuna por índice do texto e
## chama configure(). A lacuna não conhece o diário: ela avisa por signal, e a página escreve.
##
## O QUE ELE FAZ:
##
##   soltar palavra em cima -> word_dropped(index, word_id)
##   clique esquerdo cheia  -> cleared(index), e a palavra volta pro glossário
##
## A LACUNA NUNCA DIZ QUE ESTÁ ERRADA. O GDD é específico: a mensagem acima da página conta QUANTAS
## palavras estão erradas, nunca QUAIS. Marcar a lacuna errada em vermelho transformaria o quebra-
## cabeça em tentativa e erro de uma lacuna por vez. Por isso só existe o estado "certa" — o
## checkmark verde que aparece quando a página inteira está correta.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingBlank
extends PanelContainer

## Espaço para sinais

## Emitido quando o jogador solta uma palavra do glossário nesta lacuna.
signal word_dropped(index: int, word_id: StringName)

## Emitido quando o jogador clica numa lacuna preenchida: ela esvazia.
signal cleared(index: int)

## Espaço para constantes

# PLACEHOLDER: o desenho da lacuna vazia e o checkmark da lacuna certa, até existir arte. Texto de
# tela, não frase de jogador — não passam por tr().
const EMPTY_TEXT: String = "_______"
const CORRECT_GLYPH: String = " ✓"

const CORRECT_COLOR: Color = Color(0.45, 0.9, 0.5)

## Espaço para variáveis exportadas

## Largura mínima da lacuna, em pixels. É balanceamento de leitura: lacuna estreita demais faz o
## texto "pular" quando a palavra entra, e larga demais desmancha a frase.
@export var minimum_blank_width: float = 150.0

## Espaço para variáveis

var index: int = -1

var _word: GlossaryWord
# Guardado, e não passado adiante, porque configure() pode ser chamado antes de o nó estar pronto
# (a página monta a fileira inteira e só então configura cada lacuna): sem isto, o checkmark do
# acerto se perderia no _ready.
var _is_correct: bool = false
var _label: Label

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(minimum_blank_width, 0.0)

	_label = Label.new()
	# O texto da palavra já vem traduzido; traduzir de novo faria o Godot procurar a palavra no CSV.
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_refresh()


func _gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_LEFT and _word != null:
		accept_event()
		cleared.emit(index)


# Aceita qualquer palavra: a lacuna não sabe qual é a certa, e não deveria — se ela recusasse a
# palavra errada, o jogador descobriria a solução por eliminação, sem nunca ler a história.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var payload: Dictionary = data as Dictionary
	return payload != null and payload.has("word_id")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data as Dictionary
	if payload == null or not payload.has("word_id"):
		return
	word_dropped.emit(index, StringName(payload["word_id"]))

## Espaço para funções personalizadas

# Põe (ou tira) a palavra da lacuna. is_correct só vem true quando a página inteira está certa —
# ver o bloco "A LACUNA NUNCA DIZ QUE ESTÁ ERRADA" no topo deste arquivo.
func configure(p_index: int, p_word: GlossaryWord, is_correct: bool = false) -> void:
	index = p_index
	_word = p_word
	_is_correct = is_correct
	_refresh()


# A palavra que está na lacuna, ou null.
func get_word() -> GlossaryWord:
	return _word


func _refresh() -> void:
	if _label == null:
		return

	if _word == null:
		_label.text = EMPTY_TEXT
		_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
		add_theme_stylebox_override("panel", _build_style(Color(1.0, 1.0, 1.0, 0.08)))
		return

	_label.text = _word.get_display_text() + (CORRECT_GLYPH if _is_correct else "")
	if _is_correct:
		_label.add_theme_color_override("font_color", CORRECT_COLOR)
		add_theme_stylebox_override("panel", _build_style(Color(CORRECT_COLOR.r, CORRECT_COLOR.g,
			CORRECT_COLOR.b, 0.18)))
		return

	# Palavra na lacuna aparece na cor da categoria dela: é o que deixa o jogador reler a frase
	# preenchida e ver de longe que pôs um nome onde a frase pedia um objeto.
	_label.add_theme_color_override("font_color", Color.WHITE)
	var tint: Color = _word.get_color()
	tint.a = 0.35
	add_theme_stylebox_override("panel", _build_style(tint))


# O fundo da lacuna. A borda de baixo mais grossa é o que faz a lacuna vazia parecer uma linha pra
# preencher, e não um botão.
func _build_style(background: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 1.0, 1.0, 0.5)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4.0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	return style
