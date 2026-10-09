extends Control

#constastes/variáveis para caminhos de arquivos
const CONFIG_PATH := "user://settings.cfg"
@onready var new_game_button: Button = $CenterContainer/VBoxContainer/Button
@onready var continue_button: Button = $CenterContainer/VBoxContainer/Button2
@onready var options_button: Button = $CenterContainer/VBoxContainer/Button3
@onready var welcome_label: Label = $CenterContainer/VBoxContainer/WelcomeLabel
@onready var sair: Button = $Sair
@onready var center_container: CenterContainer = $CenterContainer
@onready var settings = $Settings
@onready var save_slot_menu: SaveSlotMenu = $SaveSlotMenu

func _ready() -> void:
	# Rede de segurança do save: qualquer caminho de volta ao menu (botão da pausa, cena trocada pelo
	# debug, fim de jogo futuro) grava e fecha a partida ativa. Sem partida ativa não faz nada, então é
	# seguro na primeira abertura do jogo.
	SaveManager.end_session()
	_apply_saved_locale()
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	options_button.pressed.connect(_on_options_pressed)
	sair.pressed.connect(_on_sair_pressed)
	settings.closed.connect(_on_settings_closed)
	save_slot_menu.closed.connect(_on_save_slot_menu_closed)
	settings.hide()
	save_slot_menu.hide()
	_update_continue_button()
	_update_dynamic_labels()


# Abre a escolha de slot para um jogo novo. Quem troca de cena é a tela de slots, depois de o jogador
# escolher (e confirmar, se o slot estiver ocupado).
func _on_new_game_pressed() -> void:
	_open_save_slot_menu(SaveSlotMenu.Mode.NEW_GAME)


# Abre a escolha de slot para continuar uma partida salva.
func _on_continue_pressed() -> void:
	_open_save_slot_menu(SaveSlotMenu.Mode.CONTINUE)


# Esconde os botões do menu e mostra a tela de slots no modo pedido, como já é feito com o Settings.
func _open_save_slot_menu(mode: SaveSlotMenu.Mode) -> void:
	center_container.hide()
	sair.hide()
	save_slot_menu.open(mode)


# Devolve os botões do menu quando a tela de slots fecha. "Continuar" é reavaliado porque o jogador
# pode ter apagado o último save lá dentro.
func _on_save_slot_menu_closed() -> void:
	center_container.show()
	sair.show()
	_update_continue_button()
	new_game_button.grab_focus()


# "Continuar" só fica habilitado se existe algum arquivo de slot, em qualquer estado: um save
# danificado também conta, porque o jogador precisa chegar à tela de slots para apagá-lo.
func _update_continue_button() -> void:
	continue_button.disabled = not SaveManager.has_any_save()

#aplica as configurações de menu já salvas
func _apply_saved_locale() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return 
	var saved_locale: String = config.get_value("language", "code", "")
	if saved_locale != "":
		TranslationServer.set_locale(saved_locale)

#abre a tela de opções como instância (overlay) desta cena
func _on_options_pressed() -> void:
	center_container.hide()
	sair.hide()
	settings.show()

func _on_settings_closed() -> void:
	settings.hide()
	center_container.show()
	sair.show()
	_update_dynamic_labels()

#Func de teste para a localização
func _update_dynamic_labels() -> void:
	welcome_label.text = tr("DYNAMIC_EXAMPLE") % formatar_numero(5.5)

# Formata número decimal com o separador certo por locale
# Se a gnt utilizar essa função deveremos colocar em um singleton
func formatar_numero(valor: float, casas_decimais: int = 1) -> String:
	var texto := "%.*f" % [casas_decimais, valor]
	if TranslationServer.get_locale().begins_with("pt"):
		texto = texto.replace(".", ",")
	return texto

func _on_sair_pressed() -> void:
	get_tree().quit()
