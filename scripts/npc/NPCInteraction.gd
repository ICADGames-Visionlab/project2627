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
class_name NPCInteraction
extends Area2D

@export var style: DialogueStyle = preload("res://resources/dialogue/dialogue_style.tres")

# Compartilhada entre TODAS as instâncias (uma por NPC): sem isso, clicar num segundo NPC durante a
# abordagem do primeiro disputaria o mesmo Player e a mesma DialogueCamera com duas sequências
# rodando juntas. Só uma abordagem por vez, em qualquer NPC.
static var _approach_in_progress: bool = false

@onready var _npc: NPC = get_parent()


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Contorno de hover (SPEC §11.4): só acende para NPC com conversa disponível, senão o jogador
# passaria o mouse por cima e a cidade inteira pareceria clicável.
func _on_mouse_entered() -> void:
	var definition: NPCDefinition = _npc.definition
	if definition != null and definition.conversation_id != &"":
		_npc.set_hover_outline(true)


func _on_mouse_exited() -> void:
	_npc.set_hover_outline(false)


func _input_event(viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	var definition: NPCDefinition = _npc.definition
	if definition == null or definition.conversation_id == &"" or _approach_in_progress:
		return
	viewport.set_input_as_handled()
	_start_conversation(definition)


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
