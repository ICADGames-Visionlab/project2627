## Bed - A cama: o único jeito de o dia virar.
##
## COMO USAR: instancie Bed.tscn onde o jogador dorme. Nada mais precisa ser configurado — a
## Area2D em volta detecta o jogador e o aviso aparece sozinho no rodapé, via EventBus.
##
## SÓ DÁ PRA DORMIR NA HORA DE DORMIR. A janela é o último pedaço do dia e fica no TimeSettings
## (padrão: as últimas 2 h), e é lá que o design mexe — este arquivo só pergunta. Fora dela o
## jogador ainda recebe um aviso, mas dizendo que não é hora, e a tecla não faz nada.
##
## O DIA NÃO VIRA SOZINHO. Quando o relógio bate no horário máximo, o GameClock congela o tempo e
## fica esperando (ver GameClock.end_day): o jogador continua andando pela cidade, mas o relógio
## não anda mais. Só dormir abre o dia seguinte. É por isso que este arquivo chama as DUAS
## funções do relógio — fechar o dia e abrir o próximo.
class_name Bed
extends Node2D

## Espaço para constantes

# Chaves de localização dos dois avisos. Quem traduz é o ActionPrompt.
const PROMPT_KEY: String = "PROMPT_SLEEP"
const PROMPT_TOO_EARLY_KEY: String = "PROMPT_SLEEP_TOO_EARLY"

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
	_sleep()

## Espaço para funções personalizadas

# Diz se a cama aceita o jogador agora: a janela é o último pedaço do dia, e quem a define é o
# TimeSettings (ver sleep_window_hours).
func _can_sleep() -> bool:
	return GameClock.settings.is_sleep_time(GameClock.get_minutes_left())


# Coloca na tela o aviso que corresponde à hora atual. Chamado ao chegar perto e a cada virada de
# hora, porque o jogador pode simplesmente esperar a hora chegar parado em cima da cama.
func _update_prompt() -> void:
	EventBus.action_prompt_changed.emit(PROMPT_KEY if _can_sleep() else PROMPT_TOO_EARLY_KEY)

# Fecha o dia e abre o seguinte.
#
# end_day() antes de start_next_day() para o resto do jogo (save, resumo do dia, NPCs) receber o
# day_ended normalmente. Quando o jogador já tinha batido no horário máximo, o dia JÁ foi fechado
# pelo relógio e o end_day daqui não faz nada — o que interessa nesse caso é o start_next_day,
# que é justamente o que estava faltando para o tempo voltar a andar.
func _sleep() -> void:
	print("[Bed] - Jogador dormiu no dia %d às %s" % [
		GameClock.time.get_day(), GameClock.time.format_clock()])
	GameClock.end_day(GameClock.DayEndReason.SLEPT)
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
