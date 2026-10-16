## DreamHud - o HUD do mundo dos sonhos: o botão "Acordar" no canto inferior esquerdo e a pergunta
## "Deseja sair do mundo dos sonhos?".
##
## COMO USAR: instancie DreamHud.tscn uma vez na cena de jogo. Nada a configurar — ele aparece
## sozinho quando o jogador adormece (EventBus.dream_started) e sai quando o dia vira.
##
## POR QUE ELE EXISTE, se a cama já acorda: o GDD pede que acordar esteja SEMPRE na tela do sonho,
## em vez de obrigar o jogador a atravessar a cidade de volta até a cama. A cama continua
## funcionando (ver Bed.gd) — este é o segundo caminho, e os dois terminam na mesma chamada:
## GameClock.start_next_day() atrás de uma DreamTransition.
##
## ELE SAI DA FRENTE ENQUANTO UM ESPÍRITO ESTÁ ABERTO: a tela de profiling ocupa a tela inteira, e
## ela já tem a saída dela ("Sair"). Quem avisa são os eventos profiling_opened/profiling_closed.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name DreamHud
extends CanvasLayer

## Espaço para constantes

const GROUP: StringName = &"dream_hud"

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _wake_button: Button = $Root/WakeButton
@onready var _confirm: Control = $Root/Confirm
@onready var _confirm_yes: Button = $Root/Confirm/Panel/Margin/Content/Buttons/Yes
@onready var _confirm_no: Button = $Root/Confirm/Panel/Margin/Content/Buttons/No

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)
	# A pergunta de confirmação pausa o jogo, então este nó precisa continuar respondendo com a
	# árvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS

	EventBus.dream_started.connect(_on_dream_started)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.profiling_opened.connect(_on_profiling_opened)
	EventBus.profiling_closed.connect(_on_profiling_closed)

	_wake_button.pressed.connect(_on_wake_pressed)
	_confirm_yes.pressed.connect(_on_confirm_yes_pressed)
	_confirm_no.pressed.connect(_on_confirm_no_pressed)

	_confirm.hide()
	# O jogo pode começar com o jogador já sonhando: um save feito dentro do sonho volta assim, e
	# nesse caso o dream_started já aconteceu antes deste nó existir.
	_root.visible = GameClock.is_dreaming()


# _unhandled_input, e não _input: a tecla de cancelar fecha a pergunta antes de o menu de pausa
# aparecer por cima dela — sem isso, o menu de pausa abriria sobre a pergunta e despausaria o jogo
# com ela ainda na tela.
func _unhandled_input(event: InputEvent) -> void:
	if not _confirm.visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	cancel_wake()

## Espaço para funções personalizadas

# Abre a pergunta "Deseja sair do mundo dos sonhos?".
func ask_to_wake() -> void:
	_confirm.show()
	# Foco no "não": a resposta destrutiva (perder o resto do sonho) não deve ser a que um ENTER
	# distraído confirma.
	_confirm_no.grab_focus()
	get_tree().paused = true
	print("[DreamHud] - Jogador perguntado se quer acordar")


# Fecha a pergunta e devolve o jogo ao movimento.
func cancel_wake() -> void:
	if not _confirm.visible:
		return
	_confirm_no.release_focus()
	_confirm.hide()
	get_tree().paused = false


# Acorda o jogador, com a mesma passagem da cama. O relógio é quem sabe abrir o dia seguinte; este
# HUD só escolhe o momento.
func wake_up() -> void:
	_confirm.hide()
	_root.hide()
	get_tree().paused = false

	print("[DreamHud] - Jogador acordou pelo HUD do sonho")
	var transition: DreamTransition = get_tree().get_first_node_in_group(
		DreamTransition.GROUP) as DreamTransition
	if transition == null:
		push_warning("[DreamHud] - AVISO: nenhuma DreamTransition na cena, acordando sem transição")
		GameClock.start_next_day()
		return
	await transition.play(GameClock.start_next_day)


func _on_wake_pressed() -> void:
	ask_to_wake()


func _on_confirm_yes_pressed() -> void:
	wake_up()


func _on_confirm_no_pressed() -> void:
	cancel_wake()


func _on_dream_started(_day: int) -> void:
	_root.show()


# O dia virou, então o sonho acabou — por este HUD, pela cama ou por o jogador ter entendido um NPC
# por inteiro. Em todos os casos o HUD sai da tela.
func _on_day_changed(_day: int) -> void:
	_root.hide()
	_confirm.hide()


func _on_profiling_opened(_npc_id: StringName) -> void:
	_root.hide()


# O espírito fechou: o HUD volta, mas só se o jogador ainda estiver sonhando — fechar a tela de
# profiling acertando o NPC inteiro acorda, e aí não há mais sonho pra ter HUD.
func _on_profiling_closed(_npc_id: StringName) -> void:
	_root.visible = GameClock.is_dreaming()
