extends Control

#constastes/variáveis para caminhos de arquivos
const SETTINGS_SCENE := "res://scenes/SettingsManager.tscn"
const CONFIG_PATH := "user://settings.cfg" 

@onready var options_button: Button = $CenterContainer/VBoxContainer/Button3
@onready var welcome_label: Label = $CenterContainer/VBoxContainer/WelcomeLabel
@onready var sair: Button = $Sair

func _ready() -> void:
	_apply_saved_locale()
	options_button.pressed.connect(_on_options_pressed)
	sair.pressed.connect(_on_sair_pressed)
	_update_dynamic_labels()

#aplica as configurações de menu já salvas
func _apply_saved_locale() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return 
	var saved_locale: String = config.get_value("idioma", "codigo", "")
	if saved_locale != "":
		TranslationServer.set_locale(saved_locale)

#troca cena para opções
func _on_options_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)

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
