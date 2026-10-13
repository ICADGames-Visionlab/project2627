# NPCInteraction.gd — Detecção de clique e hover no NPC (SPEC §11.4, V7), e a sequência que um
# clique dispara: trava o jogador, anda até perto do NPC, aproxima a câmera dos dois e só então
# pede a conversa — a DialogueScreen só entra em cena no fim disso (ver _start_conversation).
# Area2D na mesma layer "só picking" do InsightMarker (32768) e collision_mask = 0: precisa de
# layer não-zero pra o picking de física achar a Area2D, mas não detecta nem é detectada por
# nenhum corpo, então o Player não tem como esbarrar nela.
#
# _input_event (do picking de física) roda antes do _unhandled_input do Player, então clicar no NPC
# não faz o personagem sair andando até ele — o mesmo problema que o InsightInteractor resolve para
# os orbes.
#
# NO TECLADO/CONTROLE: o NPC entra no foco do InsightInteractor (o anel que segue o alvo mais perto,
# acionado pelo A ou pelo E) cumprindo o contrato de FocusTargets — ver os métodos da seção "Foco de
# teclado/controle" lá embaixo. Acionar pelo foco é exatamente o mesmo que clicar.
class_name NPCInteraction
extends Area2D

@export var style: DialogueStyle = preload("res://resources/dialogue/dialogue_style.tres")

# Compartilhada entre TODAS as instâncias (uma por NPC): sem isso, clicar num segundo NPC durante a
# abordagem do primeiro disputaria o mesmo Player e a mesma DialogueCamera com duas sequências
# rodando juntas. Só uma abordagem por vez, em qualquer NPC.
static var _approach_in_progress: bool = false

# O contorno branco acende por dois motivos independentes: o mouse em cima (hover) ou o foco de
# teclado/controle. Guardados separados porque cada um apaga por um caminho diferente.
var _is_hovered: bool = false
var _is_focused: bool = false
# No modo teclado/controle o hover do mouse não conta (ver set_mouse_hover_suppressed).
var _is_hover_suppressed: bool = false

@onready var _npc: NPC = get_parent()
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	add_to_group(FocusTargets.GROUP)


# Contorno de hover (SPEC §11.4): só acende para NPC com conversa disponível, senão o jogador
# passaria o mouse por cima e a cidade inteira pareceria clicável.
func _on_mouse_entered() -> void:
	if _is_hover_suppressed:
		return
	_is_hovered = _has_conversation()
	_refresh_outline()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh_outline()


func _input_event(viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not can_be_focused():
		return
	viewport.set_input_as_handled()
	_start_conversation(_npc.definition)


# --- Foco de teclado/controle (contrato de FocusTargets) ---

# Posição do NPC no mundo: é dela que o foco mede "mais perto do jogador".
func get_focus_world_position() -> Vector2:
	return _npc.global_position


# A área de clique do NPC na tela. O foco só oferece NPC que aparece na tela, como o mouse.
func get_focus_screen_rect() -> Rect2:
	var rectangle: RectangleShape2D = _shape.shape as RectangleShape2D
	if rectangle == null:
		return Rect2(get_global_transform_with_canvas().origin, Vector2.ZERO)
	return _shape.get_global_transform_with_canvas() * Rect2(-rectangle.size * 0.5, rectangle.size)


# A mesma regra do clique: NPC com conversa, nenhuma abordagem em andamento, e na tela.
func can_be_focused() -> bool:
	return _has_conversation() and not _approach_in_progress and is_visible_in_tree()


# Acende/apaga o contorno do foco. Quem decide qual alvo tem o foco é o InsightInteractor.
func set_focused(focused: bool) -> void:
	_is_focused = focused
	_refresh_outline()


# O mesmo que o clique: trava o jogador, aproxima e abre a conversa.
func activate_focus(_player: Player) -> void:
	if not can_be_focused():
		return
	print("[Dialogue] - NPC \"%s\" acionado pelo teclado/controle" % _npc.definition.id)
	_start_conversation(_npc.definition)


# Liga/desliga o hover do mouse. Ligado o modo teclado/controle, um NPC que estava sob o cursor parado
# apaga, para o foco ser o único destaque.
func set_mouse_hover_suppressed(suppressed: bool) -> void:
	_is_hover_suppressed = suppressed
	if suppressed:
		_is_hovered = false
	_refresh_outline()


# Diz se este NPC tem conversa (sem ela não há o que clicar nem focar).
func _has_conversation() -> bool:
	var definition: NPCDefinition = _npc.definition
	return definition != null and definition.conversation_id != &""


# O contorno aceso é o OU do hover com o foco.
func _refresh_outline() -> void:
	_npc.set_hover_outline(_is_hovered or _is_focused)


# Trava o jogador (via conversation_approach_started), anda até perto do NPC, aproxima a câmera de
# todo mundo que está na conversa e só então pede a conversa. Sem Player ou DialogueCamera na cena
# (cena de teste, por exemplo), pula a etapa que faltar e pede a conversa direto — degradação
# graciosa, mesmo espírito do "sem Pathfinder" no Player/NPC.
func _start_conversation(definition: NPCDefinition) -> void:
	_approach_in_progress = true
	EventBus.conversation_approach_started.emit(definition.conversation_id, definition.id)

	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.start_conversation_approach(_approach_point(player.global_position))
		await player.conversation_approach_arrived
		await _zoom_in(player, DialogueCatalog.cast_for(
			DialogueCatalog.read_participants(definition.conversation_id), definition.id))

	_approach_in_progress = false
	EventBus.conversation_requested.emit(definition.conversation_id, definition.id)


# Ponto a style.approach_distance do NPC, na direção de onde o jogador já está — mantém distância
# sem empurrar o corpo dele (SPEC §11.4).
func _approach_point(from: Vector2) -> Vector2:
	var offset: Vector2 = from - _npc.global_position
	if offset.is_zero_approx():
		offset = Vector2.DOWN
	return _npc.global_position + offset.normalized() * style.approach_distance


# Aproxima a DialogueCamera do Player e dos NPCs da conversa, e espera o tween dela terminar. Sem
# DialogueCamera na cena, não há o que esperar.
func _zoom_in(player: Player, participants: Array[StringName]) -> void:
	var camera: DialogueCamera = get_tree().get_first_node_in_group(&"dialogue_camera") as DialogueCamera
	if camera == null:
		return
	var targets: Array[Node2D] = [player as Node2D]
	targets.append_array(_participant_bodies(participants))
	camera.engage(targets, style.camera_zoom, style.camera_zoom_duration)
	await camera.tween_completed


# Os corpos dos NPCs do elenco que entram no enquadramento: quem está nesta cena agora e perto o
# bastante do NPC clicado. O limite existe porque um participante do outro lado da cidade (rotina
# que separou os dois) puxaria o enquadramento pra longe e tiraria a conversa da tela; ele continua
# falando normalmente, só não é enquadrado.
func _participant_bodies(participants: Array[StringName]) -> Array[Node2D]:
	var bodies: Array[Node2D] = []
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null:
		return [_npc as Node2D]

	for id: StringName in participants:
		var body: NPC = director.get_body(id)
		if body == null:
			print("[Dialogue] - NPC \"%s\" não está nesta cena; a conversa segue sem ele no enquadramento" % id)
			continue
		if body != _npc and body.global_position.distance_to(_npc.global_position) > style.camera_group_max_distance:
			print("[Dialogue] - NPC \"%s\" está longe demais; fora do enquadramento da conversa" % id)
			continue
		bodies.append(body)

	# Cena montada à mão (teste), em que o director não conhece nenhum destes corpos: enquadrar o
	# NPC clicado ainda é melhor que enquadrar só o jogador.
	if bodies.is_empty():
		bodies.append(_npc)
	return bodies
