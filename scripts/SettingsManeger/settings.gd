extends Control

# COMO CONECTAR EM OUTRA CENA:
#
#   @onready var config = $CaminhoParaInstancia  # a instância desta cena
#
#   func _ready():
#       config.fechado.connect(_on_config_fechada)
#
#   func _on_config_fechada():
#       config.hide()          # como overlay/popup: só esconde e mostra o menu de novo
#       # ou
#       config.hide(); resume_game()   # no Pause: esconde e despausa o jogo
#
# Se em vez de overlay a cena for aberta via change_scene_to_file() (ex: botão
# "Opções" do Menu Principal), NINGUÉM conecta o sinal "fechado" — e nesse caso
# o próprio _on_sair_pressed() detecta isso e volta sozinho pro Menu Principal
# (ver MENU_PRINCIPAL mais abaixo). Não precisa fazer nada extra pra esse caso.
#
# O resto do script (áudio, tela cheia/janela, idioma, salvar/carregar) é interno
# e não precisa ser mexido pra reusar a cena em lugares diferentes.
# =====================================================================

signal fechado  # <- CONECTE este sinal na cena-pai (ver exemplo acima)

# Referências aos nós — se algum nó for renomeado ou movido na árvore,
# atualize o caminho aqui (o "$" não atualiza sozinho quando você renomeia).
@onready var slider_geral: HSlider = $VBoxContainer/Volume_Geral
@onready var option_tela: OptionButton = $VBoxContainer/Fullscreen_Janela
@onready var option_idioma: OptionButton = $VBoxContainer/Idioma
@onready var botao_sair: Button = $Sair

const CONFIG_PATH := "user://settings.cfg"
const BUS_GERAL := "Master" # <- troque aqui se o volume geral controlar outro bus

# Idiomas disponíveis no seletor, na mesma ordem em que aparecem no OptionButton.
# Pra adicionar um novo idioma: crie a coluna em translations.csv, adicione o
# locale aqui e inclua a chave MENU_LANG_* correspondente em _popular_opcoes_idioma().
const IDIOMAS_DISPONIVEIS := ["en", "pt_BR"]


func _ready() -> void:
	slider_geral.min_value = 0.0
	slider_geral.max_value = 1.0
	slider_geral.step = 0.01

	_popular_opcoes_tela()
	_popular_opcoes_idioma()

	_carregar_configuracoes() # aplica valores salvos (ou padrão, se for a 1ª vez)

	# Conecta os controles às funções que reagem a cada mudança
	slider_geral.value_changed.connect(_on_volume_geral_changed)
	option_tela.item_selected.connect(_on_tela_selecionada)
	option_idioma.item_selected.connect(_on_idioma_selecionado)
	botao_sair.pressed.connect(_on_sair_pressed)



func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_popular_opcoes_tela()
		_popular_opcoes_idioma()


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

# (Re)popula o dropdown de tela traduzido, preservando o índice selecionado.
# Chamada no _ready() e sempre que o idioma muda (via _notification acima).
func _popular_opcoes_tela() -> void:
	var selecionado := option_tela.selected
	option_tela.clear()
	option_tela.add_item(tr("MENU_FULLSCREEN"), 0) # índice 0 = tela cheia
	option_tela.add_item(tr("MENU_WINDOWED"), 1)   # índice 1 = janela
	option_tela.selected = selecionado if selecionado != -1 else 0

func _on_tela_selecionada(indice: int) -> void:
	var modo = DisplayServer.WINDOW_MODE_FULLSCREEN if indice == 0 else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(modo)
	_salvar_configuracoes()


# --- Idioma ---

# (Re)popula o dropdown de idiomas preservando a seleção atual. Os nomes ficam
# sempre no próprio idioma (endônimo: "English" / "Português (Brasil)") — por isso
# as chaves MENU_LANG_* têm o mesmo valor em todas as colunas do CSV.
func _popular_opcoes_idioma() -> void:
	var selecionado := option_idioma.selected
	option_idioma.clear()
	option_idioma.add_item(tr("MENU_LANG_EN"), 0)
	option_idioma.add_item(tr("MENU_LANG_PT_BR"), 1)
	option_idioma.selected = selecionado if selecionado != -1 else _locale_para_indice(TranslationServer.get_locale())

func _on_idioma_selecionado(indice: int) -> void:
	TranslationServer.set_locale(IDIOMAS_DISPONIVEIS[indice])
	_salvar_configuracoes()

# Converte o locale ativo (ex: "pt_BR", "en_US") pro índice correspondente no
# OptionButton, comparando só os 2 primeiros caracteres pra não depender do país.
func _locale_para_indice(locale: String) -> int:
	for i in IDIOMAS_DISPONIVEIS.size():
		if locale.substr(0, 2) == IDIOMAS_DISPONIVEIS[i].substr(0, 2):
			return i
	return 0 # idioma do sistema sem tradução: cai no primeiro da lista (en)


# --- Sair ---
# Veja o comentário no topo do arquivo pra saber como conectar isso a outras cenas.

const MENU_PRINCIPAL := "res://scenes/MainMenu.tscn"

func _on_sair_pressed() -> void:
	if fechado.get_connections().is_empty():
		get_tree().change_scene_to_file(MENU_PRINCIPAL)
	else:
		fechado.emit()

# --- Salvar / Carregar (arquivo local, independe de onde a cena é usada) ---

func _salvar_configuracoes() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "geral", slider_geral.value)
	config.set_value("video", "tela", option_tela.selected)
	config.set_value("idioma", "codigo", TranslationServer.get_locale())
	config.save(CONFIG_PATH)

func _carregar_configuracoes() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# Nenhuma config salva ainda (1ª vez rodando o jogo): usa padrão
		slider_geral.value = 1.0
		option_tela.selected = 0
		# Idioma não é forçado aqui: mantém o que a engine já detectou do sistema.
	else:
		slider_geral.value = config.get_value("audio", "geral", 1.0)
		option_tela.selected = config.get_value("video", "tela", 0)
		var locale_salvo: String = config.get_value("idioma", "codigo", "")
		if locale_salvo != "":
			TranslationServer.set_locale(locale_salvo)

	# Aplica de fato os valores carregados (áudio, janela e o dropdown de idioma)
	_definir_volume_bus(BUS_GERAL, slider_geral.value)
	_on_tela_selecionada(option_tela.selected)
	option_idioma.selected = _locale_para_indice(TranslationServer.get_locale())
