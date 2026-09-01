extends Control

# COMO CONECTAR EM OUTRA CENA:
#
#   @onready var settings = $CaminhoParaInstancia  # a instância desta cena
#
#   func _ready():
#       settings.closed.connect(_on_settings_closed)
#
#   func _on_settings_closed():
#       settings.hide()          # como overlay/popup: só esconde e mostra o menu de novo
#       # ou
#       settings.hide(); resume_game()   # no Pause: esconde e despausa o jogo
#
# Se em vez de overlay a cena for aberta via change_scene_to_file() (ex: botão
# "Opções" do Menu Principal), NINGUÉM conecta o sinal "closed" — e nesse caso
# o próprio _on_close_pressed() detecta isso e volta sozinho pro Menu Principal
# (ver MAIN_MENU_SCENE mais abaixo). Não precisa fazer nada extra pra esse caso.
#
# Depende do Autoload AudioManager: esta tela lê AudioManager.general_volume e
# chama AudioManager.set_general_volume() pra mostrar/alterar o volume — garanta
# que o Autoload esteja registrado no projeto antes de abrir esta cena.
#
# O resto do script (tela cheia/janela, idioma, salvar/carregar) é interno
# e não precisa ser mexido pra reusar a cena em lugares diferentes.
# =====================================================================

signal closed  # <- CONECTE este sinal na cena-pai (ver exemplo acima)

const CONFIG_PATH := "user://settings.cfg"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"

# Idiomas disponíveis no seletor, na mesma ordem em que aparecem no OptionButton.
# Pra adicionar um novo idioma: crie a coluna em translations.csv, adicione o
# locale aqui e inclua a chave MENU_LANG_* correspondente em _populate_language_options().
const AVAILABLE_LANGUAGES := ["en", "pt_BR"]


# Referências aos nós — se algum nó for renomeado ou movido na árvore,
# atualize o caminho aqui (o "$" não atualiza sozinho quando você renomeia).
@onready var general_volume_slider: HSlider = $VBoxContainer/Volume_Geral
@onready var screen_mode_option: OptionButton = $VBoxContainer/Fullscreen_Janela
@onready var language_option: OptionButton = $VBoxContainer/Idioma
@onready var close_button: Button = $Sair


func _ready() -> void:
	general_volume_slider.min_value = 0.0
	general_volume_slider.max_value = 1.0
	general_volume_slider.step = 0.01

	_populate_screen_mode_options()
	_populate_language_options()

	_load_settings() # aplica valores salvos (ou padrão, se for a 1ª vez)

	# Conecta os controles às funções que reagem a cada mudança
	general_volume_slider.value_changed.connect(_on_general_volume_changed)
	screen_mode_option.item_selected.connect(_on_screen_mode_selected)
	language_option.item_selected.connect(_on_language_selected)
	close_button.pressed.connect(_on_close_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_populate_screen_mode_options()
		_populate_language_options()


# --- Áudio ---
# O volume geral não é controlado nem salvo aqui: esta tela só reflete o valor
# atual e repassa a escolha pro AudioManager (Autoload), dono desse estado.

# Repassa o novo valor pro AudioManager, que já aplica no bus certo e
# persiste em disco (ver set_general_volume() no AudioManager).
func _on_general_volume_changed(value: float) -> void:
	AudioManager.set_general_volume(value)


# --- Tela Cheia / Janela ---

# (Re)popula o dropdown de tela traduzido, preservando o índice selecionado.
# Chamada no _ready() e sempre que o idioma muda (via _notification acima).
func _populate_screen_mode_options() -> void:
	var selected := screen_mode_option.selected
	screen_mode_option.clear()
	screen_mode_option.add_item(tr("MENU_FULLSCREEN"), 0) # índice 0 = tela cheia
	screen_mode_option.add_item(tr("MENU_WINDOWED"), 1)   # índice 1 = janela
	screen_mode_option.selected = selected if selected != -1 else 0

# Aplica o modo de tela (cheia ou janela) escolhido no dropdown e persiste a escolha.
func _on_screen_mode_selected(index: int) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if index == 0 else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	_save_settings()
	print("[Settings] - Modo de tela alterado para %s" % ("Fullscreen" if index == 0 else "Windowed"))


# --- Idioma ---

# (Re)popula o dropdown de idiomas preservando a seleção atual. Os nomes ficam
# sempre no próprio idioma (endônimo: "English" / "Português (Brasil)") — por isso
# as chaves MENU_LANG_* têm o mesmo valor em todas as colunas do CSV.
func _populate_language_options() -> void:
	var selected := language_option.selected
	language_option.clear()
	language_option.add_item(tr("MENU_LANG_EN"), 0)
	language_option.add_item(tr("MENU_LANG_PT_BR"), 1)
	language_option.selected = selected if selected != -1 else _locale_to_index(TranslationServer.get_locale())

# Aplica o idioma escolhido no dropdown e persiste a escolha.
func _on_language_selected(index: int) -> void:
	TranslationServer.set_locale(AVAILABLE_LANGUAGES[index])
	_save_settings()
	print("[Settings] - Idioma alterado para \"%s\"" % AVAILABLE_LANGUAGES[index])

# Converte o locale ativo (ex: "pt_BR", "en_US") pro índice correspondente no
# OptionButton, comparando só os 2 primeiros caracteres pra não depender do país.
func _locale_to_index(locale: String) -> int:
	for i in AVAILABLE_LANGUAGES.size():
		if locale.substr(0, 2) == AVAILABLE_LANGUAGES[i].substr(0, 2):
			return i
	return 0 # idioma do sistema sem tradução: cai no primeiro da lista (en)


# --- Sair ---
# Veja o comentário no topo do arquivo pra saber como conectar isso a outras cenas.

# Fecha a tela de configurações: emite o sinal "closed" se alguém estiver
# ouvindo (uso como overlay/popup); caso contrário, chama change_scene_to_file()
# e volta direto pro Menu Principal (ninguém conectado ao sinal).
func _on_close_pressed() -> void:
	if closed.get_connections().is_empty():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		print("[Settings] - Sem listener no sinal \"closed\"; voltando ao Menu Principal")
	else:
		closed.emit()
		print("[Settings] - Sinal \"closed\" emitido")


# --- Salvar / Carregar (arquivo local, independe de onde a cena é usada) ---
# O volume geral NÃO é salvo aqui: quem é dono e persiste esse valor é o
# AudioManager — evita duas fontes de verdade diferentes pro mesmo volume.

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "screen", screen_mode_option.selected)
	config.set_value("language", "code", TranslationServer.get_locale())
	config.save(CONFIG_PATH)
	print("[Settings] - Configurações de vídeo/idioma salvas")

# Carrega vídeo e idioma do arquivo local desta tela. O volume geral vem
# pronto do AudioManager (Autoload: já carregou e aplicou o valor salvo
# antes mesmo desta cena existir).
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# Nenhuma config salva ainda (1ª vez rodando o jogo): usa padrão
		screen_mode_option.selected = 0
		# Idioma não é forçado aqui: mantém o que a engine já detectou do sistema.
		print("[Settings] - Nenhuma configuração de vídeo/idioma salva, usando padrão")
	else:
		screen_mode_option.selected = config.get_value("video", "screen", 0)
		var saved_locale: String = config.get_value("language", "code", "")
		if saved_locale != "":
			TranslationServer.set_locale(saved_locale)
		print("[Settings] - Configurações de vídeo/idioma carregadas")

	# Aplica de fato os valores carregados: janela e o dropdown de idioma.
	# O slider só reflete o volume atual — quem manda nele é o AudioManager.
	general_volume_slider.value = AudioManager.general_volume
	_on_screen_mode_selected(screen_mode_option.selected)
	language_option.selected = _locale_to_index(TranslationServer.get_locale())
