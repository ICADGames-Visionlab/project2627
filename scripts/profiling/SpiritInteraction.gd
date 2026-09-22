## SpiritInteraction - o que faz o jogador poder investigar o espírito de um NPC no mundo dos sonhos.
##
## COMO USAR: já está dentro de NPC.tscn, então todo NPC nasce com ela. Nada a configurar. Quando o
## jogador chega perto de um NPC DENTRO DO SONHO, aparece o aviso no rodapé; a tecla abre a tela de
## profiling daquele NPC, pelo EventBus:
##
##     EventBus.profiling_requested.emit(definition.id)
##
## FORA DO SONHO ELA NÃO FAZ NADA. Acordado, o NPC é assunto do sistema de diálogo, que está sendo
## feito em outra branch — e é ele que vai chamar ProfilingJournal.mark_met() pra marcar que o
## jogador conversou com aquela pessoa.
##
## O QUE O GDD PEDE E AINDA NÃO DÁ PRA FAZER: "espíritos de NPCs só aparecem quando você conversa com
## um NPC no mundo real". A regra está escrita e ligada aqui (_has_spirit pergunta a
## ProfilingJournal.has_met), mas nada marca esse encontro ainda, então has_met responde sim pra todo
## mundo — ver ASSUME_MET_UNTIL_DIALOGUE_EXISTS em ProfilingJournal.gd. Desligar aquela constante
## ativa a regra do GDD inteira, sem tocar neste arquivo.
##
## PLACEHOLDER: no sonho, o NPC continua com o corpo e o sprite do mundo acordado. Os "espíritos"
## (portraits/monstros) são arte que ainda não existe; o que muda no sonho hoje é a posição fixa
## (NPCDefinition.dream_entry) e o fato de ele poder ser investigado.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name SpiritInteraction
extends Area2D

## Espaço para constantes

# Chave de localização do aviso no rodapé. Quem traduz é o ActionPrompt.
const PROMPT_KEY: String = "PROMPT_INVESTIGATE_SPIRIT"

## Espaço para variáveis exportadas

## Ação de input que abre o espírito. Trocar a tecla é trabalho do mapa de input (Projeto > Input
## Map), não deste script.
@export var interact_action: StringName = &"spirit_interact"

## Espaço para variáveis

var _player_near: bool = false

## Espaço para funções nativas

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# O sonho começa e acaba com o jogador já perto de um NPC (ele pode dormir do lado de alguém),
	# então o aviso precisa reagir à passagem, e não só ao movimento.
	EventBus.dream_started.connect(_on_dream_changed)
	EventBus.day_changed.connect(_on_day_changed)
	# Só escuta teclado enquanto o jogador está do lado (ver _on_body_entered/_on_body_exited).
	set_process_unhandled_input(false)


# _unhandled_input, e não _input: assim qualquer tela aberta por cima (a própria tela de profiling, o
# menu de pausa) consome a tecla antes, e o jogador não reabre o espírito por baixo dela.
func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or not event.is_action_pressed(interact_action):
		return
	if not _has_spirit():
		return

	get_viewport().set_input_as_handled()
	var definition: NPCDefinition = _get_definition()
	print("[Profiling] - Espírito de \"%s\" acionado no sonho" % definition.id)
	EventBus.profiling_requested.emit(definition.id)

## Espaço para funções personalizadas

# Diz se há um espírito pra investigar aqui e agora: é preciso estar sonhando, o NPC precisa ter
# perfil de profiling escrito, e o jogador precisa já tê-lo encontrado no mundo real.
func _has_spirit() -> bool:
	var definition: NPCDefinition = _get_definition()
	if definition == null or not GameClock.is_dreaming():
		return false
	if ProfilingCatalog.find_profile(definition.id) == null:
		return false
	return ProfilingJournal.has_met(definition.id)


# O NPC a que esta área pertence. A área vive dentro de NPC.tscn, então o dono é o nó pai.
func _get_definition() -> NPCDefinition:
	var npc: NPC = get_parent() as NPC
	if npc == null:
		return null
	return npc.definition


# Mostra ou esconde o aviso no rodapé, conforme o momento. O aviso é compartilhado (ver
# EventBus.action_prompt_changed): quem mostra é responsável por esconder.
func _update_prompt() -> void:
	if _player_near and _has_spirit():
		EventBus.action_prompt_changed.emit(PROMPT_KEY)
	elif _player_near:
		# Perto de um NPC sem espírito: some com o aviso em vez de deixar o do NPC anterior na tela.
		EventBus.action_prompt_changed.emit("")


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	_player_near = true
	set_process_unhandled_input(true)
	_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if not body is Player:
		return
	_player_near = false
	set_process_unhandled_input(false)
	if _has_spirit():
		# Só apaga o aviso que ELE pediu: se o jogador saiu de perto sem nunca ter tido espírito
		# aqui, o aviso na tela é de outro objeto e não é deste nó apagar.
		EventBus.action_prompt_changed.emit("")


func _on_dream_changed(_day: int) -> void:
	_update_prompt()


func _on_day_changed(_day: int) -> void:
	# Acordou: o espírito deixou de existir, e o aviso dele tem que sair da tela.
	if _player_near:
		EventBus.action_prompt_changed.emit("")
