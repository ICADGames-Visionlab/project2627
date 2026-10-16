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
# que o Autoload esteja registrado no projeto antes de abrir esta cena. Mesma
# coisa com o Autoload GameManager: esquema de movimentação, diálogo e vídeo
# (modo de janela, resolução e proporção) são dele.
#
# O resto do script (idioma, salvar/carregar) é interno
# e não precisa ser mexido pra reusar a cena em lugares diferentes.
# =====================================================================

signal closed  # <- CONECTE este sinal na cena-pai (ver exemplo acima)

const CONFIG_PATH := "user://settings.cfg"
const MAIN_MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

# Idiomas disponíveis no seletor, na mesma ordem em que aparecem no OptionButton.
# Pra adicionar um novo idioma: crie a coluna em translations.csv, adicione o
# locale aqui e inclua a chave MENU_LANG_* correspondente em _populate_language_options().
const AVAILABLE_LANGUAGES := ["en", "pt_BR"]


# Referências aos nós — se algum nó for renomeado ou movido na árvore,
# atualize o caminho aqui (o "$" não atualiza sozinho quando você renomeia).
@onready var general_volume_slider: HSlider = $VBoxContainer/Volume_Geral
@onready var screen_mode_option: OptionButton = $VBoxContainer/Fullscreen_Janela
@onready var resolution_option: OptionButton = $VBoxContainer/Resolucao
@onready var aspect_ratio_option: OptionButton = $VBoxContainer/Proporcao
@onready var language_option: OptionButton = $VBoxContainer/Idioma
@onready var movement_option: OptionButton = $VBoxContainer/Movimentacao
@onready var dialogue_scale_slider: HSlider = $VBoxContainer/DialogoEscala
@onready var dialogue_alt_font_check: CheckButton = $VBoxContainer/DialogoFonteAlt
@onready var dialogue_opacity_slider: HSlider = $VBoxContainer/DialogoOpacidade
@onready var dialogue_reveal_option: OptionButton = $VBoxContainer/DialogoRevelacao
@onready var dialogue_animation_option: OptionButton = $VBoxContainer/DialogoAnimacao
@onready var close_button: Button = $Sair


func _ready() -> void:
	general_volume_slider.min_value = 0.0
	general_volume_slider.max_value = 1.0
	general_volume_slider.step = 0.01
	dialogue_scale_slider.min_value = 0.8
	dialogue_scale_slider.max_value = 2.0
	dialogue_scale_slider.step = 0.1
	dialogue_opacity_slider.min_value = 0.82
	dialogue_opacity_slider.max_value = 1.0
	dialogue_opacity_slider.step = 0.01

	_populate_screen_mode_options()
	_populate_aspect_ratio_options()
	_populate_resolution_options()
	_populate_language_options()
	_populate_movement_options()
	_populate_dialogue_reveal_options()
	_populate_dialogue_animation_options()

	_load_settings() # aplica valores salvos (ou padrão, se for a 1ª vez)

	# Conecta os controles às funções que reagem a cada mudança
	general_volume_slider.value_changed.connect(_on_general_volume_changed)
	screen_mode_option.item_selected.connect(_on_screen_mode_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	aspect_ratio_option.item_selected.connect(_on_aspect_ratio_selected)
	language_option.item_selected.connect(_on_language_selected)
	movement_option.item_selected.connect(_on_movement_selected)
	dialogue_scale_slider.value_changed.connect(_on_dialogue_scale_changed)
	dialogue_alt_font_check.toggled.connect(_on_dialogue_alt_font_toggled)
	dialogue_opacity_slider.value_changed.connect(_on_dialogue_opacity_changed)
	dialogue_reveal_option.item_selected.connect(_on_dialogue_reveal_selected)
	dialogue_animation_option.item_selected.connect(_on_dialogue_animation_selected)
	close_button.pressed.connect(_on_close_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_populate_screen_mode_options()
		_populate_aspect_ratio_options()
		_populate_language_options()
		_populate_movement_options()
		_populate_dialogue_reveal_options()
		_populate_dialogue_animation_options()


# --- Áudio ---
# O volume geral não é controlado nem salvo aqui: esta tela só reflete o valor
# atual e repassa a escolha pro AudioManager (Autoload), dono desse estado.

# Repassa o novo valor pro AudioManager, que já aplica no bus certo e
# persiste em disco (ver set_general_volume() no AudioManager).
func _on_general_volume_changed(value: float) -> void:
	AudioManager.set_general_volume(value)


# --- Vídeo (modo de janela, resolução e proporção) ---
# As preferências de vídeo não são controladas nem salvas aqui: esta tela só reflete o valor atual
# e repassa a escolha pro GameManager, que aplica na janela e persiste — mesma divisão do volume
# geral e do esquema de movimentação. O catálogo de opções fica em VideoOptions.gd.

# (Re)popula o dropdown de modo de janela traduzido, preservando o índice selecionado. A ordem dos
# itens tem que bater com a do enum VideoOptions.WindowMode.
func _populate_screen_mode_options() -> void:
	var selected := screen_mode_option.selected
	screen_mode_option.clear()
	screen_mode_option.add_item(tr("MENU_FULLSCREEN"), 0) # VideoOptions.WindowMode.FULLSCREEN
	screen_mode_option.add_item(tr("MENU_BORDERLESS"), 1) # VideoOptions.WindowMode.BORDERLESS
	screen_mode_option.add_item(tr("MENU_WINDOWED"), 2)   # VideoOptions.WindowMode.WINDOWED
	screen_mode_option.selected = selected if selected != -1 else int(GameManager.video_window_mode)

# (Re)popula o dropdown de proporção. A ordem tem que bater com a do enum VideoOptions.AspectRatio;
# só o "Automática" precisa de tradução, as proporções em si são números.
func _populate_aspect_ratio_options() -> void:
	var selected := aspect_ratio_option.selected
	aspect_ratio_option.clear()
	aspect_ratio_option.add_item(tr("MENU_ASPECT_AUTO"), 0)
	aspect_ratio_option.add_item("16:9", 1)
	aspect_ratio_option.add_item("16:10", 2)
	aspect_ratio_option.add_item("4:3", 3)
	aspect_ratio_option.add_item("21:9", 4)
	aspect_ratio_option.selected = selected if selected != -1 else int(GameManager.video_aspect_ratio)

# Popula o dropdown de resolução com as opções da proporção ativa e seleciona a resolução atual.
# Diferente dos outros, a lista muda conforme a proporção — por isso é refeita a cada troca dela.
# Cada item guarda o Vector2i no metadata, então o índice não precisa bater com nenhum enum.
func _populate_resolution_options() -> void:
	resolution_option.clear()
	for resolution: Vector2i in VideoOptions.get_resolutions(GameManager.video_aspect_ratio):
		resolution_option.add_item(VideoOptions.format_resolution(resolution))
		resolution_option.set_item_metadata(resolution_option.item_count - 1, resolution)
		if resolution == GameManager.video_resolution:
			resolution_option.selected = resolution_option.item_count - 1
	_update_resolution_enabled()

# A resolução só vale no modo janela (nas telas cheias a janela ocupa o monitor inteiro), então o
# dropdown fica desabilitado nos outros modos pra não parecer que a escolha não funcionou.
func _update_resolution_enabled() -> void:
	resolution_option.disabled = GameManager.video_window_mode != VideoOptions.WindowMode.WINDOWED

func _on_screen_mode_selected(index: int) -> void:
	GameManager.set_video_preference(&"window_mode", index as VideoOptions.WindowMode)
	_update_resolution_enabled()

func _on_resolution_selected(index: int) -> void:
	GameManager.set_video_preference(&"resolution", resolution_option.get_item_metadata(index))

# Trocar a proporção pode mudar a resolução (o GameManager escolhe a mais próxima na proporção
# nova), então a lista de resoluções é refeita a partir do estado do GameManager.
func _on_aspect_ratio_selected(index: int) -> void:
	GameManager.set_video_preference(&"aspect_ratio", index as VideoOptions.AspectRatio)
	_populate_resolution_options()


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


# --- Movimentação ---
# O esquema de movimentação não é controlado nem salvo aqui: esta tela só reflete
# o valor atual e repassa a escolha pro GameManager (Autoload), dono desse estado
# — mesma divisão usada com o volume geral e o AudioManager.

# (Re)popula o dropdown de movimentação traduzido, preservando o índice selecionado.
# A ordem dos itens tem que bater com a do enum GameManager.MovementScheme, porque
# é o índice do item que é repassado como esquema.
func _populate_movement_options() -> void:
	var selected := movement_option.selected
	movement_option.clear()
	movement_option.add_item(tr("MENU_MOVEMENT_KEYBOARD"), 0) # índice 0 = MovementScheme.KEYBOARD
	movement_option.add_item(tr("MENU_MOVEMENT_CLICK"), 1)    # índice 1 = MovementScheme.CLICK
	movement_option.add_item(tr("MENU_MOVEMENT_BOTH"), 2)     # índice 2 = MovementScheme.BOTH
	movement_option.selected = selected if selected != -1 else int(GameManager.movement_scheme)

# Repassa o esquema escolhido pro GameManager, que aplica e persiste a escolha
# (ver set_movement_scheme() no GameManager).
func _on_movement_selected(index: int) -> void:
	GameManager.set_movement_scheme(index as GameManager.MovementScheme)


# --- Diálogo ---
# As preferências de diálogo não são controladas nem salvas aqui: esta tela só reflete o valor
# atual e repassa a escolha pro GameManager, dono desse estado (SPEC §14) — mesma divisão do
# volume geral e do esquema de movimentação.

func _populate_dialogue_reveal_options() -> void:
	var selected := dialogue_reveal_option.selected
	dialogue_reveal_option.clear()
	dialogue_reveal_option.add_item(tr("SETTINGS_DIALOGUE_REVEAL_INSTANT"), 0)     # GameManager.TextReveal.INSTANT
	dialogue_reveal_option.add_item(tr("SETTINGS_DIALOGUE_REVEAL_PROGRESSIVE"), 1) # GameManager.TextReveal.PROGRESSIVE
	dialogue_reveal_option.selected = selected if selected != -1 else int(GameManager.dialogue_text_reveal)


# Índice 0 = Normal (1.0), 1 = Rápida (0.5), 2 = Instantânea (0.0) — não é o enum TextReveal, é o
# multiplicador de duração das animações (SPEC §14.1).
func _populate_dialogue_animation_options() -> void:
	var selected := dialogue_animation_option.selected
	dialogue_animation_option.clear()
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_NORMAL"), 0)
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_FAST"), 1)
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_INSTANT"), 2)
	dialogue_animation_option.selected = selected if selected != -1 else _animation_multiplier_to_index(GameManager.dialogue_animation_multiplier)


func _on_dialogue_scale_changed(value: float) -> void:
	GameManager.set_dialogue_preference(&"text_scale", value)


func _on_dialogue_alt_font_toggled(enabled: bool) -> void:
	GameManager.set_dialogue_preference(&"use_alt_font", enabled)


func _on_dialogue_opacity_changed(value: float) -> void:
	GameManager.set_dialogue_preference(&"panel_opacity", value)


func _on_dialogue_reveal_selected(index: int) -> void:
	GameManager.set_dialogue_preference(&"text_reveal", index as GameManager.TextReveal)


func _on_dialogue_animation_selected(index: int) -> void:
	GameManager.set_dialogue_preference(&"animation_multiplier", [1.0, 0.5, 0.0][index])


func _animation_multiplier_to_index(multiplier: float) -> int:
	if is_equal_approx(multiplier, 0.5):
		return 1
	if is_equal_approx(multiplier, 0.0):
		return 2
	return 0


# --- Sair ---
# Veja o comentário no topo do arquivo pra saber como conectar isso a outras cenas.

# Fecha a tela de configurações: emite o sinal "closed" se alguém estiver
# ouvindo (uso como overlay/popup); caso contrário, chama change_scene_to_file()
# e volta direto pro Menu Principal (ninguém conectado ao sinal).
func _on_close_pressed() -> void:
	if closed.get_connections().is_empty():
		GameManager.change_scene(MAIN_MENU_SCENE)
		print("[Settings] - Sem listener no sinal \"closed\"; voltando ao Menu Principal")
	else:
		closed.emit()
		print("[Settings] - Sinal \"closed\" emitido")


# --- Salvar / Carregar (arquivo local, independe de onde a cena é usada) ---
# O volume geral NÃO é salvo aqui: quem é dono e persiste esse valor é o
# AudioManager — evita duas fontes de verdade diferentes pro mesmo volume.
# O esquema de movimentação e o vídeo também não, pelo mesmo motivo: o dono é o GameManager.
# Atenção ao mexer em _save_settings(): ele grava um ConfigFile novo em cima do
# arquivo, então qualquer seção que não seja reescrita aqui some.

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("language", "code", TranslationServer.get_locale())
	config.save(CONFIG_PATH)
	print("[Settings] - Configuração de idioma salva")

# Carrega o idioma do arquivo local desta tela. O volume geral vem
# pronto do AudioManager (Autoload: já carregou e aplicou o valor salvo
# antes mesmo desta cena existir).
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# Nenhuma config salva ainda (1ª vez rodando o jogo): o idioma não é forçado
		# aqui, mantém o que a engine já detectou do sistema.
		print("[Settings] - Nenhuma configuração de idioma salva, usando padrão")
	else:
		var saved_locale: String = config.get_value("language", "code", "")
		if saved_locale != "":
			TranslationServer.set_locale(saved_locale)
		print("[Settings] - Configuração de idioma carregada")

	# O slider só reflete o volume atual — quem manda nele é o AudioManager.
	general_volume_slider.value = AudioManager.general_volume
	# O vídeo já foi carregado e aplicado pelo GameManager na abertura do jogo: aqui os
	# dropdowns só refletem os valores ativos.
	screen_mode_option.selected = int(GameManager.video_window_mode)
	aspect_ratio_option.selected = int(GameManager.video_aspect_ratio)
	_populate_resolution_options()
	language_option.selected = _locale_to_index(TranslationServer.get_locale())
	# O esquema de movimentação já veio carregado do disco pelo GameManager (Autoload),
	# antes mesmo desta cena existir: aqui o dropdown só reflete o valor ativo.
	movement_option.selected = int(GameManager.movement_scheme)
	# As preferências de diálogo também já vieram carregadas pelo GameManager: os controles só
	# refletem os valores ativos.
	dialogue_scale_slider.value = GameManager.dialogue_text_scale
	dialogue_alt_font_check.button_pressed = GameManager.dialogue_use_alt_font
	dialogue_opacity_slider.value = GameManager.dialogue_panel_opacity
	dialogue_reveal_option.selected = int(GameManager.dialogue_text_reveal)
	dialogue_animation_option.selected = _animation_multiplier_to_index(GameManager.dialogue_animation_multiplier)
