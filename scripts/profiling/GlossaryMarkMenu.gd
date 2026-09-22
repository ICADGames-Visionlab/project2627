## GlossaryMarkMenu - o retângulo que aparece acima de uma palavra do glossário, com o lixo e a
## estrela.
##
## COMO USAR: instancie scenes/profiling/GlossaryMarkMenu.tscn dentro da tela (fora de container,
## porque ele se posiciona sozinho) e aponte quem pede. Na tela de profiling ele já está na
## ProfilingScreen.tscn, e quem pede é o chique do glossário, pelo sinal mark_menu_requested.
##
## POR QUE NÃO É UM PopupMenu: um PopupMenu é uma JANELA, e janela aberta captura o clique de fora
## pra se fechar. O resultado era o bug de abrir o menu de uma palavra, clicar com o direito na
## palavra do lado e o segundo menu não abrir — o clique morria fechando o primeiro. Sendo um Control
## comum dentro da própria tela, o clique direito chega ao outro chip normalmente, e o menu só muda
## de lugar.
##
## O layout (tamanho, cantos, ícones dos botões) está na cena. Este script só abre, fecha e posiciona.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryMarkMenu
extends PanelContainer

## Espaço para sinais

## Emitido quando o jogador escolhe uma marca. Quem grava é quem escuta (a tela), porque a marca é
## estado do diário, e este nó não conhece o diário.
signal mark_chosen(word_id: StringName, kind: GlossaryMark.Kind)

## Espaço para variáveis exportadas

## Distância entre o retângulo e a palavra, em pixels.
@export var gap: float = 6.0

## Cor com que o botão da marca JÁ POSTA aparece — é o aviso de que aquele clique vai removê-la.
@export var active_modulate: Color = Color(1.0, 0.85, 0.4)

## Espaço para variáveis

var _word_id: StringName = &""

## Espaço para variáveis onready

@onready var _trash_button: Button = $Buttons/TrashButton
@onready var _star_button: Button = $Buttons/StarButton

## Espaço para funções nativas

func _ready() -> void:
	# Aparece sobre uma tela que pausa o jogo, então precisa responder com a árvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_trash_button.pressed.connect(_on_trash_pressed)
	_star_button.pressed.connect(_on_star_pressed)
	hide()


# Qualquer clique que não tenha sido consumido por um botão daqui (nem pelo chip, que reabre o menu
# em outro lugar) fecha o retângulo — é o que o jogador espera de um menu de contexto.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed:
		close()

## Espaço para funções personalizadas

# Abre o retângulo acima de uma palavra, ou o fecha se ele já estava aberto NAQUELA palavra (clicar
# de novo na mesma palavra é o gesto de desistir).
#
# chip_rect é o retângulo da palavra na tela, em coordenadas globais — quem sabe disso é o chip.
func toggle_for(word_id: StringName, chip_rect: Rect2, current: GlossaryMark.Kind) -> void:
	if visible and word_id == _word_id:
		close()
		return
	open_for(word_id, chip_rect, current)


# Abre o retângulo acima de uma palavra.
func open_for(word_id: StringName, chip_rect: Rect2, current: GlossaryMark.Kind) -> void:
	_word_id = word_id
	_trash_button.modulate = active_modulate if current == GlossaryMark.Kind.TRASH else Color.WHITE
	_star_button.modulate = active_modulate if current == GlossaryMark.Kind.STAR else Color.WHITE

	show()
	# O tamanho só existe depois de o nó se ajustar ao conteúdo, e a posição depende do tamanho.
	reset_size()
	global_position = Vector2(
		chip_rect.get_center().x - size.x * 0.5,
		chip_rect.position.y - size.y - gap)
	print("[Profiling] - Menu de marcas aberto para \"%s\"" % word_id)


# Fecha o retângulo.
func close() -> void:
	if not visible:
		return
	hide()
	_word_id = &""


# A palavra a que o retângulo está apontado agora, ou vazio quando ele está fechado.
func get_word_id() -> StringName:
	return _word_id


func _on_trash_pressed() -> void:
	_choose(GlossaryMark.Kind.TRASH)


func _on_star_pressed() -> void:
	_choose(GlossaryMark.Kind.STAR)


# Anuncia a escolha e fecha. Fechar aqui, e não em quem escuta, mantém o gesto inteiro num lugar só.
func _choose(kind: GlossaryMark.Kind) -> void:
	if _word_id == &"":
		return
	var chosen_word: StringName = _word_id
	close()
	mark_chosen.emit(chosen_word, kind)
