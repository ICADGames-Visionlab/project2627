## Settings - tela de configurações do jogo, dividida em abas (Geral, Vídeo, Áudio, Diálogo).
##
## COMO CONECTAR EM OUTRA CENA:
##
##   @onready var settings = $CaminhoParaInstancia  # a instância desta cena
##
##   func _ready():
##       settings.closed.connect(_on_settings_closed)
##
##   func _on_settings_closed():
##       settings.hide()          # como overlay/popup: só esconde e mostra o menu de novo
##       # ou
##       settings.hide(); resume_game()   # no Pause: esconde e despausa o jogo
##
## Se em vez de overlay a cena for aberta via change_scene_to_file() (ex: botão
## "Opções" do Menu Principal), NINGUÉM conecta o sinal "closed" — e nesse caso
## o próprio _on_close_pressed() detecta isso e volta sozinho pro Menu Principal
## (ver MAIN_MENU_SCENE mais abaixo). Não precisa fazer nada extra pra esse caso.
##
## Depende dos Autoloads AudioManager (volume geral) e GameManager (esquema de movimentação e
## preferências de diálogo): esta tela só mostra e repassa esses valores, quem guarda e salva são
## eles. Vídeo e idioma, sim, são salvos aqui (ver _save_settings()).
##
## COMO AS ABAS FUNCIONAM: as abas são os filhos do TabContainer "Tabs". O título de cada uma vem do
## metadado _tab_name do nó da aba (uma chave do CSV, traduzida sozinha pela engine). A ordem das
## abas é a ordem dos filhos na árvore. Cada aba tem uma lista "Rows" de linhas iguais: um Label com a
## chave do texto à esquerda e o controle à direita. Os controles são nós de nome único (%), então
## mover uma opção de uma aba para outra na cena não quebra as referências deste script.
##
## COMO ADICIONAR UMA OPÇÃO: duplique na cena uma linha parecida (ex.: "MovementRow"), troque a
## chave do Label, renomeie o controle e marque "Access as Unique Name". Aqui no script: crie o
## @onready com %Nome, preencha o controle (_populate_* se for um OptionButton), conecte o sinal no
## _ready() e reflita o valor salvo em _load_settings(). Quem guarda o valor é o sistema dono dele
## (AudioManager, GameManager...), nunca esta tela — a não ser que seja vídeo ou idioma.
##
## COMO ADICIONAR UMA ABA: duplique uma aba (ex.: "Video") como filha de "Tabs", troque o nome do nó
## e o metadado _tab_name pela chave nova no CSV. Mais detalhes em docs/tela_de_configuracoes.md.
extends Control

## Espaço para sinais

signal closed  # <- CONECTE este sinal na cena-pai (ver exemplo acima)

## Espaço para constantes

const CONFIG_PATH: String = "user://settings.cfg"
const MAIN_MENU_SCENE: String = "res://scenes/ui/MainMenu.tscn"

# Idiomas disponíveis no seletor, na mesma ordem em que aparecem no OptionButton.
# Pra adicionar um novo idioma: crie a coluna em translations.csv, adicione o
# locale aqui e inclua a chave MENU_LANG_* correspondente em _populate_language_options().
const AVAILABLE_LANGUAGES: Array[String] = ["en", "pt_BR"]

# Multiplicadores de duração das animações do diálogo, na ordem dos itens do seletor (Normal,
# Rápida, Instantânea — SPEC §14.1).
const DIALOGUE_ANIMATION_MULTIPLIERS: Array[float] = [1.0, 0.5, 0.0]

## Espaço para variáveis onready

# Os controles são buscados pelo nome único (%), e não pelo caminho: assim dá pra reorganizar as
# abas e as linhas na cena sem mexer aqui. Se renomear um controle, atualize o nome aqui também.
@onready var tabs: TabContainer = %Tabs
@onready var language_option: OptionButton = %LanguageOption
@onready var movement_option: OptionButton = %MovementOption
@onready var screen_mode_option: OptionButton = %ScreenModeOption
@onready var general_volume_slider: HSlider = %GeneralVolumeSlider
@onready var general_volume_value: Label = %GeneralVolumeValue
@onready var dialogue_scale_slider: HSlider = %DialogueScaleSlider
@onready var dialogue_scale_value: Label = %DialogueScaleValue
@onready var dialogue_alt_font_check: CheckButton = %DialogueAltFontCheck
@onready var dialogue_opacity_slider: HSlider = %DialogueOpacitySlider
@onready var dialogue_opacity_value: Label = %DialogueOpacityValue
@onready var dialogue_reveal_option: OptionButton = %DialogueRevealOption
@onready var dialogue_animation_option: OptionButton = %DialogueAnimationOption
@onready var close_button: Button = %CloseButton

## Espaço para funções nativas

func _ready() -> void:
	# Os limites dos sliders de diálogo são os mesmos que o GameManager aceita em
	# set_dialogue_preference() (SPEC §14.1): se mudar lá, mude aqui.
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
	_populate_language_options()
	_populate_movement_options()
	_populate_dialogue_reveal_options()
	_populate_dialogue_animation_options()

	_load_settings() # aplica valores salvos (ou padrão, se for a 1ª vez)

	# Conecta os controles às funções que reagem a cada mudança. Vem depois do _load_settings() de
	# propósito: refletir os valores carregados não pode disparar um "o jogador mudou" (e um save).
	tabs.tab_changed.connect(_on_tab_changed)
	general_volume_slider.value_changed.connect(_on_general_volume_changed)
	screen_mode_option.item_selected.connect(_on_screen_mode_selected)
	language_option.item_selected.connect(_on_language_selected)
	movement_option.item_selected.connect(_on_movement_selected)
	dialogue_scale_slider.value_changed.connect(_on_dialogue_scale_changed)
	dialogue_alt_font_check.toggled.connect(_on_dialogue_alt_font_toggled)
	dialogue_opacity_slider.value_changed.connect(_on_dialogue_opacity_changed)
	dialogue_reveal_option.item_selected.connect(_on_dialogue_reveal_selected)
	dialogue_animation_option.item_selected.connect(_on_dialogue_animation_selected)
	close_button.pressed.connect(_on_close_pressed)


# Os itens dos OptionButtons são montados em código com tr(), então não se retraduzem sozinhos
# quando o idioma muda — por isso são refeitos aqui. Os Labels e os títulos das abas usam a chave
# direto e a engine retraduz sem ajuda.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_populate_screen_mode_options()
		_populate_language_options()
		_populate_movement_options()
		_populate_dialogue_reveal_options()
		_populate_dialogue_animation_options()

## Espaço para funções personalizadas

# --- Abas ---

# Só registra a troca de aba no log: a aba aberta não é salva (a instância desta tela vive junto com
# o menu que a contém, então ela já reabre na última aba usada enquanto o jogo estiver aberto).
func _on_tab_changed(tab_index: int) -> void:
	print("[Settings] - Aba \"%s\" aberta" % tabs.get_tab_control(tab_index).name)


# --- Áudio ---
# O volume geral não é controlado nem salvo aqui: esta tela só reflete o valor
# atual e repassa a escolha pro AudioManager (Autoload), dono desse estado.

# Repassa o novo valor pro AudioManager, que já aplica no bus certo e
# persiste em disco (ver set_general_volume() no AudioManager).
func _on_general_volume_changed(value: float) -> void:
	AudioManager.set_general_volume(value)
	_refresh_value_labels()


# --- Tela Cheia / Janela ---

# (Re)popula o dropdown de tela traduzido, preservando o índice selecionado.
# Chamada no _ready() e sempre que o idioma muda (via _notification acima).
func _populate_screen_mode_options() -> void:
	var selected: int = screen_mode_option.selected
	screen_mode_option.clear()
	screen_mode_option.add_item(tr("MENU_FULLSCREEN"), 0) # índice 0 = tela cheia
	screen_mode_option.add_item(tr("MENU_WINDOWED"), 1)   # índice 1 = janela
	screen_mode_option.selected = selected if selected != -1 else 0


# Aplica o modo de tela (cheia ou janela) escolhido no dropdown e persiste a escolha.
func _on_screen_mode_selected(index: int) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if index == 0 else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	_save_settings()
	print("[Settings] - Modo de tela alterado para %s" % ("Fullscreen" if index == 0 else "Windowed"))


# --- Idioma ---

# (Re)popula o dropdown de idiomas preservando a seleção atual. Os nomes ficam
# sempre no próprio idioma (endônimo: "English" / "Português (Brasil)") — por isso
# as chaves MENU_LANG_* têm o mesmo valor em todas as colunas do CSV.
func _populate_language_options() -> void:
	var selected: int = language_option.selected
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
	for i: int in AVAILABLE_LANGUAGES.size():
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
	var selected: int = movement_option.selected
	movement_option.clear()
	movement_option.add_item(tr("MENU_MOVEMENT_KEYBOARD"), 0) # índice 0 = MovementScheme.KEYBOARD
	movement_option.add_item(tr("MENU_MOVEMENT_CLICK"), 1)    # índice 1 = MovementScheme.CLICK
	movement_option.selected = selected if selected != -1 else int(GameManager.movement_scheme)


# Repassa o esquema escolhido pro GameManager, que aplica e persiste a escolha
# (ver set_movement_scheme() no GameManager).
func _on_movement_selected(index: int) -> void:
	GameManager.set_movement_scheme(index as GameManager.MovementScheme)


# --- Diálogo ---
# As preferências de diálogo não são controladas nem salvas aqui: esta tela só reflete o valor
# atual e repassa a escolha pro GameManager, dono desse estado (SPEC §14) — mesma divisão do
# volume geral e do esquema de movimentação.

# (Re)popula o dropdown de revelação do texto, preservando a seleção. A ordem dos itens é a do enum
# GameManager.TextReveal, porque o índice é repassado como o valor do enum.
func _populate_dialogue_reveal_options() -> void:
	var selected: int = dialogue_reveal_option.selected
	dialogue_reveal_option.clear()
	dialogue_reveal_option.add_item(tr("SETTINGS_DIALOGUE_REVEAL_INSTANT"), 0)     # GameManager.TextReveal.INSTANT
	dialogue_reveal_option.add_item(tr("SETTINGS_DIALOGUE_REVEAL_PROGRESSIVE"), 1) # GameManager.TextReveal.PROGRESSIVE
	dialogue_reveal_option.selected = selected if selected != -1 else int(GameManager.dialogue_text_reveal)


# (Re)popula o dropdown de velocidade das animações do diálogo, preservando a seleção. O índice não é
# um enum: aponta para o multiplicador em DIALOGUE_ANIMATION_MULTIPLIERS.
func _populate_dialogue_animation_options() -> void:
	var selected: int = dialogue_animation_option.selected
	dialogue_animation_option.clear()
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_NORMAL"), 0)
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_FAST"), 1)
	dialogue_animation_option.add_item(tr("SETTINGS_DIALOGUE_ANIMATION_INSTANT"), 2)
	dialogue_animation_option.selected = selected if selected != -1 else _animation_multiplier_to_index(GameManager.dialogue_animation_multiplier)


# Repassa o novo tamanho do texto do diálogo pro GameManager.
func _on_dialogue_scale_changed(value: float) -> void:
	GameManager.set_dialogue_preference(&"text_scale", value)
	_refresh_value_labels()


# Repassa a escolha da fonte alternativa (sem serifa) do diálogo pro GameManager.
func _on_dialogue_alt_font_toggled(enabled: bool) -> void:
	GameManager.set_dialogue_preference(&"use_alt_font", enabled)


# Repassa a nova opacidade do painel de diálogo pro GameManager.
func _on_dialogue_opacity_changed(value: float) -> void:
	GameManager.set_dialogue_preference(&"panel_opacity", value)
	_refresh_value_labels()


# Repassa o modo de revelação do texto pro GameManager (o índice é o valor do enum TextReveal).
func _on_dialogue_reveal_selected(index: int) -> void:
	GameManager.set_dialogue_preference(&"text_reveal", index as GameManager.TextReveal)


# Repassa o multiplicador de duração das animações escolhido pro GameManager.
func _on_dialogue_animation_selected(index: int) -> void:
	GameManager.set_dialogue_preference(&"animation_multiplier", DIALOGUE_ANIMATION_MULTIPLIERS[index])


# Converte um multiplicador de animação salvo no índice do seletor. Valor desconhecido cai no Normal.
func _animation_multiplier_to_index(multiplier: float) -> int:
	for i: int in DIALOGUE_ANIMATION_MULTIPLIERS.size():
		if is_equal_approx(multiplier, DIALOGUE_ANIMATION_MULTIPLIERS[i]):
			return i
	return 0


# --- Valores ao lado dos sliders ---

# Escreve ao lado de cada slider o valor que ele marca. São só números e símbolos (% e ×), por
# isso não passam pelo CSV. A opacidade aparece em % do opaco (0.82 vira 82%).
func _refresh_value_labels() -> void:
	general_volume_value.text = "%d%%" % roundi(general_volume_slider.value * 100.0)
	dialogue_scale_value.text = "%.1f×" % dialogue_scale_slider.value
	dialogue_opacity_value.text = "%d%%" % roundi(dialogue_opacity_slider.value * 100.0)


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
# O esquema de movimentação também não, pelo mesmo motivo: o dono é o GameManager.
# Atenção ao mexer em _save_settings(): ele grava um ConfigFile novo em cima do
# arquivo, então qualquer seção que não seja reescrita aqui some.

# Grava o modo de tela e o idioma no arquivo desta tela.
func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("video", "screen", screen_mode_option.selected)
	config.set_value("language", "code", TranslationServer.get_locale())
	config.save(CONFIG_PATH)
	print("[Settings] - Configurações de vídeo/idioma salvas")


# Carrega vídeo e idioma do arquivo local desta tela. O volume geral vem
# pronto do AudioManager (Autoload: já carregou e aplicou o valor salvo
# antes mesmo desta cena existir).
func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
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
	_refresh_value_labels()
