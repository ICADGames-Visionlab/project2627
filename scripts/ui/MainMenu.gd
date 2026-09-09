extends Control

#constastes/variáveis para caminhos de arquivos
const CONFIG_PATH := "user://settings.cfg"
const CITY_SCENE := "res://scenes/main.tscn"
@onready var new_game_button: Button = $CenterContainer/VBoxContainer/Button
@onready var options_button: Button = $CenterContainer/VBoxContainer/Button3
@onready var welcome_label: Label = $CenterContainer/VBoxContainer/WelcomeLabel
@onready var sair: Button = $Sair
@onready var center_container: CenterContainer = $CenterContainer
@onready var settings: Control = $Settings

func _ready() -> void:
	_apply_saved_locale()
	new_game_button.pressed.connect(_on_new_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	sair.pressed.connect(_on_sair_pressed)
	settings.closed.connect(_on_settings_closed)
	settings.hide()
	_update_dynamic_labels()


# Inicia uma nova partida carregando a cena inicial da cidade (placeholder).
func _on_new_game_pressed() -> void:
	print("[MainMenu] - Novo jogo iniciado, carregando cena da cidade")
	GameManager.change_scene(CITY_SCENE)

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

#fecha o overlay de opções e volta a mostrar o menu principal
func _on_settings_closed() -> void:
	settings.hide()
	center_container.show()
	sair.show()

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
