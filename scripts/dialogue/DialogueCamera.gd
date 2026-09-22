# DialogueCamera.gd — PhantomCamera2D dedicada ao zoom de conversa: enquadra o Player e o NPC
# falando (FollowMode.GROUP centraliza sozinho no meio-termo dos dois) e assume a câmera do jogo
# enquanto ativa, com prioridade maior que a PlayerCamera (Player.tscn, priority 10). O
# PhantomCameraHost (City.tscn) faz o tween sozinho a cada troca de prioridade — nada aqui anima a
# câmera na mão.
#
# Vive parada (RESTING_PRIORITY) o jogo inteiro até NPCInteraction chamar engage(); devolve
# a câmera sozinha em conversation_ended, então nada precisa lembrar de "desengatar" depois de uma
# conversa.
#
# @tool ficaria faltando de propósito: a base é @tool para desenhar o retângulo de preview no
# editor (frame_preview), mas isso exigiria guardar _ready() com Engine.is_editor_hint() antes de
# tocar no EventBus (Autoload que não existe no editor — mesmo cuidado de InsightSource.gd) só por
# uma prévia visual que este nó não precisa: ele não tem comportamento nenhum fora do jogo rodando.
@warning_ignore("missing_tool")
class_name DialogueCamera
extends PhantomCamera2D

const ENGAGED_PRIORITY: int = 20
const RESTING_PRIORITY: int = 0   # o padrão de priority (0) já é este; existe só para dar nome.

# follow_mode (Group) e priority (0, RESTING_PRIORITY) vêm da cena: setados aqui em vez de lá
# rodariam depois de _enter_tree(), que já lê follow_mode para decidir como se comportar (ver
# phantom_camera_2d.gd) — setar cedo demais é assumir o valor padrão errado por um frame.


func _ready() -> void:
	EventBus.conversation_ended.connect(_on_conversation_ended)


# Enquadra os dois personagens e assume a câmera. Quem chama espera tween_completed (sinal do
# próprio PhantomCamera2D) para saber quando o zoom terminou.
func engage(first: Node2D, second: Node2D, target_zoom: float, duration: float) -> void:
	follow_targets = [first, second]
	zoom = Vector2.ONE * target_zoom
	tween_duration = duration
	priority = ENGAGED_PRIORITY


# A PlayerCamera (priority 10) volta a ser a de maior prioridade, então o Host tween de volta pra
# ela sozinho — com a duração/ease do tween_resource DELA, não do nosso.
func _on_conversation_ended(_conversation_id: StringName, _end_node_id: StringName) -> void:
	priority = RESTING_PRIORITY
