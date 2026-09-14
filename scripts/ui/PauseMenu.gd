## PauseMenu - menu de pausa do jogo, com a tela de configurações embutida.
##
## COMO USAR: instancie PauseMenu.tscn em qualquer cena de gameplay e pronto. Ele se vira sozinho
## — escuta a ação "pause", congela e descongela a árvore, e já traz a instância de Settings
## conectada do jeito que o cabeçalho do Settings.gd descreve.
##
## Duas decisões que não são óbvias olhando a cena:
##
## É um CanvasLayer, e não um Control solto, porque a cena de gameplay tem Camera2D: um Control
## filho do mundo andaria junto com a câmera em vez de ficar parado na tela. O layer 50 fica
## abaixo dos overlays de debug (125-128) e do fade de troca de cena (1001), que devem continuar
## por cima do menu.
##
## E roda com process_mode = ALWAYS, senão o próprio menu congelaria junto com o jogo que ele
## acabou de pausar — os botões parariam de responder e não teria como despausar.
extends CanvasLayer

## Espaço para sinais

## Espaço para variáveis

const MAIN_MENU_SCENE: String = "res://scenes/ui/MainMenu.tscn"

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _buttons: CenterContainer = $Root/CenterContainer
@onready var _resume_button: Button = $Root/CenterContainer/VBoxContainer/Resume
@onready var _options_button: Button = $Root/CenterContainer/VBoxContainer/Options
@onready var _back_to_menu_button: Button = $Root/CenterContainer/VBoxContainer/BackToMenu
@onready var _settings: Control = $Root/Settings

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resume_button.pressed.connect(resume)
	_options_button.pressed.connect(_on_options_pressed)
	_back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	_settings.closed.connect(_on_settings_closed)

	_settings.hide()
	_root.hide()


# A ação de pausa volta um passo por vez em vez de sempre despausar direto: com as configurações
# abertas ela fecha as configurações, e só no menu de pausa é que ela retoma o jogo. Sem isso, sair
# de dentro das opções despausaria o jogo sem o jogador ter pedido.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return

	get_viewport().set_input_as_handled()

	if not _root.visible:
		pause()
	elif _settings.visible:
		_on_settings_closed()
	else:
		resume()

## Espaço para funções personalizadas

# Abre o menu e congela a árvore. Público: dá pra pausar de outros lugares (cutscene, perda de
# foco da janela) sem depender da tecla.
func pause() -> void:
	# Durante uma troca de cena a tela já está coberta pelo fade e o GameManager está no meio de um
	# await — pausar aqui congelaria a transição pela metade.
	if GameManager.in_transition:
		return

	_root.show()
	_show_buttons()
	get_tree().paused = true
	print("[PauseMenu] - Jogo pausado")


# Fecha o menu e descongela a árvore.
func resume() -> void:
	_root.hide()
	get_tree().paused = false
	print("[PauseMenu] - Jogo retomado")


func _on_options_pressed() -> void:
	_buttons.hide()
	_settings.show()


func _on_settings_closed() -> void:
	_show_buttons()


# Mostra os botões do menu e esconde as configurações, devolvendo o foco pro primeiro botão pra
# quem estiver jogando de teclado ou controle não ficar sem cursor.
func _show_buttons() -> void:
	_settings.hide()
	_buttons.show()
	_resume_button.grab_focus()


# Volta pro menu principal. Despausa ANTES de pedir a troca, e isso não é detalhe: o GameManager
# anima o fade com um Tween da árvore, e Tween de árvore pausada não avança. Trocando de cena com
# o jogo ainda congelado, o jogador ficaria preso na tela preta pra sempre.
func _on_back_to_menu_pressed() -> void:
	resume()
	GameManager.change_scene(MAIN_MENU_SCENE)
