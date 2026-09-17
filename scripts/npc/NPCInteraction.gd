# NPCInteraction.gd — Detecção de clique e hover no NPC (SPEC §11.4, V7). Area2D na mesma layer "só
# picking" do InsightMarker (32768) e collision_mask = 0: precisa de layer não-zero pra o picking de
# física achar a Area2D, mas não detecta nem é detectada por nenhum corpo, então o Player não tem
# como esbarrar nela.
#
# _input_event (do picking de física) roda antes do _unhandled_input do Player, então clicar no NPC
# não faz o personagem sair andando até ele — o mesmo problema que o InsightInteractor resolve para
# os orbes.
class_name NPCInteraction
extends Area2D

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
	if definition == null or definition.conversation_id == &"":
		return
	viewport.set_input_as_handled()
	EventBus.conversation_requested.emit(definition.conversation_id, definition.id)
