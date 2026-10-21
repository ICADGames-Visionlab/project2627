## DiaryBook - o livro do diário na tela: a moldura (capa, folhas, abas, setas) e a página aberta.
##
## Não guarda conteúdo nenhum: lê tudo do Diary (Autoload) e redesenha. Quem o cria é o próprio Diary,
## na primeira vez que o jogador aperta L (Diary.open_diary); não se põe em cena à mão.
##
## CADA TIPO DE PÁGINA É UMA CENA, apontada no Inspector ("Páginas"). Trocar o visual de uma página é
## abrir a cena dela; nada aqui sabe como uma página é desenhada.
##
## O QUE FICA POR CIMA DAS PÁGINAS mora aqui, e não na página, pra sobreviver ao redesenho (que acontece
## a cada palavra marcada, por exemplo): o pop-up de evidências de uma palavra, a evidência ampliada e
## o menu de marcas (lixo/estrela) do glossário.
##
## TECLADO: setas esquerda/direita folheiam, Esc fecha o que estiver por cima (ou o diário), L fecha.
## Lido em _input, e não em _unhandled_input: o menu de pausa está na cena atual, que recebe o evento
## antes deste autoload, e abriria por cima do diário a cada Esc.
class_name DiaryBook
extends CanvasLayer

## Espaço para variáveis exportadas

@export_group("Páginas")
@export var cover_scene: PackedScene
@export var contents_scene: PackedScene
@export var people_scene: PackedScene
@export var person_scene: PackedScene
@export var person_evidence_scene: PackedScene
@export var person_routine_scene: PackedScene
@export var notes_index_scene: PackedScene
@export var notes_scene: PackedScene

## Espaço para variáveis

var _view: DiaryPageView = null
var _view_kind: int = -1

## Espaço para variáveis onready

@onready var _page_host: Control = %PageHost
@onready var _paper: Control = %Paper
@onready var _tabs: Control = %Tabs
@onready var _contents_tab: Button = %ContentsTab
@onready var _people_tab: Button = %PeopleTab
@onready var _notes_tab: Button = %NotesTab
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton
@onready var _close_button: Button = %CloseButton
@onready var _page_indicator: Label = %PageIndicator
@onready var _word_popup: DiaryWordEvidencePopup = %WordPopup
@onready var _evidence_zoom: DiaryEvidenceZoom = %EvidenceZoom
@onready var _mark_menu: GlossaryMarkMenu = %MarkMenu

## Espaço para funções nativas

func _ready() -> void:
	# É o Diary quem pausa a árvore ao abrir; sem isto o livro travaria junto com o jogo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_button.pressed.connect(Diary.previous_page)
	_next_button.pressed.connect(Diary.next_page)
	_close_button.pressed.connect(Diary.close_diary)
	_contents_tab.pressed.connect(navigate.bind(DiaryPage.make_key(DiaryPage.Kind.CONTENTS)))
	# As primeiras pessoas ficam ao lado do sumário: é lá que a aba Pessoas abre.
	_people_tab.pressed.connect(navigate.bind(DiaryPage.make_key(DiaryPage.Kind.CONTENTS)))
	_notes_tab.pressed.connect(navigate.bind(DiaryPage.make_key(DiaryPage.Kind.NOTES_INDEX)))
	_mark_menu.mark_chosen.connect(_on_mark_chosen)
	_word_popup.evidence_selected.connect(show_evidence)
	Diary.content_changed.connect(_on_content_changed)
	Diary.page_changed.connect(_on_page_changed)


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	# Digitando na pesquisa do glossário: as setas andam no texto e o L é uma letra. Só o Esc sai do
	# campo.
	if get_viewport().gui_get_focus_owner() is LineEdit and event is InputEventKey:
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().gui_get_focus_owner().release_focus()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_cancel"):
		_step_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right") and not _has_overlay_open():
		Diary.next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left") and not _has_overlay_open():
		Diary.previous_page()
		get_viewport().set_input_as_handled()

## Espaço para funções personalizadas

# Redesenha a página atual. A cena da página só é trocada quando o TIPO muda; dentro do mesmo tipo
# ela é reaproveitada (e mantém, por exemplo, o texto digitado na pesquisa do glossário).
func refresh() -> void:
	var page: DiaryPage = Diary.get_current_page()
	if page == null:
		return

	if _view == null or _view_kind != page.kind:
		if _view != null:
			_page_host.remove_child(_view)
			_view.queue_free()
		_view = _scene_for(page.kind).instantiate() as DiaryPageView
		_view_kind = page.kind
		_view.book = self
		_page_host.add_child(_view)

	_view.show_page(page)
	_paper.visible = _view.uses_spread()
	_tabs.visible = _view.uses_spread()
	_update_navigation(page)


# Vai pra uma página pela chave (links do sumário, abas, cartões de pessoa).
func navigate(key: String) -> void:
	close_overlays()
	Diary.go_to_key(key)
	# A aba é um botão de alternar: clicar na aba da seção em que já se está a soltaria.
	_update_navigation(Diary.get_current_page())


# Amplia uma evidência no centro da tela, escurecendo o resto.
func show_evidence(item: ItemData) -> void:
	_mark_menu.close()
	_evidence_zoom.open(item)


# O pop-up de uma palavra do glossário: a palavra no centro e as evidências que a mencionam em volta.
func show_word_evidence(npc_id: StringName, word_id: StringName) -> void:
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	var word: GlossaryWord = profile.find_word(word_id) if profile != null else ProfilingCatalog.find_word(word_id)
	if word == null:
		return
	_mark_menu.close()
	_word_popup.open(npc_id, word, Diary.get_evidence_for_word(word_id))
	print("[Diary] - Pop-up da palavra \"%s\" aberto" % word_id)


func request_mark_menu(npc_id: StringName, word_id: StringName, chip_rect: Rect2) -> void:
	_mark_menu.set_meta(&"npc_id", npc_id)
	_mark_menu.toggle_for(word_id, chip_rect, ProfilingJournal.get_mark(npc_id, word_id))


# Fecha tudo o que está por cima das páginas. O Diary chama ao fechar o livro.
func close_overlays() -> void:
	_mark_menu.close()
	_word_popup.close()
	_evidence_zoom.close()


func _has_overlay_open() -> bool:
	return _word_popup.visible or _evidence_zoom.visible


# Esc volta um passo: a evidência ampliada, depois o pop-up da palavra, depois o menu de marcas, e só
# então fecha o diário.
func _step_back() -> void:
	if _evidence_zoom.visible:
		_evidence_zoom.close()
	elif _word_popup.visible:
		_word_popup.close()
	elif _mark_menu.visible:
		_mark_menu.close()
	else:
		Diary.close_diary()


func _scene_for(kind: int) -> PackedScene:
	match kind:
		DiaryPage.Kind.CONTENTS:
			return contents_scene
		DiaryPage.Kind.PEOPLE:
			return people_scene
		DiaryPage.Kind.PERSON:
			return person_scene
		DiaryPage.Kind.PERSON_EVIDENCE:
			return person_evidence_scene
		DiaryPage.Kind.PERSON_ROUTINE:
			return person_routine_scene
		DiaryPage.Kind.NOTES_INDEX:
			return notes_index_scene
		DiaryPage.Kind.NOTES:
			return notes_scene
		_:
			return cover_scene


func _update_navigation(page: DiaryPage) -> void:
	var count: int = Diary.get_pages().size()
	var index: int = Diary.get_current_page_index()
	_previous_button.disabled = index <= 0
	_next_button.disabled = index >= count - 1
	_page_indicator.text = tr(&"DIARY_PAGE_INDICATOR") % [index + 1, count]

	var section_tab: Button = null
	match page.kind:
		DiaryPage.Kind.CONTENTS:
			section_tab = _contents_tab
		DiaryPage.Kind.PEOPLE, DiaryPage.Kind.PERSON, DiaryPage.Kind.PERSON_EVIDENCE, DiaryPage.Kind.PERSON_ROUTINE:
			section_tab = _people_tab
		DiaryPage.Kind.NOTES_INDEX, DiaryPage.Kind.NOTES:
			section_tab = _notes_tab
	for tab: Button in [_contents_tab, _people_tab, _notes_tab]:
		tab.set_pressed_no_signal(tab == section_tab)


func _on_content_changed() -> void:
	if visible:
		refresh()


func _on_page_changed(_index: int) -> void:
	_mark_menu.close()
	if visible:
		refresh()


func _on_mark_chosen(word_id: StringName, kind: GlossaryMark.Kind) -> void:
	ProfilingJournal.set_mark(StringName(_mark_menu.get_meta(&"npc_id", &"")), word_id, kind)
