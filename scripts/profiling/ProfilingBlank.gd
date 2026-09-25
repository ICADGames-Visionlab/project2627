## ProfilingBlank - uma lacuna da página do profiling: o buraco onde uma palavra do glossário cai.
##
## COMO USAR: o layout está em scenes/profiling/ProfilingBlank.tscn (moldura, linha de baixo, fonte,
## largura mínima). Quem instancia é a ProfilingPage, uma por lacuna do texto, pela cena apontada no
## Inspector dela. Este script só põe o dado no lugar e avisa por signal — ele não conhece o diário.
##
## CADA LACUNA TEM UMA CATEGORIA: a da palavra esperada nela. A lacuna aparece na cor dessa
## categoria e só aceita palavras dela — não dá pra pôr um nome onde a frase pede uma arma.
##
## OS GESTOS:
##
##   soltar palavra em cima   -> word_dropped(index, word_id), se a categoria bater
##   arrastar a palavra fora  -> PUXA a palavra: a lacuna fica vazia enquanto ela está na mão do
##                               jogador, e a palavra vai pra outra lacuna (ou de volta pro
##                               glossário, se ela for solta em qualquer outro lugar)
##   clique DIREITO na cheia  -> cleared(index), e a palavra volta pro glossário
##
## O clique esquerdo não tira a palavra de propósito: o esquerdo é o botão de arrastar, e pegar a
## palavra pra levá-la a outra lacuna não pode ter o risco de devolvê-la ao glossário.
##
## A LACUNA NUNCA DIZ QUE ESTÁ ERRADA. O GDD é específico: a mensagem acima da página conta QUANTAS
## palavras estão erradas, nunca QUAIS. Por isso só existe o estado "certa" — o checkmark verde que
## aparece quando a página inteira está correta.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingBlank
extends PanelContainer

## Espaço para sinais

## Emitido quando o jogador solta uma palavra do glossário (ou de outra lacuna) nesta lacuna.
signal word_dropped(index: int, word_id: StringName)

## Emitido no clique direito numa lacuna preenchida: ela esvazia.
signal cleared(index: int)

## Espaço para variáveis exportadas

## PLACEHOLDER: o que a lacuna vazia mostra, até existir arte de linha pontilhada.
@export var empty_text: String = "_______"

## PLACEHOLDER: o que entra ao lado da palavra quando a página inteira está correta.
@export var correct_glyph: String = " ✓"

## Opacidade do fundo da lacuna vazia, que é tingido com a cor da categoria que ela aceita.
@export_range(0.0, 1.0, 0.01) var empty_opacity: float = 0.15

## Cor da lacuna certa (o verde do acerto).
@export var correct_tint: Color = Color(0.45, 0.9, 0.5)

## Opacidade do fundo da lacuna preenchida. Ela é tingida com a cor da CATEGORIA da palavra, e
## opacidade cheia roubaria a atenção da frase.
@export_range(0.0, 1.0, 0.01) var filled_opacity: float = 0.35

## Espaço para variáveis

var index: int = -1

var _word: GlossaryWord
# A categoria que esta lacuna aceita. Null aceita qualquer palavra (a palavra esperada está sem
# categoria, o que o resumo da palavra já acusa).
var _category: GlossaryCategory
# Guardado, e não passado adiante, porque configure() pode ser chamado antes de o nó estar pronto:
# sem isto, o checkmark do acerto se perderia no _ready.
var _is_correct: bool = false
# O arraste em curso saiu DESTA lacuna. NOTIFICATION_DRAG_END chega a todos os Controls da tela, e é
# isto que separa "o meu arraste acabou" de "acabou o arraste de alguém". Enquanto ele dura, a
# lacuna se desenha vazia: a palavra está na mão do jogador.
var _is_dragging: bool = false

## Espaço para variáveis onready

@onready var _label: Label = $WordLabel

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()


# Arraste que termina sem ninguém aceitar esvazia a lacuna: a palavra volta pro glossário. É o mesmo
# desfecho de soltá-la em cima do glossário — soltar "no nada" não pode deixar o gesto pela metade.
func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _is_dragging:
		return
	_is_dragging = false
	if not is_inside_tree() or _word == null:
		return
	_refresh()
	if not get_viewport().gui_is_drag_successful():
		print("[Profiling] - Palavra da lacuna %d solta fora: devolvida ao glossário" % index)
		cleared.emit(index)


func _gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or _word == null:
		return
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		cleared.emit(index)


# Só aceita palavra da categoria desta lacuna. As outras são recusadas no arraste, e o Godot mostra
# o cursor de "não pode" em cima da lacuna.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var payload: Dictionary = data as Dictionary
	if payload == null or not payload.has("word_id"):
		return false
	var word: GlossaryWord = ProfilingCatalog.find_word(StringName(payload["word_id"]))
	return word != null and word.fits_category(_category)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data as Dictionary
	if payload == null or not payload.has("word_id"):
		return
	word_dropped.emit(index, StringName(payload["word_id"]))


# Arrastar a palavra PRA FORA da lacuna. O payload leva de onde ela saiu ("from_blank"), que é o que
# permite ao glossário aceitar a palavra de volta ao receber o soltar.
#
# O preview é a própria lacuna duplicada, deslocada meio tamanho pra ficar centrada no cursor
# (set_drag_preview põe o canto no mouse), e a lacuna de verdade passa a se desenhar vazia.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _word == null:
		return null

	# DUPLICATE_SCRIPTS sozinho: o padrão de duplicate() também copia as CONEXÕES de sinal, e o
	# preview não deve responder por esta palavra — ele é só um desenho seguindo o cursor.
	var preview: ProfilingBlank = duplicate(Node.DUPLICATE_SCRIPTS) as ProfilingBlank
	preview.custom_minimum_size = size

	var holder: Control = Control.new()
	holder.add_child(preview)
	preview.position = -0.5 * size
	set_drag_preview(holder)
	preview.configure(index, _word, _is_correct, _category)

	_is_dragging = true
	_refresh()
	return { "word_id": _word.id, "from_blank": index }

## Espaço para funções personalizadas

# Põe (ou tira) a palavra da lacuna. is_correct só vem true quando a página inteira está certa —
# ver o bloco "A LACUNA NUNCA DIZ QUE ESTÁ ERRADA" no topo deste arquivo. category é a categoria que
# a lacuna aceita (a da palavra esperada nela).
func configure(p_index: int, p_word: GlossaryWord, is_correct: bool = false,
		category: GlossaryCategory = null) -> void:
	index = p_index
	_word = p_word
	_is_correct = is_correct
	_category = category
	_refresh()


# A palavra que está na lacuna, ou null.
func get_word() -> GlossaryWord:
	return _word


# Redesenha a lacuna. Nada de StyleBox criado aqui: a moldura é a da cena, e o que muda é o
# tingimento (self_modulate) e o texto.
func _refresh() -> void:
	if _label == null:
		return

	if _word == null or _is_dragging:
		# Vazia, na cor da categoria que ela aceita: é o que diz ao jogador que tipo de palavra falta.
		var category_color: Color = _category.color if _category != null else Color.WHITE
		_label.text = empty_text
		_label.modulate = Color(category_color.r, category_color.g, category_color.b, 0.8)
		self_modulate = Color(category_color.r, category_color.g, category_color.b, empty_opacity)
		return

	_label.text = _word.get_display_text() + (correct_glyph if _is_correct else "")
	if _is_correct:
		_label.modulate = correct_tint
		self_modulate = Color(correct_tint.r, correct_tint.g, correct_tint.b, filled_opacity)
		return

	_label.modulate = Color.WHITE
	var tint: Color = _word.get_color()
	tint.a = filled_opacity
	self_modulate = tint
