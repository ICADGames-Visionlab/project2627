extends Control

# COMO CONECTAR EM OUTRA CENA:
#
#   @onready var config = $CaminhoParaInstancia  # a instância desta cena
#
#   func _ready():
#       config.fechado.connect(_on_config_fechada)
#
#   func _on_config_fechada():
#       config.hide()          # no Menu Principal: só esconde e mostra o menu de novo
#       # ou
#       config.hide(); resume_game()   # no Pause: esconde e despausa o jogo
#
# O resto do script (áudio, tela cheia/janela, salvar/carregar) é interno
# e não precisa ser mexido pra reusar a cena em lugares diferentes.
# =====================================================================

signal fechado  # <- CONECTE este sinal na cena-pai (ver exemplo acima)

# Referências aos nós — se algum nó for renomeado ou movido na árvore,
# atualize o caminho aqui (o "$" não atualiza sozinho quando você renomeia).
@onready var slider_geral: HSlider = $VBoxContainer/Volume_Geral
@onready var option_tela: OptionButton = $Fullscreen_Janela
@onready var botao_sair: Button = $Sair

const CONFIG_PATH := "user://settings.cfg"
const BUS_GERAL := "Master" # <- troque aqui se o volume geral controlar outro bus


func _ready() -> void:
	slider_geral.min_value = 0.0
	slider_geral.max_value = 1.0
	slider_geral.step = 0.01

	# Itens do dropdown de tela — se quiser mudar os textos, é só aqui:
	option_tela.clear()
	option_tela.add_item("Tela Cheia", 0) # índice 0 = tela cheia
	option_tela.add_item("Janela", 1)     # índice 1 = janela

	_carregar_configuracoes() # aplica valores salvos (ou padrão, se for a 1ª vez)

	# Conecta os controles às funções que reagem a cada mudança
	slider_geral.value_changed.connect(_on_volume_geral_changed)
	option_tela.item_selected.connect(_on_tela_selecionada)
	botao_sair.pressed.connect(_on_sair_pressed)


# --- Áudio ---

func _on_volume_geral_changed(valor: float) -> void:
	_definir_volume_bus(BUS_GERAL, valor)
	_salvar_configuracoes()

func _definir_volume_bus(nome_bus: String, valor_linear: float) -> void:
	var idx := AudioServer.get_bus_index(nome_bus)
	if idx == -1:
		return # bus não existe — confira o nome no painel Audio (embaixo do editor)
	AudioServer.set_bus_mute(idx, valor_linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(valor_linear, 0.001, 1.0)))


# --- Tela Cheia / Janela ---

func _on_tela_selecionada(indice: int) -> void:
	var modo = DisplayServer.WINDOW_MODE_FULLSCREEN if indice == 0 else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(modo)
	_salvar_configuracoes()


# --- Sair ---
# Veja o comentário no topo do arquivo pra saber como conectar isso a outras cenas.

func _on_sair_pressed() -> void:
	fechado.emit()


# --- Salvar / Carregar (arquivo local, independe de onde a cena é usada) ---

func _salvar_configuracoes() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "geral", slider_geral.value)
	config.set_value("video", "tela", option_tela.selected)
	config.save(CONFIG_PATH)

func _carregar_configuracoes() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# Nenhuma config salva ainda (1ª vez rodando o jogo): usa padrão
		slider_geral.value = 1.0
		option_tela.selected = 0
	else:
		slider_geral.value = config.get_value("audio", "geral", 1.0)
		option_tela.selected = config.get_value("video", "tela", 0)

	# Aplica de fato os valores carregados (áudio e janela)
	_definir_volume_bus(BUS_GERAL, slider_geral.value)
	_on_tela_selecionada(option_tela.selected)
