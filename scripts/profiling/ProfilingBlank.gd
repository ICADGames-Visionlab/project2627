## ProfilingBlank - uma lacuna da página do profiling: o buraco onde uma palavra do glossário cai.
##
## COMO USAR: o layout está em scenes/profiling/ProfilingBlank.tscn (moldura, linha de baixo, fonte,
## largura mínima). Quem instancia é a ProfilingPage, uma por lacuna do texto, pela cena apontada no
## Inspector dela. Este script só põe o dado no lugar e avisa por signal — ele não conhece o diário.
##
## OS GESTOS SÃO OS MESMOS DA PALAVRA NO GLOSSÁRIO (ver GlossaryWordChip), e pelo mesmo motivo:
##
##   soltar palavra em cima   -> word_dropped(index, word_id)
##   arrastar a palavra fora  -> tira a palavra desta lacuna e leva pra outra (ou de volta pro
##                               glossário, se o jogador soltar em cima dele)
##   clique curto na cheia    -> cleared(index), e a palavra volta pro glossário
##
## O clique só conta ao SOLTAR o botão, e só se o arraste não tiver começado no meio: se ele contasse
## na pressão, pegar a palavra pra tirar da lacuna já a devolveria ao glossário antes de o jogador
## conseguir arrastá-la pra outro lugar.
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

## Emitido quando o jogador solta uma palavra do glossário (ou de outra lacuna) nesta lacuna.
signal word_dropped(index: int, word_id: StringName)

## Emitido no clique curto numa lacuna preenchida: ela esvazia.
signal cleared(index: int)

## Espaço para variáveis exportadas

## PLACEHOLDER: o que a lacuna vazia mostra, até existir arte de linha pontilhada.
@export var empty_text: String = "_______"

## PLACEHOLDER: o que entra ao lado da palavra quando a página inteira está correta.
@export var correct_glyph: String = " ✓"

## Cor da lacuna vazia.
@export var empty_tint: Color = Color(1.0, 1.0, 1.0, 0.1)

## Cor da lacuna certa (o verde do acerto).
@export var correct_tint: Color = Color(0.45, 0.9, 0.5)

## Opacidade do fundo da lacuna preenchida. Ela é tingida com a cor da CATEGORIA da palavra, e
## opacidade cheia roubaria a atenção da frase.
@export_range(0.0, 1.0, 0.01) var filled_opacity: float = 0.35

## Espaço para variáveis

var index: int = -1

var _word: GlossaryWord
# Guardado, e não passado adiante, porque configure() pode ser chamado antes de o nó estar pronto:
# sem isto, o checkmark do acerto se perderia no _ready.
var _is_correct: bool = false
# O botão esquerdo está pressionado nesta lacuna e o arraste ainda não começou: é o "clique curto"
# em potencial. O arraste (ou o mouse saindo) cancela.
var _press_pending: bool = false
# O arraste em curso saiu DESTA lacuna. NOTIFICATION_DRAG_END chega a todos os Controls da tela, e é
# isto que separa "o meu arraste acabou" de "acabou o arraste de alguém".
var _is_dragging: bool = false

## Espaço para variáveis onready

@onready var _label: Label = $WordLabel

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_exited.connect(_on_mouse_exited)
	_refresh()


# Arraste que termina sem ninguém aceitar esvazia a lacuna: a palavra volta pro glossário. É o mesmo
# desfecho de soltá-la em cima do glossário — soltar "no nada" não pode deixar o gesto pela metade.
func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _is_dragging:
		return
	_is_dragging = false
	if not is_inside_tree() or _word == null:
		return
	if not get_viewport().gui_is_drag_successful():
		print("[Profiling] - Palavra da lacuna %d solta fora: devolvida ao glossário" % index)
		cleared.emit(index)


func _gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT or _word == null:
		return

	if mouse_button.pressed:
		# Sem accept_event() aqui: é o Viewport que começa o arraste quando o mouse se move com o
		# botão pressionado, e consumir a pressão mataria o arraste.
		_press_pending = true
		return

	if _press_pending:
		_press_pending = false
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


# Arrastar a palavra PRA FORA da lacuna. O payload leva de onde ela saiu ("from_blank"), que é o que
# permite ao glossário aceitar a palavra de volta ao receber o soltar.
#
# Ser chamada já é a resposta de que o gesto é arraste, e não clique: o clique curto pendente morre
# aqui. O preview é a própria lacuna duplicada, deslocada meio tamanho pra ficar centrada no cursor
# (set_drag_preview põe o canto no mouse).
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _word == null:
		return null
	_press_pending = false
	_is_dragging = true

	# DUPLICATE_SCRIPTS sozinho: o padrão de duplicate() também copia as CONEXÕES de sinal, e o
	# preview não deve responder por esta palavra — ele é só um desenho seguindo o cursor.
	var preview: ProfilingBlank = duplicate(Node.DUPLICATE_SCRIPTS) as ProfilingBlank
	preview.custom_minimum_size = size
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)

	var holder: Control = Control.new()
	holder.add_child(preview)
	preview.position = -0.5 * size
	set_drag_preview(holder)

	preview.configure(index, _word, _is_correct)
	return { "word_id": _word.id, "from_blank": index }

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


# Redesenha a lacuna. Nada de StyleBox criado aqui: a moldura é a da cena, e o que muda é o
# tingimento (self_modulate) e o texto.
func _refresh() -> void:
	if _label == null:
		return

	if _word == null:
		_label.text = empty_text
		_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
		self_modulate = empty_tint
		return

	_label.text = _word.get_display_text() + (correct_glyph if _is_correct else "")
	if _is_correct:
		_label.modulate = correct_tint
		self_modulate = Color(correct_tint.r, correct_tint.g, correct_tint.b, filled_opacity)
		return

	# A palavra na lacuna aparece na cor da categoria dela: é o que deixa o jogador reler a frase
	# preenchida e ver de longe que pôs um nome onde a frase pedia um objeto.
	_label.modulate = Color.WHITE
	var tint: Color = _word.get_color()
	tint.a = filled_opacity
	self_modulate = tint


# O mouse saindo cancela o clique curto: o botão vai ser solto em outro lugar, e aquilo não é mais
# um clique nesta lacuna.
func _on_mouse_exited() -> void:
	_press_pending = false
