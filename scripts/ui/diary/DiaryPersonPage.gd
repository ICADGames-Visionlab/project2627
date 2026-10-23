## DiaryPersonPage - a página geral de uma pessoa: à esquerda o retrato e a história (que se completa
## com o profiling), à direita o glossário dela, separado por categoria.
##
## A HISTÓRIA não tem campos de ficha (nome, profissão, idade) de propósito — o GDD acha que isso
## desumaniza o personagem. É texto corrido: a apresentação e o que o jogador já entendeu (ver
## Diary.get_person_history).
##
## O GLOSSÁRIO é o mesmo do sonho (ProfilingJournal), com os chips do profiling
## (GlossaryWordChip.tscn), mas arrumado como o GDD do diário pede: uma seção por categoria. Na borda
## direita ficam os filtros (A-Z, só estrela, só lixo) e no topo a lupa, que mostra o campo de
## pesquisa. Clicar numa palavra abre o pop-up das evidências dela; o botão direito abre o menu de
## marcas, o mesmo do sonho.
class_name DiaryPersonPage
extends DiaryPageView

## Espaço para enums

enum Filter { NONE, ALPHABETICAL, STAR, TRASH }

## Espaço para variáveis exportadas

## A cena de uma seção de categoria (DiaryGlossarySection.tscn).
@export var section_scene: PackedScene
## A cena de um chip de palavra (o do profiling, GlossaryWordChip.tscn).
@export var chip_scene: PackedScene

## Espaço para variáveis

var _npc_id: StringName = &""
var _filter: Filter = Filter.NONE

## Espaço para variáveis onready

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %Name
@onready var _history: RichTextLabel = %History
@onready var _count_label: Label = %Count
@onready var _search_button: Button = %SearchButton
@onready var _search_field: LineEdit = %SearchField
@onready var _sections: Container = %Sections
@onready var _glossary_empty: Label = %GlossaryEmpty
@onready var _alpha_filter: Button = %AlphaFilter
@onready var _star_filter: Button = %StarFilter
@onready var _trash_filter: Button = %TrashFilter

## Espaço para funções nativas

func _ready() -> void:
	_search_button.toggled.connect(_on_search_toggled)
	_search_field.text_changed.connect(_on_search_changed)
	_search_field.hide()
	_alpha_filter.pressed.connect(_on_filter_pressed.bind(Filter.ALPHABETICAL))
	_star_filter.pressed.connect(_on_filter_pressed.bind(Filter.STAR))
	_trash_filter.pressed.connect(_on_filter_pressed.bind(Filter.TRASH))

## Espaço para funções personalizadas

func show_page(page: DiaryPage) -> void:
	if page.npc_id != _npc_id:
		# Outra pessoa: a pesquisa e o filtro da anterior não valem aqui.
		_npc_id = page.npc_id
		_filter = Filter.NONE
		_search_button.set_pressed_no_signal(false)
		_search_field.clear()
		_search_field.hide()

	var definition: NPCDefinition = Diary.get_definition(_npc_id)
	if definition == null:
		return
	_portrait.texture = definition.portrait
	_name_label.text = definition.get_display_name()

	var paragraphs: PackedStringArray = Diary.get_person_history(_npc_id)
	_history.text = "\n\n".join(paragraphs) if not paragraphs.is_empty() else tr(&"DIARY_PERSON_HISTORY_EMPTY")

	_refresh_glossary()


func _refresh_glossary() -> void:
	clear_children(_sections)
	_update_filter_buttons()

	var profile: NPCProfile = ProfilingCatalog.find_profile(_npc_id)
	if profile == null:
		_count_label.text = ""
		_glossary_empty.visible = true
		return
	_count_label.text = "%d/%d" % [
		ProfilingJournal.count_discovered_words(_npc_id), profile.get_total_word_count()]

	# Uma seção por categoria, na ordem das categorias (sort_order); palavra sem categoria no fim.
	var by_category: Dictionary = {}
	for word: GlossaryWord in _collect_words(profile):
		var category_id: StringName = word.get_category_id()
		if not by_category.has(category_id):
			var words: Array[GlossaryWord] = []
			by_category[category_id] = words
		(by_category[category_id] as Array[GlossaryWord]).append(word)

	var order: Array[StringName] = []
	for category: GlossaryCategory in ProfilingCatalog.load_all_categories():
		order.append(category.id)
	order.append(&"")

	_glossary_empty.visible = by_category.is_empty()
	for category_id: StringName in order:
		if not by_category.has(category_id):
			continue
		var section: DiaryGlossarySection = section_scene.instantiate() as DiaryGlossarySection
		_sections.add_child(section)
		section.configure(_category_title(category_id))
		for word: GlossaryWord in by_category[category_id]:
			var chip: GlossaryWordChip = chip_scene.instantiate() as GlossaryWordChip
			section.get_words_container().add_child(chip)
			chip.configure(word, ProfilingJournal.get_mark(_npc_id, word.id), false)
			chip.word_activated.connect(_on_word_activated)
			chip.mark_menu_requested.connect(_on_mark_menu_requested)


# As palavras descobertas que passam pela pesquisa e pelo filtro, já ordenadas.
func _collect_words(profile: NPCProfile) -> Array[GlossaryWord]:
	var result: Array[GlossaryWord] = []
	var search: String = _search_field.text.strip_edges().to_lower()
	for word_id: StringName in ProfilingJournal.get_discovered_word_ids(_npc_id):
		var word: GlossaryWord = profile.find_word(word_id)
		if word == null:
			continue
		var mark: GlossaryMark.Kind = ProfilingJournal.get_mark(_npc_id, word_id)
		if _filter == Filter.STAR and mark != GlossaryMark.Kind.STAR:
			continue
		if _filter == Filter.TRASH and mark != GlossaryMark.Kind.TRASH:
			continue
		if not search.is_empty() and not word.get_display_text().to_lower().contains(search):
			continue
		result.append(word)
	if _filter == Filter.ALPHABETICAL:
		result.sort_custom(func(left: GlossaryWord, right: GlossaryWord) -> bool:
			return left.get_display_text().naturalnocasecmp_to(right.get_display_text()) < 0)
	return result


func _category_title(category_id: StringName) -> String:
	for category: GlossaryCategory in ProfilingCatalog.load_all_categories():
		if category.id == category_id:
			return category.get_display_name()
	return tr(&"DIARY_GLOSSARY_NO_CATEGORY")


func _update_filter_buttons() -> void:
	_alpha_filter.set_pressed_no_signal(_filter == Filter.ALPHABETICAL)
	_star_filter.set_pressed_no_signal(_filter == Filter.STAR)
	_trash_filter.set_pressed_no_signal(_filter == Filter.TRASH)


# Um filtro por vez; clicar no que já está ligado desliga.
func _on_filter_pressed(filter: Filter) -> void:
	_filter = Filter.NONE if _filter == filter else filter
	print("[Diary] - Filtro do glossário de \"%s\": %s" % [_npc_id, Filter.keys()[_filter]])
	_refresh_glossary()


func _on_search_toggled(pressed: bool) -> void:
	_search_field.visible = pressed
	if pressed:
		_search_field.grab_focus()
	else:
		# Fechar a lupa limpa a pesquisa, como no glossário do sonho.
		_search_field.clear()
		_refresh_glossary()


func _on_search_changed(_text: String) -> void:
	_refresh_glossary()


func _on_word_activated(word_id: StringName) -> void:
	book.show_word_evidence(_npc_id, word_id)


func _on_mark_menu_requested(word_id: StringName, chip_rect: Rect2) -> void:
	book.request_mark_menu(_npc_id, word_id, chip_rect)
