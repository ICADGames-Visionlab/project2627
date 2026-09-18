## Bed - A cama: a porta para o mundo dos sonhos, e o único jeito de o dia virar.
##
## COMO USAR: instancie Bed.tscn onde o jogador dorme. Nada mais precisa ser configurado — a
## Area2D em volta detecta o jogador e o aviso aparece sozinho no rodapé, via EventBus.
##
## O CICLO, INTEIRO:
##
##   acordado, fora da janela  -> aviso "não é hora", a tecla não faz nada
##   acordado, dentro da janela -> dorme: transição, mundo dos sonhos (GameClock.enter_dream)
##   sonhando                   -> acorda: transição, dia seguinte (GameClock.start_next_day)
##
## A janela de dormir é o último pedaço do dia e fica no TimeSettings (padrão: as últimas 2 h).
##
## O DIA NÃO VIRA SOZINHO. Quando o relógio bate no horário máximo, o GameClock congela o tempo e
## fica esperando (ver GameClock.end_day): o jogador continua andando pela cidade, mas o relógio
## não anda mais. Só a cama leva ao sonho, e só sair do sonho abre o dia seguinte.
##
## PROVISÓRIO: sair do sonho é interagir com a cama de novo, porque o mundo dos sonhos ainda é a
## própria cidade (a mesma cena, com o relógio travado e os NPCs nas posições de sonho). Quando ele
## ganhar forma própria, a saída muda de lugar, mas continua sendo uma chamada a
## GameClock.start_next_day() atrás de uma transição.
class_name Bed
extends Node2D

## Espaço para constantes

# Chaves de localização dos avisos. Quem traduz é o ActionPrompt.
const PROMPT_KEY: String = "PROMPT_SLEEP"
const PROMPT_TOO_EARLY_KEY: String = "PROMPT_SLEEP_TOO_EARLY"
const PROMPT_WAKE_KEY: String = "PROMPT_WAKE"

## Espaço para variáveis exportadas

## Ação de input que dorme. Trocar a tecla é trabalho do mapa de input (Projeto > Input Map),
## não deste script.
@export var sleep_action: StringName = &"sleep"

## Espaço para variáveis

var _player_near: bool = false

## Espaço para variáveis onready

@onready var _detector: Area2D = $PlayerDetector

## Espaço para funções nativas

func _ready() -> void:
	_detector.body_entered.connect(_on_body_entered)
	_detector.body_exited.connect(_on_body_exited)
	# O aviso muda de texto quando a hora de dormir chega com o jogador já parado na cama.
	# time_changed, e não hour_changed: a janela pode abrir na metade de uma hora (2.5 h antes do
	# fim, por exemplo), e aí a virada de hora chegaria tarde demais.
	EventBus.time_changed.connect(_on_time_changed)
	# Só escuta teclado enquanto o jogador está do lado (ver _on_body_entered/_on_body_exited).
	set_process_unhandled_input(false)


# _unhandled_input, e não _input: assim qualquer tela aberta por cima (menu de pausa, diálogo)
# consome a tecla antes, e o jogador não dorme sem querer com a interface na frente.
func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or not event.is_action_pressed(sleep_action):
		return

	if not _can_sleep():
		print("[Bed] - Tentou dormir às %s, ainda faltam %d min para a janela de dormir" % [
			GameClock.time.format_clock(),
			GameClock.get_minutes_left() - GameClock.settings.sleep_window_minutes()])
		return

	get_viewport().set_input_as_handled()
	_cross()

## Espaço para funções personalizadas

# Diz se a cama aceita o jogador agora. Sonhando, sempre (é a saída do sonho); acordado, só na
# janela de dormir, que é o último pedaço do dia e quem define é o TimeSettings.
func _can_sleep() -> bool:
	if GameClock.is_dreaming():
		return true
	return GameClock.settings.is_sleep_time(GameClock.get_minutes_left())


# Coloca na tela o aviso que corresponde ao momento. Chamado ao chegar perto, a cada tique do
# relógio (o jogador pode esperar a hora chegar parado em cima da cama) e depois de atravessar.
func _update_prompt() -> void:
	var key: String = PROMPT_TOO_EARLY_KEY
	if GameClock.is_dreaming():
		key = PROMPT_WAKE_KEY
	elif _can_sleep():
		key = PROMPT_KEY
	EventBus.action_prompt_changed.emit(key)


# Atravessa para o outro lado: do mundo acordado para o sonho, ou do sonho para o dia seguinte.
# A troca acontece no escuro da transição; sem transição na cena, troca seco e avisa.
func _cross() -> void:
	var action: Callable = _wake_up if GameClock.is_dreaming() else _fall_asleep
	var transition: DreamTransition = get_tree().get_first_node_in_group(DreamTransition.GROUP) as DreamTransition

	if transition == null:
		push_warning("[Bed] - AVISO: nenhuma DreamTransition na cena, atravessando sem transição")
		action.call()
	else:
		await transition.play(action)

	# O jogador continua deitado na cama do outro lado, então o aviso muda (dormir <-> acordar).
	if _player_near:
		_update_prompt()


func _fall_asleep() -> void:
	print("[Bed] - Jogador adormeceu no dia %d às %s" % [
		GameClock.time.get_day(), GameClock.time.format_clock()])
	GameClock.enter_dream()


func _wake_up() -> void:
	print("[Bed] - Jogador acordou do sonho do dia %d" % GameClock.time.get_day())
	GameClock.start_next_day()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return

	_player_near = true
	set_process_unhandled_input(true)
	_update_prompt()
	print("[Bed] - Jogador ao alcance da cama às %s (pode dormir: %s)" % [
		GameClock.time.format_clock(), _can_sleep()])


func _on_body_exited(body: Node2D) -> void:
	if not body is Player:
		return

	_player_near = false
	set_process_unhandled_input(false)
	EventBus.action_prompt_changed.emit("")
	print("[Bed] - Jogador saiu do alcance da cama")


# O tempo andou: se o jogador está na cama, o aviso pode ter mudado de "não é hora" para "pode
# dormir". Fora de alcance não tem aviso nenhum na tela, então não há o que atualizar.
func _on_time_changed(_total_minutes: int) -> void:
	if _player_near:
		_update_prompt()
