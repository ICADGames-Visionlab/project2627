## GlossaryWordChip - o retângulo de uma palavra do glossário: a palavra, a cor da categoria dela e
## a marca que o jogador pôs nela.
##
## COMO USAR: ninguém instancia isto à mão. O GlossaryPanel cria um chip por palavra descoberta e
## chama configure(). O chip não conhece o diário nem a página: ele avisa por signal, e quem escuta
## decide o que acontece.
##
## O QUE ELE FAZ:
##
##   arrastar         -> leva a palavra pra uma lacuna da página (o jeito do GDD)
##   clique esquerdo  -> atalho: a página põe a palavra na primeira lacuna vazia, ou a devolve ao
##                       glossário se ela já estiver em uma. Existe pra quem joga de teclado e
##                       controle, que não tem como arrastar.
##   clique direito   -> abre o retângulo de marcas, com lixo e estrela
##
## PLACEHOLDER: a marca aparece como um glifo de texto antes da palavra (ver GlossaryMark), porque
## não há ícone de arte ainda. Quando os ícones existirem, muda só o desenho — o estado das marcas
## vive no ProfilingJournal.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryWordChip
extends Button

## Espaço para sinais

## Emitido no clique esquerdo: o jogador quer usar (ou devolver) esta palavra.
signal word_activated(word_id: StringName)

## Emitido quando o jogador escolhe uma marca no retângulo do clique direito.
signal mark_chosen(word_id: StringName, kind: GlossaryMark.Kind)

## Espaço para constantes

# Ids dos itens do retângulo de marcas. Dois itens, dois ids — não vale a pena uma lista pra isso, e
# id explícito deixa o match do handler legível.
const MENU_ID_TRASH: int = 0
const MENU_ID_STAR: int = 1

## Espaço para variáveis

var word: GlossaryWord

var _mark: GlossaryMark.Kind = GlossaryMark.Kind.NONE
var _mark_menu: PopupMenu

## Espaço para funções nativas

func _ready() -> void:
	# O chip vive dentro de uma tela que roda com o jogo pausado, e o botão precisa responder.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# O texto já vem traduzido de GlossaryWord.get_display_text(). Sem isto o Godot tentaria traduzir
	# a PALAVRA como se ela fosse uma chave do CSV.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(_on_pressed)


# O Button trata o clique esquerdo sozinho; o direito é o menu de marcas do GDD, e é aqui que ele é
# pescado antes de o botão engolir o evento.
func _gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		_open_mark_menu()


# O arrasto que leva a palavra pra lacuna. O dado é o ID da palavra, e não o recurso: é o id que a
# lacuna manda pro diário, e passar o recurso convidaria a tela a mexer no conteúdo.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if word == null:
		return null

	var preview: Button = Button.new()
	preview.text = text
	preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview.add_theme_stylebox_override("normal", _build_style(0.95))
	preview.add_theme_color_override("font_color", _get_text_color())
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
	set_drag_preview(preview)

	return { "word_id": word.id }

## Espaço para funções personalizadas

# Põe uma palavra no chip: texto, cor da categoria, marca e se ela já está em uso numa lacuna.
#
# in_use deixa o chip apagado em vez de escondê-lo: o GDD conta as palavras descobertas ("23/36"),
# e uma palavra que desaparece do glossário ao ser usada faria o jogador achar que a perdeu.
func configure(p_word: GlossaryWord, kind: GlossaryMark.Kind, in_use: bool) -> void:
	word = p_word
	_mark = kind
	if word == null:
		text = ""
		return

	var glyph: String = GlossaryMark.get_glyph(kind)
	text = word.get_display_text() if glyph.is_empty() else "%s %s" % [glyph, word.get_display_text()]

	add_theme_stylebox_override("normal", _build_style(1.0))
	add_theme_stylebox_override("hover", _build_style(1.0, true))
	add_theme_stylebox_override("pressed", _build_style(1.0, true))
	add_theme_color_override("font_color", _get_text_color())
	add_theme_color_override("font_hover_color", _get_text_color())
	add_theme_color_override("font_pressed_color", _get_text_color())
	# Palavra em uso continua clicável de propósito: clicar nela é o atalho que a devolve ao
	# glossário (quem resolve isso é a página, ao receber word_activated).
	modulate = Color(1.0, 1.0, 1.0, 0.45 if in_use else 1.0)


# A marca atual do chip. O painel usa na hora de filtrar sem reler o diário palavra por palavra.
func get_mark() -> GlossaryMark.Kind:
	return _mark


# O retângulo de marcas do clique direito: lixo e estrela, acima da palavra, como no GDD.
#
# Escolher a marca que já está posta a REMOVE, e quem decide isso é ProfilingJournal.set_mark — o
# chip só anuncia a escolha. Por isso o item aparece com um "—" quando a marca já está lá: é o
# aviso de que aquele clique vai tirá-la.
func _open_mark_menu() -> void:
	if word == null:
		return

	if _mark_menu == null:
		_mark_menu = PopupMenu.new()
		_mark_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		_mark_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_mark_menu.id_pressed.connect(_on_mark_menu_id_pressed)
		add_child(_mark_menu)

	_mark_menu.clear()
	_mark_menu.add_item(_describe_option(GlossaryMark.Kind.TRASH), MENU_ID_TRASH)
	_mark_menu.add_item(_describe_option(GlossaryMark.Kind.STAR), MENU_ID_STAR)

	# global_position é em coordenadas de tela, que é o que popup() espera. O tamanho vem em zero de
	# propósito: o PopupMenu se dimensiona pelo conteúdo.
	var origin: Vector2 = global_position + Vector2(0.0, -size.y)
	_mark_menu.popup(Rect2i(Vector2i(origin), Vector2i.ZERO))


# O texto de um item do retângulo de marcas.
func _describe_option(kind: GlossaryMark.Kind) -> String:
	var glyph: String = GlossaryMark.get_glyph(kind)
	return glyph if _mark != kind else glyph + " —"


func _on_mark_menu_id_pressed(id: int) -> void:
	if word == null:
		return
	match id:
		MENU_ID_TRASH:
			mark_chosen.emit(word.id, GlossaryMark.Kind.TRASH)
		MENU_ID_STAR:
			mark_chosen.emit(word.id, GlossaryMark.Kind.STAR)


func _on_pressed() -> void:
	if word != null:
		word_activated.emit(word.id)


# O fundo do chip, na cor da categoria da palavra.
func _build_style(alpha: float, highlight: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var base: Color = word.get_color() if word != null else Color(0.6, 0.6, 0.6)
	if highlight:
		base = base.lightened(0.15)
	base.a = alpha
	style.bg_color = base
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


# A cor do texto que se lê em cima da cor da categoria (preto no amarelo, branco no azul).
func _get_text_color() -> Color:
	if word == null or word.category == null:
		return Color.WHITE
	return word.category.get_contrast_color()
