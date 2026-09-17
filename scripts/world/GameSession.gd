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
##
## QUEM ABRE O DIA SEGUINTE NÃO É ESTE ARQUIVO, É A CAMA (ver Bed.gd). Ao bater no horário
## máximo o relógio congela e o jogo fica esperando: o jogador continua andando, mas o tempo não
## anda mais até ele ir dormir. Virar o dia por conta própria aqui tiraria do jogador a única
## decisão que o sistema de tempo cobra dele.
class_name GameSession
extends Node

## Espaço para funções nativas

func _ready() -> void:
	# Adiado de propósito: start_session() anuncia time_changed, e o _ready() dos irmãos que
	# escutam o relógio (HUD, NPCs) pode ainda não ter rodado — _ready corre na ordem da árvore,
	# e depender dela seria um bug esperando a primeira vez que alguém arrastar um nó. O
	# call_deferred cai no fim do frame, com a cena inteira já montada e conectada.
	GameClock.start_session.call_deferred()


func _exit_tree() -> void:
	GameClock.stop_session()
