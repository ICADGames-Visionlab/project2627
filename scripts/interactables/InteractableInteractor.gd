## InteractableInteractor - os olhos e a mão do jogador sobre os objetos interagíveis (Interactable).
##
## Três trabalhos, todos a partir do jogador:
##   1. Segurar o botão direito do mouse, Alt ou LB do controle (ação "highlight_interactables") faz
##      brilhar todo objeto interagível que está no campo de visão, ou seja, na tela. Soltar apaga.
##   2. O objeto sob o cursor ganha o contorno branco de hover, igual ao do NPC.
##   3. O clique esquerdo num objeto aciona ele, e não vira movimento no esquema de clique para andar.
##
## Vive como filho do Player pelo mesmo motivo do InsightInteractor: ser filho é o que garante
## receber o clique ANTES do Player (a engine chama _unhandled_input primeiro nos nós mais adiante na
## árvore). Fora dele, clicar num objeto no esquema de clique também mandaria o personagem andar até o
## ponto clicado. E ele fica ANTES do InsightInteractor entre os filhos, para um orbe de insight
## desenhado por cima de um objeto ganhar o clique: o orbe é o alvo menor e mais específico.
class_name InteractableInteractor
extends Node

## Espaço para constantes

const HIGHLIGHT_ACTION: StringName = &"highlight_interactables"

## Espaço para variáveis exportadas

@export_group("Brilho")
# Cor do contorno de "mostrar interagíveis". Quente, para não se confundir com o branco do hover
# (o objeto que o clique vai pegar) nem com o verde dos orbes de insight de ambiente.
@export var highlight_color: Color = Color(1.0, 0.82, 0.35, 1.0)
# Pulsos por segundo. O pulso chama o olho para o objeto; parado, um contorno fino some no cenário.
@export_range(0.1, 4.0, 0.1) var pulse_speed: float = 1.2
# Opacidade do contorno no vale do pulso. Acima de zero para o objeto nunca "apagar" enquanto o
# jogador segura a tecla.
@export_range(0.0, 1.0, 0.05) var min_outline_alpha: float = 0.45
# Quanto o desenho clareia no pico do pulso (0.2 = 20% mais claro).
@export_range(0.0, 1.0, 0.05) var brighten_amount: float = 0.4

## Espaço para variáveis

var _is_highlighting: bool = false
var _pulse_time: float = 0.0
var _hovered: Interactable = null
# Objetos com brilho aceso agora. Guardados para apagar exatamente esses ao soltar a tecla ou ao
# saírem da tela, sem percorrer o grupo inteiro de novo.
var _lit: Array[Interactable] = []

# Travas: conversa aberta (ou a caminho) e tela de profiling. Separadas porque abrem e fecham por
# eventos diferentes; um bool só seria destravado pela primeira que fechasse.
var _in_conversation: bool = false
var _in_profiling: bool = false

## Espaço para variáveis onready

@onready var _player: Player = get_parent() as Player

## Espaço para funções nativas

func _ready() -> void:
	if _player == null:
		push_warning("[Interactables] - InteractableInteractor fora de um Player: a aproximação até o objeto não vai funcionar")
	# Durante uma conversa o mundo não responde (mesma regra do Player e do InsightInteractor), e
	# na tela de profiling o botão direito é do glossário: sem esta trava, marcar uma palavra
	# acenderia os objetos do mundo atrás da tela.
	EventBus.conversation_approach_started.connect(_on_conversation_started)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.conversation_ended.connect(_on_conversation_ended)
	EventBus.profiling_opened.connect(_on_profiling_opened)
	EventBus.profiling_closed.connect(_on_profiling_closed)


func _process(delta: float) -> void:
	if _is_locked():
		_set_hovered(null)
		_stop_highlight()
		return
	_set_hovered(_object_at(get_viewport().get_mouse_position(), true))
	_update_highlight(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _is_locked():
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	var target: Interactable = _object_at(mouse_button.position, false)
	if target == null:
		return
	# Consome antes do Player (ver o topo do arquivo): o clique é do objeto, não do chão.
	get_viewport().set_input_as_handled()
	target.interact(_player)

## Espaço para funções personalizadas

# O objeto sob um ponto da tela, ou null. Com dois objetos sobrepostos, ganha o de maior Y no mundo,
# que é o desenhado por cima no Y-sort: o jogador clica no que está vendo na frente.
# check_gui: no hover, um painel de interface (inventário aberto) na frente do objeto esconde o
# objeto. No clique não precisa: um clique que um Control pegou nem chega ao _unhandled_input.
func _object_at(screen_point: Vector2, check_gui: bool) -> Interactable:
	if check_gui and get_viewport().gui_get_hovered_control() != null:
		return null
	var best: Interactable = null
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var interactable: Interactable = node as Interactable
		if interactable == null or not interactable.is_available():
			continue
		if not interactable.get_screen_rect().has_point(screen_point):
			continue
		if best == null or interactable.global_position.y > best.global_position.y:
			best = interactable
	return best


# Acende os objetos no campo de visão enquanto a tecla está segura, com um pulso só para todos.
# "Campo de visão" é a tela: o que a câmera mostra é o que o jogador está vendo. Um objeto
# parcialmente na borda conta, porque o jogador vê a parte dele que está dentro.
func _update_highlight(delta: float) -> void:
	var holding: bool = Input.is_action_pressed(HIGHLIGHT_ACTION)
	if not holding:
		_stop_highlight()
		return

	_pulse_time += delta
	var wave: float = 0.5 + 0.5 * sin(_pulse_time * TAU * pulse_speed)
	var color: Color = highlight_color
	color.a = lerpf(min_outline_alpha, 1.0, wave)

	var screen_rect: Rect2 = get_viewport().get_visible_rect()
	var now_lit: Array[Interactable] = []
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var interactable: Interactable = node as Interactable
		if interactable == null or not interactable.is_available():
			continue
		if screen_rect.intersects(interactable.get_screen_rect()):
			interactable.set_highlight(color, brighten_amount * wave)
			now_lit.append(interactable)

	# Quem saiu da tela (o jogador andou segurando a tecla) apaga.
	for interactable: Interactable in _lit:
		if is_instance_valid(interactable) and not now_lit.has(interactable):
			interactable.clear_highlight()
	_lit = now_lit

	if not _is_highlighting:
		_is_highlighting = true
		print("[Interactables] - Destaque ligado: %d objeto(s) no campo de visão" % _lit.size())


# Apaga todo brilho aceso. Chamado ao soltar a tecla e ao travar (conversa, profiling).
func _stop_highlight() -> void:
	if not _is_highlighting:
		return
	_is_highlighting = false
	_pulse_time = 0.0
	for interactable: Interactable in _lit:
		if is_instance_valid(interactable):
			interactable.clear_highlight()
	_lit.clear()
	print("[Interactables] - Destaque desligado")


# Troca o objeto com contorno de hover. Tolera o anterior já ter sido liberado (evidência coletada).
func _set_hovered(interactable: Interactable) -> void:
	if not is_instance_valid(_hovered):
		_hovered = null
	if interactable == _hovered:
		return
	if _hovered != null:
		_hovered.set_hovered(false)
	_hovered = interactable
	if _hovered != null:
		_hovered.set_hovered(true)


func _is_locked() -> bool:
	return _in_conversation or _in_profiling


func _on_conversation_started(_conversation_id: StringName, _initiator_id: StringName) -> void:
	_in_conversation = true


func _on_conversation_ended(_conversation_id: StringName, _end_node_id: StringName) -> void:
	_in_conversation = false


func _on_profiling_opened(_npc_id: StringName) -> void:
	_in_profiling = true


func _on_profiling_closed(_npc_id: StringName) -> void:
	_in_profiling = false
