## GlossaryWordChip - o retângulo de uma palavra do glossário: a palavra, a cor da categoria dela e
## a marca que o jogador pôs nela.
##
## COMO USAR: o layout inteiro está em scenes/profiling/GlossaryWordChip.tscn — é lá que se mexe em
## fonte, cantos, borda e espaçamento. Este script só põe o dado no lugar. Quem instancia é o
## GlossaryPanel (um chip por palavra descoberta), pela cena apontada no Inspector dele.
##
## POR QUE PanelContainer E NÃO Button: a cor do chip é a cor da CATEGORIA, que é dado, e a única
## forma de tingir sem escrever StyleBox em código é o self_modulate por cima de um StyleBox branco
## da cena. Num Button, o self_modulate tingiria o texto junto com o fundo, e o contraste da palavra
## (preto no amarelo, branco no azul) iria embora. Aqui o fundo é tingido e o Label tem a cor dele.
##
## CLIQUE E ARRASTE SÃO GESTOS DIFERENTES, e é isso que _gui_input separa:
##
##   arrastar         -> leva a palavra pra uma lacuna da página (o jeito do GDD)
##   clique curto     -> atalho: a página põe a palavra na primeira lacuna vazia, ou a devolve ao
##                       glossário se ela já estiver em uma. Existe pra quem joga de teclado e
##                       controle, que não tem como arrastar.
##   clique direito   -> pede o retângulo de marcas (lixo e estrela), que é um nó da tela, não uma
##                       janela: ver GlossaryMarkMenu.
##
## O atalho do clique só dispara ao SOLTAR o botão, e só se o arraste não tiver começado no meio —
## senão pegar a palavra pra arrastar já a mandava pra lacuna, e o arraste ficava impossível.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryWordChip
extends PanelContainer

## Espaço para sinais

## Emitido no clique curto: o jogador quer usar (ou devolver) esta palavra.
signal word_activated(word_id: StringName)

## Emitido no clique direito, com o retângulo do chip na tela — é ele que diz onde o menu de marcas
## deve aparecer ("acima da palavra", no GDD).
signal mark_menu_requested(word_id: StringName, chip_rect: Rect2)

## Emitido quando um arraste começado neste chip termina sem ninguém aceitar: a palavra volta pro
## glossário (o que, se ela estava numa lacuna, esvazia aquela lacuna).
signal word_returned(word_id: StringName)

## Espaço para variáveis exportadas

@export_group("Cor")

## Quanto a cor do chip clareia quando o mouse está em cima. Zero desliga o destaque.
@export_range(0.0, 1.0, 0.01) var hover_lighten: float = 0.18

## Opacidade do chip cuja palavra já está numa lacuna da página.
@export_range(0.0, 1.0, 0.01) var in_use_opacity: float = 0.45

@export_group("Animação do hover")

## Quanto a palavra cresce com o mouse em cima (1.0 = não cresce).
@export_range(1.0, 1.5, 0.01) var hover_scale: float = 1.06

## Quanto a palavra torce com o mouse em cima, em graus. Valores pequenos: é um empurrãozinho, não
## uma cambalhota.
@export_range(-15.0, 15.0, 0.1) var hover_rotation_degrees: float = 2.0

## Velocidade do lerp que leva a palavra até o estado de hover (e de volta). Maior = mais seco.
@export_range(1.0, 40.0, 0.5) var hover_lerp_speed: float = 14.0

## Espaço para constantes

# Abaixo desta diferença o lerp é considerado terminado, e o _process desliga: um chip parado não
# precisa de quadro, e o glossário tem dezenas deles.
const SETTLE_EPSILON: float = 0.001

## Espaço para variáveis

var word: GlossaryWord

var _mark: GlossaryMark.Kind = GlossaryMark.Kind.NONE
var _in_use: bool = false
var _is_hovered: bool = false
# O botão esquerdo está pressionado em cima deste chip e o arraste ainda não começou: é o "clique
# curto" em potencial. O arraste (ou o mouse saindo) cancela.
var _press_pending: bool = false
# O arraste em curso saiu DESTE chip. NOTIFICATION_DRAG_END chega a todos os Controls da tela, e é
# isto que separa "o meu arraste acabou" de "acabou o arraste de alguém".
var _is_dragging: bool = false

## Espaço para variáveis onready

@onready var _label: Label = $Label

## Espaço para funções nativas

func _ready() -> void:
	# O chip vive dentro de uma tela que roda com o jogo pausado, e precisa responder ao mouse.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_pivot)
	_update_pivot()
	_refresh()
	set_process(false)


# Leva a escala e a rotação até o estado de hover, e desliga sozinho quando chega. O lerp é
# exponencial (1 - exp(-v*dt)) pra ficar igual em qualquer taxa de quadros.
func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-hover_lerp_speed * delta)
	var target_scale: float = hover_scale if _is_hovered else 1.0
	var target_rotation: float = deg_to_rad(hover_rotation_degrees) if _is_hovered else 0.0

	scale = scale.lerp(Vector2(target_scale, target_scale), weight)
	rotation = lerpf(rotation, target_rotation, weight)

	if absf(scale.x - target_scale) < SETTLE_EPSILON \
			and absf(rotation - target_rotation) < SETTLE_EPSILON:
		scale = Vector2(target_scale, target_scale)
		rotation = target_rotation
		set_process(false)


# Um arraste que termina sem ninguém aceitar devolve a palavra ao glossário. Sem isto, soltar a
# palavra no meio do nada a deixava presa na lacuna de onde ela veio, e o gesto não tinha desfecho.
#
# gui_is_drag_successful() é a pergunta certa: "alguém aceitou o drop?". Quando o destino é uma
# lacuna (ou o próprio glossário, que aceita palavra vinda de lacuna), o drop foi aceito e este
# bloco não faz nada — quem resolve é o _drop_data de lá.
func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _is_dragging:
		return
	_is_dragging = false
	if not is_inside_tree() or word == null:
		return
	if not get_viewport().gui_is_drag_successful():
		print("[Profiling] - Arraste de \"%s\" solto fora de lacuna: palavra devolvida" % word.id)
		word_returned.emit(word.id)


func _gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or word == null:
		return

	if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		accept_event()
		_press_pending = false
		mark_menu_requested.emit(word.id, get_global_rect())
		return

	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_button.pressed:
		# Sem accept_event() aqui de propósito: é o próprio Viewport que, com o botão pressionado
		# sobre um Control que tem _get_drag_data, começa o arraste quando o mouse se move. Consumir
		# o evento de pressão mataria o arraste.
		_press_pending = true
		return

	# Soltou: virou clique curto, se o arraste não tiver começado no meio.
	if _press_pending:
		_press_pending = false
		accept_event()
		word_activated.emit(word.id)


# O arrasto que leva a palavra pra lacuna. O dado é o ID da palavra, e não o recurso: é o id que a
# lacuna manda pro diário, e passar o recurso convidaria a tela a mexer no conteúdo.
#
# Ser chamada JÁ É a resposta de que o gesto é arraste, e não clique: o clique curto pendente morre
# aqui.
#
# O PREVIEW FICA CENTRADO NO MOUSE. set_drag_preview() põe o canto superior esquerdo do nó no
# cursor, então o que se passa é um Control vazio com o chip DENTRO dele, deslocado meio tamanho —
# é a única forma de centralizar, porque a posição do preview é escrita pela engine a cada quadro.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if word == null:
		return null
	_press_pending = false
	_is_dragging = true

	# DUPLICATE_SCRIPTS sozinho: o padrão de duplicate() também copia as CONEXÕES de sinal, e o
	# preview não deve responder por esta palavra — ele é só um desenho seguindo o cursor.
	var preview: GlossaryWordChip = duplicate(Node.DUPLICATE_SCRIPTS) as GlossaryWordChip
	preview.custom_minimum_size = size
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)

	var holder: Control = Control.new()
	holder.add_child(preview)
	preview.position = -0.5 * size
	set_drag_preview(holder)

	# O duplicate() copia o nó, não o estado: configure() precisa rodar de novo, e só depois de ele
	# estar na árvore (o _ready dele é que acha o Label).
	preview.configure(word, _mark, false)
	return { "word_id": word.id }

## Espaço para funções personalizadas

# Põe uma palavra no chip: texto, cor da categoria, marca e se ela já está em uso numa lacuna.
#
# in_use deixa o chip apagado em vez de escondê-lo: o GDD conta as palavras descobertas ("23/36"),
# e uma palavra que desaparece do glossário ao ser usada faria o jogador achar que a perdeu. Ela
# continua clicável de propósito — clicar nela é o atalho que a devolve ao glossário.
func configure(p_word: GlossaryWord, kind: GlossaryMark.Kind, in_use: bool) -> void:
	word = p_word
	_mark = kind
	_in_use = in_use
	_refresh()


# A marca atual do chip. O painel usa na hora de filtrar sem reler o diário palavra por palavra.
func get_mark() -> GlossaryMark.Kind:
	return _mark


# Redesenha o chip a partir do que está guardado. Nada de StyleBox criado aqui: o estilo é o da
# cena, e o que muda é o TINGIMENTO (self_modulate) e a opacidade.
func _refresh() -> void:
	if _label == null:
		return

	if word == null:
		_label.text = ""
		return

	var glyph: String = GlossaryMark.get_glyph(_mark)
	_label.text = word.get_display_text() if glyph.is_empty() \
		else "%s %s" % [glyph, word.get_display_text()]

	var tint: Color = word.get_color()
	if _is_hovered:
		tint = tint.lightened(hover_lighten)
	tint.a = in_use_opacity if _in_use else 1.0
	# self_modulate tinge só o fundo deste nó: o Label é filho, e a cor de leitura dele não é
	# afetada. É o que substitui o StyleBox por categoria que antes era montado em código.
	self_modulate = tint
	# A cor da palavra vem do contraste com a cor da categoria (preto no amarelo, branco no azul).
	# modulate, e não override de tema, pra a fonte escolhida na cena continuar valendo.
	_label.modulate = word.category.get_contrast_color() if word.category != null else Color.WHITE


# O pivô no centro é o que faz a palavra crescer e torcer no lugar, em vez de escorregar pra
# direita. Refeito a cada mudança de tamanho, porque o texto define a largura do chip.
func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	_is_hovered = true
	set_process(true)
	_refresh()


func _on_mouse_exited() -> void:
	_is_hovered = false
	# O mouse saindo cancela o clique curto: o botão vai ser solto em outro lugar, e aquilo não é
	# mais um clique nesta palavra.
	_press_pending = false
	set_process(true)
	_refresh()
