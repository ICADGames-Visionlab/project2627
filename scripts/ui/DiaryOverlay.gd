# DiaryOverlay.gd — UI do protótipo de diário: lê o estado do Diary (Autoload) e desenha a página
# atual. Não guarda nenhum dado por conta própria — toda a lógica de conteúdo e navegação mora no
# Diary; esta cena só reflete e repassa cliques, mesma divisão de responsabilidade que Settings.gd
# usa com o AudioManager (ver o cabeçalho de scripts/settings/Settings.gd).
#
# Instanciada sob demanda pelo próprio Diary na primeira vez que o jogador aperta a tecla de abrir
# (ver Diary.open_diary()). Não precisa ser colocada à mão em nenhuma cena de gameplay.
#
# O guia completo está em docs/diary.md.
class_name DiaryOverlay
extends CanvasLayer

@onready var _title_label: Label = $Panel/Margin/Content/Header/TitleLabel
@onready var _page_indicator: Label = $Panel/Margin/Content/Header/PageIndicator
@onready var _body_label: Label = $Panel/Margin/Content/BodyScroll/BodyLabel
@onready var _previous_button: Button = $Panel/Margin/Content/Footer/PreviousButton
@onready var _next_button: Button = $Panel/Margin/Content/Footer/NextButton
@onready var _close_button: Button = $Panel/Margin/Content/Footer/CloseButton


func _ready() -> void:
	# A UI do diário precisa continuar respondendo mesmo com a árvore pausada — é o próprio Diary
	# quem pausa o jogo ao abrir por padrão (ver Diary.pause_game_on_open). Sem isto os botões e o
	# fechamento por tecla travariam junto com o resto do jogo.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_previous_button.pressed.connect(Diary.previous_page)
	_next_button.pressed.connect(Diary.next_page)
	_close_button.pressed.connect(Diary.close_diary)

	Diary.pages_changed.connect(refresh)
	Diary.current_page_changed.connect(_on_current_page_changed)
	# Uma página pode citar teclas ("Use {diary_toggle} para abrir"): trocar de dispositivo com o
	# diário aberto reescreve a tecla na hora.
	EventBus.input_device_changed.connect(_on_input_device_changed)


# Fechar com "ui_cancel" (Esc, ou o B do controle) segue o mesmo padrão do resto das telas do projeto
# (PauseMenu, PlaceholderDialogueScreen). O diary_toggle (J, ou o Y) também fecha AQUI, e não no
# Diary: abrir o diário pausa a árvore, e o Autoload Diary, pausável, não recebe mais a tecla — o
# mesmo botão que abriu não fecharia. Passar de página reaproveita as ações de movimento
# esquerda/direita (que no controle são o analógico e o D-pad) — ver docs/diary.md, "Como escalar"
# pra saber quando trocar isso por ações dedicadas.
#
# Os botões do diário não recebem foco do controle de propósito: com um botão focado, o D-pad
# navegaria entre eles em vez de virar a página.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"diary_toggle"):
		Diary.close_diary()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_right"):
		Diary.next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_left"):
		Diary.previous_page()
		get_viewport().set_input_as_handled()


# Redesenha a página atual do zero. Chamado pelo Diary ao abrir (o conteúdo pode ter mudado
# enquanto o diário estava fechado) e sempre que a lista de páginas muda.
func refresh() -> void:
	var count: int = Diary.get_page_count()
	var current: int = Diary.get_current_page_index()
	_page_indicator.text = tr(&"DIARY_PAGE_INDICATOR") % [current + 1 if count > 0 else 0, count]
	_draw_current_page()
	_update_nav_buttons()


func _on_current_page_changed(_index: int) -> void:
	refresh()


# A página aberta pode citar teclas ({acao}): trocar de dispositivo reescreve a tecla na hora.
func _on_input_device_changed(_device: int) -> void:
	if visible:
		refresh()


# Desenha a página atual, ou o estado vazio se o diário ainda não tem nenhuma página — o único
# jeito de o protótipo abrir sem quebrar antes de qualquer sistema chamar Diary.add_page().
func _draw_current_page() -> void:
	var page: Diary.DiaryPage = Diary.get_page(Diary.get_current_page_index())
	if page == null:
		_title_label.text = ""
		_body_label.text = tr(&"DIARY_EMPTY")
		return

	_title_label.text = tr(page.title_key) if page.title_key != &"" else ""
	var body_text: String = tr(page.text_key)
	if not page.format_args.is_empty():
		body_text = body_text % page.format_args
	# {acao} no texto vira a tecla/botão do dispositivo em uso (ver InputGlyphs).
	_body_label.text = InputGlyphs.format_actions(body_text, GameManager.active_input_device)


# Desativa os botões de navegação nas pontas (o diário não dá a volta) e some com eles de vez com o
# diário vazio, pra não sobrar "Anterior"/"Próxima" clicável sem nenhuma página pra ir.
func _update_nav_buttons() -> void:
	var count: int = Diary.get_page_count()
	var current: int = Diary.get_current_page_index()
	_previous_button.visible = count > 0
	_next_button.visible = count > 0
	_previous_button.disabled = count == 0 or current <= 0
	_next_button.disabled = count == 0 or current >= count - 1
