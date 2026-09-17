## NPC - o corpo de um NPC em cena: anda até onde a rotina manda, toca a animação das 8 direções e
## mostra o nome acima da cabeça.
##
## Este script NÃO decide nada sobre rotina, horário ou emoção — quem decide é o NPCDirector, que
## instancia este corpo e manda ir a um ponto. A divisão é de propósito: o corpo é a camada TÁTICA
## (como chegar lá, desviando de prédio e desistindo quando trava) e o diretor é a ESTRATÉGICA
## (onde ele deveria estar agora). É a mesma separação que o Creation Engine faz entre os AI
## packages e a navegação do ator.
##
## COMO USAR (só o NPCDirector faz isso):
##
##     var npc: NPC = npc_scene.instantiate()
##     parent.add_child(npc)
##     npc.configure(definition, emotion)
##     npc.snap_to(posicao)     # aparecer já no lugar
##     npc.walk_to(posicao)     # ir andando até o lugar
##
## O guia completo está em docs/sistema_de_npc.md.
class_name NPC
extends CharacterBody2D

## Espaço para sinais

# Emitido quando o NPC alcança o ponto que o diretor pediu. Emissor e ouvinte são o NPC e o
# NPCDirector, que vivem na mesma cena e têm relação direta e permanente: por isso é um Signal
# local e não um evento no EventBus (ver a regra em docs/event_bus.md).
signal arrived

# Emitido só quando o estado de movimento muda — mesma ideia do sinal homônimo do Player: a troca
# de animação não precisa (e não deve) rodar a cada frame.
signal movement_state_changed(is_moving: bool, facing_direction: Isometric.Facing)

## Espaço para constantes

# Distância da tela até o ponto abaixo da qual ele é considerado alcançado. Não é balanceamento: é
# a folga técnica que impede o NPC de oscilar em volta do alvo por nunca cair exatamente em cima.
const ARRIVAL_DISTANCE: float = 8.0

# Fração da velocidade abaixo da qual o NPC é considerado travado, e por quanto tempo contínuo.
# Mesmos critérios do Player: roçar numa quina custa um ou dois frames lentos e não pode custar o
# trajeto inteiro.
const BLOCKED_SPEED_FRACTION: float = 0.1
const BLOCKED_GRACE_SECONDS: float = 0.4

## Espaço para variáveis exportadas

## Achatamento do eixo Y que alinha a direção do movimento aos eixos do losango isométrico. Mesmo
## significado (e mesmo valor padrão) do campo homônimo do Player — ver Isometric.gd.
@export_range(0.5, 1.0, 0.01) var isometric_y_ratio: float = 0.5

## Velocidade do movimento vertical como fração da horizontal. Ver o comentário longo no Player:
## é o botão de sensação, não tem valor geometricamente "certo".
@export_range(0.5, 1.0, 0.01) var vertical_speed_factor: float = 0.75

## Quanto tempo ele espera antes de tentar traçar o caminho de novo depois de falhar ou travar.
@export var repath_interval: float = 1.5

## Depois de quantas tentativas frustradas ele desiste de andar e simplesmente assume a posição do
## waypoint. A rotina é um compromisso: é melhor o NPC estar no lugar certo do que ficar encalhado
## num vão estreito pelo resto do dia.
@export var give_up_attempts: int = 3

## Duração do fade ao aparecer e ao desaparecer (quando a rotina o manda pra outra cena).
@export var fade_duration: float = 0.3

## Espessura do contorno branco de hover (SPEC §11.4), em texels da textura de origem — ver
## resources/shaders/sprite_outline.gdshader. A NPCInteraction liga e desliga com o mouse.
@export var hover_outline_width: float = 1.0

## Espaço para variáveis

# Quem este NPC é. Preenchido por configure(), nunca aqui.
var definition: NPCDefinition

# Desenha o caminho atual por cima da cena. Ligado pelo menu de debug, via o NPCDirector.
var draw_path: bool = false:
	set(value):
		draw_path = value
		queue_redraw()

var _speed: float = 220.0

# Caminho que ele está percorrendo e em qual ponto dele está. Vem pronto do Pathfinder. Caminho
# vazio significa "sem destino", então não precisa de bandeira separada.
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0

# Para onde ele foi mandado (o ponto final, não o trecho atual). Guardado pra poder tentar de novo
# e pra, em último caso, assumir a posição.
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false

var _blocked_time: float = 0.0
var _retry_time: float = 0.0
var _attempts: int = 0

var _is_moving: bool = false
var _facing: Isometric.Facing = Isometric.Facing.S

# Segurado por uma conversa (SPEC §11.4): cancela o caminho e ignora walk_to() até release().
var _is_held: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _name_label: Label = $NameLabel

## Espaço para funções nativas

func _ready() -> void:
	movement_state_changed.connect(_on_movement_state_changed)
	_play_animation()


func _physics_process(delta: float) -> void:
	# O tempo parado (diálogo, cutscene, troca de cena, fim do dia) para a cidade junto. Sem isto,
	# os NPCs continuariam cumprindo rotina durante uma conversa em que o relógio está congelado.
	if not GameClock.is_running() or GameClock.is_frozen():
		velocity = Vector2.ZERO
		_update_movement_state(Vector2.ZERO)
		return

	var direction: Vector2 = _get_path_direction()
	velocity = Isometric.screen_velocity(direction, _speed, isometric_y_ratio, vertical_speed_factor)
	move_and_slide()

	_handle_blocked(delta)
	_handle_retry(delta)
	_update_movement_state(direction)

	if draw_path:
		queue_redraw()


func _draw() -> void:
	if not draw_path or _path.is_empty():
		return

	# O que FALTA percorrer, a partir de onde ele está — diferente do desenho do Pathfinder, que
	# mostra a rota inteira como foi pedida. Aqui o que interessa é pra onde ele ainda vai.
	var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for index: int in range(_path_index, _path.size()):
		points.append(to_local(_path[index]))

	draw_polyline(points, Color(1.0, 0.85, 0.3, 0.8), 3.0)
	draw_circle(points[points.size() - 1], 8.0, Color(1.0, 0.85, 0.3, 0.8))

## Espaço para funções personalizadas

# Dá ao corpo a identidade do NPC: nome, cor e velocidade. Chamado pelo NPCDirector logo depois de
# instanciar, antes de qualquer ordem de movimento.
func configure(p_definition: NPCDefinition, emotion: EmotionDefinition = null) -> void:
	definition = p_definition
	_speed = definition.walk_speed

	# PLACEHOLDER: enquanto todos os NPCs usam o spritesheet do Player, a cor é o que diferencia um
	# do outro (ver a chave PLACEHOLDER_NPC_BODY no CSV).
	_animated_sprite.modulate = definition.tint
	_name_label.text = definition.get_display_name()
	set_emotion(emotion)

	print("[NPC] - \"%s\" entrou em cena" % definition.id)


# Mostra a emoção vigente tingindo o nome. É o único efeito visual da emoção por enquanto, e serve
# principalmente pra dar pra ver, olhando a cidade, quem está em qual emoção durante o teste.
func set_emotion(emotion: EmotionDefinition) -> void:
	_name_label.modulate = emotion.tint if emotion != null else Color.WHITE


# Manda o NPC andar até um ponto, desviando do cenário. Chamar de novo troca o destino. Ignorado
# enquanto segurado por uma conversa (ver hold()).
func walk_to(target: Vector2) -> void:
	if _is_held:
		return
	_target = target
	_has_target = true
	_attempts = 0
	_retry_time = 0.0
	_request_path()


# Segura o NPC parado durante uma conversa: cancela o caminho e ignora walk_to() até release().
func hold() -> void:
	_is_held = true
	_has_target = false
	_clear_path()


func release() -> void:
	_is_held = false


# Liga/desliga o contorno branco de hover (mouse em cima, com conversa disponível). Quem decide
# quando chamar é a NPCInteraction; este método só aplica o parâmetro do shader.
func set_hover_outline(enabled: bool) -> void:
	_animated_sprite.material.set_shader_parameter(&"outline_width", hover_outline_width if enabled else 0.0)


# Vira o sprite para encarar um ponto (o jogador, ao abrir uma conversa), sem se mover.
func face_toward(world_position: Vector2) -> void:
	var to_target: Vector2 = world_position - global_position
	if to_target.is_zero_approx():
		return
	_facing = Isometric.facing_from_direction(Isometric.to_cartesian(to_target, isometric_y_ratio))
	_play_animation()


# Põe o NPC direto no ponto, sem andar. Usado quando ele aparece em cena (chegou de outra cena, ou
# a partida acabou de começar) e quando o tempo pula — nesses casos não houve trajeto a percorrer.
func snap_to(target: Vector2) -> void:
	global_position = target
	_target = target
	_has_target = false
	_clear_path()
	_update_movement_state(Vector2.ZERO)


# Aparece com fade. Separado do snap_to porque nem toda chegada em cena deve ser animada (a
# primeira montagem da cena, por exemplo, não precisa).
func appear() -> void:
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)


# Desaparece com fade e se remove da cena. Chamado quando a rotina manda o NPC pra outra cena: o
# corpo deixa de existir, e a rotina continua valendo (a posição dele é derivada do relógio, não
# guardada neste nó).
func disappear() -> void:
	if definition != null:
		print("[NPC] - \"%s\" saiu de cena" % definition.id)

	set_physics_process(false)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)


func is_walking() -> bool:
	return not _path.is_empty()


# Pede ao Pathfinder o caminho até o destino atual.
#
# O Pathfinder é procurado por grupo, e não guardado numa referência exportada, pra que o NPC
# funcione igual numa cena que não tenha nenhum — sem Pathfinder o caminho vira a reta até o
# destino, que é o comportamento simples e aceitável de uma cena de teste.
func _request_path() -> void:
	if not _has_target:
		return

	var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP) as Pathfinder
	if pathfinder == null:
		_path = PackedVector2Array([_target])
	else:
		# O próprio RID vai junto: a linha de visão do Pathfinder é raycast, e sem se excluir o
		# NPC bate no próprio colisor e nunca enxerga destino nenhum.
		_path = pathfinder.find_path(global_position, _target, [get_rid()])

	_path_index = 0
	_blocked_time = 0.0

	if _path.is_empty():
		_give_up_or_retry("sem caminho até o destino")


# Converte o ponto atual do caminho na direção cartesiana equivalente, avançando pro ponto seguinte
# conforme chega. Devolve ZERO quando não há caminho a percorrer. Mesma mecânica do Player no
# esquema de clique — a diferença é só de onde vem o destino.
func _get_path_direction() -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO

	var arrival_distance: float = maxf(ARRIVAL_DISTANCE, _speed * get_physics_process_delta_time())

	# Laço, e não if: com os pontos do caminho próximos entre si, um único frame pode vencer mais
	# de um de uma vez.
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) <= arrival_distance:
		_path_index += 1

	if _path_index >= _path.size():
		_arrive()
		return Vector2.ZERO

	var to_waypoint: Vector2 = _path[_path_index] - global_position
	return Isometric.to_cartesian(to_waypoint, isometric_y_ratio)


func _arrive() -> void:
	_clear_path()
	_has_target = false
	_attempts = 0
	arrived.emit()


# Detecta que o NPC travou. Com o Pathfinder o traçado já desvia da geometria estática, então
# travar aqui quer dizer que apareceu algo que o grafo não conhece — outro NPC, o Player, cenário
# que mudou desde o último rebuild().
func _handle_blocked(delta: float) -> void:
	if _path.is_empty():
		_blocked_time = 0.0
		return

	if get_real_velocity().length() >= _speed * BLOCKED_SPEED_FRACTION:
		_blocked_time = 0.0
		return

	_blocked_time += delta
	if _blocked_time >= BLOCKED_GRACE_SECONDS:
		_clear_path()
		_give_up_or_retry("passagem bloqueada")


# Espera repath_interval e tenta de novo. É aqui que o NPC sai de um bloqueio temporário (alguém
# parado na porta) sem precisar de nada mais elaborado que paciência.
func _handle_retry(delta: float) -> void:
	if not _has_target or not _path.is_empty():
		return

	_retry_time += delta
	if _retry_time >= repath_interval:
		_retry_time = 0.0
		_request_path()


# Decide entre tentar de novo depois e desistir assumindo a posição. Desistir é deliberado: um NPC
# fora do lugar quebra a rotina do dia inteiro dele, e ninguém prefere ver o NPC encalhado numa
# quina a vê-lo aparecer no destino.
func _give_up_or_retry(reason: String) -> void:
	_attempts += 1
	var npc_id: StringName = definition.id if definition != null else &"?"

	if _attempts >= give_up_attempts:
		print("[NPC] - \"%s\" desistiu de andar (%s) e assumiu a posição do waypoint" % [npc_id, reason])
		snap_to(_target)
		arrived.emit()
		return

	print("[NPC] - \"%s\" não conseguiu andar (%s), tentativa %d de %d" % [
		npc_id, reason, _attempts, give_up_attempts])
	_retry_time = 0.0


func _clear_path() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_blocked_time = 0.0
	queue_redraw()


# Calcula o estado de movimento a partir da direção deste frame, mantendo a última direção encarada
# quando está parado, e só emite quando algo muda de verdade.
func _update_movement_state(direction: Vector2) -> void:
	var is_moving: bool = direction != Vector2.ZERO
	var facing: Isometric.Facing = _facing

	if is_moving:
		facing = Isometric.facing_from_direction(direction)

	if is_moving == _is_moving and facing == _facing:
		return

	_is_moving = is_moving
	_facing = facing
	movement_state_changed.emit(_is_moving, _facing)


func _on_movement_state_changed(_is_moving_now: bool, _facing_now: Isometric.Facing) -> void:
	_play_animation()


func _play_animation() -> void:
	var prefix: StringName = &"run" if _is_moving else &"idle"
	_animated_sprite.play(Isometric.animation_name(prefix, _facing))
