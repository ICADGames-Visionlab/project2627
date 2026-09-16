## GameSession - Liga e desliga o relógio junto com a cena de jogo.
##
## COMO USAR: um nó com este script dentro da cena de gameplay, em qualquer lugar da árvore.
## Só isso. Ele chama GameClock.start_session() ao entrar e stop_session() ao sair.
##
## POR QUE ISTO EXISTE EM VEZ DE O RELÓGIO SE LIGAR SOZINHO: o GameClock é Autoload, ou seja,
## existe desde o boot do jogo — inclusive no menu principal e na tela de loading, que são cenas
## comuns e não pausa. Se ele começasse a contar no próprio _ready(), o tempo passaria enquanto o
## jogador escolhe o slot de save. Quem sabe que uma partida começou é a cena de jogo, então é
## ela que avisa.
##
## Efeito colateral bem-vindo: rodar a cena de jogo direto pelo editor (F6) também liga o
## relógio, sem precisar passar pelo menu.
class_name GameSession
extends Node

## Espaço para variáveis exportadas

## Quanto tempo a sequência de fim de dia segura a tela antes de abrir o dia seguinte.
## Provisório — ver _on_day_ended().
@export var day_end_delay: float = 1.0

## Espaço para funções nativas

func _ready() -> void:
	EventBus.day_ended.connect(_on_day_ended)

	# Adiado de propósito: start_session() anuncia time_changed, e o _ready() dos irmãos que
	# escutam o relógio (HUD, NPCs) pode ainda não ter rodado — _ready corre na ordem da árvore,
	# e depender dela seria um bug esperando a primeira vez que alguém arrastar um nó. O
	# call_deferred cai no fim do frame, com a cena inteira já montada e conectada.
	GameClock.start_session.call_deferred()


func _exit_tree() -> void:
	GameClock.stop_session()

## Espaço para funções personalizadas

# Fecha o dia e abre o seguinte.
#
# PROVISÓRIO: quando existir a sequência de fim de dia de verdade (fade, tela de resumo, save
# automático), ela entra aqui no lugar da espera. O que NÃO pode sumir é a chamada final a
# start_next_day(): o relógio fica congelado desde o day_ended, então sem ela a partida trava
# com o tempo parado.
func _on_day_ended(day: int, reason: int) -> void:
	print("[GameSession] - Dia %d terminou (%s), abrindo o próximo" % [
		day, GameClock.DayEndReason.keys()[reason]])

	await get_tree().create_timer(day_end_delay).timeout

	# A cena pode ter sido trocada durante a espera (o jogador voltou ao menu).
	if not is_inside_tree():
		return

	GameClock.start_next_day()
