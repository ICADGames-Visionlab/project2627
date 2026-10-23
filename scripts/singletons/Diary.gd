# Diary.gd — Autoload: o diário do jogador. Guarda o que só o diário sabe, monta a ordem das páginas
# e abre/fecha o livro (tecla L).
#
# O LIVRO É FOLHEADO EM SEQUÊNCIA, com as setas do teclado, na ordem do GDD:
#
#     capa -> sumário (com as primeiras pessoas ao lado) -> mais pessoas, se houver ->
#     [geral -> evidências -> rotina] x cada pessoa, na ordem em que o
#     jogador as conheceu -> anotações pessoais -> coro -> cidade -> cidade distorcida -> memórias
#
# A lista de páginas (get_pages) não é guardada: é refeita dos fatos sempre que eles mudam. Quem
# desenha é o DiaryBook (res://scenes/ui/diary/DiaryBook.tscn), instanciado sob demanda na primeira
# vez que o jogador abre o diário.
#
# DE ONDE VEM CADA PEDAÇO (o diário reúne, quase nunca é o dono):
#
#   pessoas          quem o jogador conheceu numa conversa (ProfilingJournal.has_met). O diário só
#                    guarda a ORDEM em que elas apareceram, que é a ordem das páginas.
#   história         as entradas de diário das histórias de profiling resolvidas
#                    (ProfilingStory.journal_entry_key), mais a apresentação DIARY_PERSON_INTRO_<ID>.
#   glossário        o glossário do NPC no ProfilingJournal (as marcas de lixo/estrela também).
#   evidências       as que o jogador já fechou no EvidenceViewer (add_evidence). Este fato é do
#                    diário. Uma evidência é "da pessoa" quando o texto dela tem palavra do pool dela.
#   rotina           o que o jogador VIU: cada trecho de rotina vira conhecido quando o NPC está na
#                    tela enquanto ele vale (ver _observe_routines). Fato do diário.
#   anotações        DiaryNote, disparadas por evento (sonho, insight, conversa) ou por add_note().
#                    Fato do diário: o id e o dia em que entrou.
#
# ENTRA NO SAVE PELO SaveManager, seção "diary". Saves antigos que só tinham a seção "evidences" (o
# protótipo da issue #30) são lidos uma vez, na primeira abertura.
#
# NÃO CONFUNDIR COM O InsightJournal nem com o ProfilingJournal: aqueles são os donos dos insights e do
# profiling; este é o livro que o jogador lê.
#
# O guia completo está em docs/diary.md.
extends Node

# Qualquer fato do diário mudou (pessoa nova, evidência, anotação, trecho de rotina, palavra do
# glossário). Só o DiaryBook escuta — relação direta entre o dono do estado e a tela que o mostra,
# por isso não é evento de bus (ver docs/event_bus.md, "Quando evitar").
signal content_changed

# A página aberta mudou (navegação).
signal page_changed(index: int)

signal diary_opened
signal diary_closed

# Anotação nova entrou no diário.
signal note_added(note_id: StringName)

const BOOK_SCENE_PATH: String = "res://scenes/ui/diary/DiaryBook.tscn"
const ROSTER_PATH: String = "res://resources/npcs/npc_roster.tres"

const DEBUG_SECTION: StringName = &"Diário"

# Chave da seção no save. É contrato do arquivo: renomear pede um passo de migração no SaveManager.
const SAVE_KEY: String = "diary"
const PEOPLE_KEY: String = "people"
const EVIDENCE_IDS_KEY: String = "evidences"
const NOTES_KEY: String = "notes"
const NOTE_ID_KEY: String = "id"
const NOTE_DAY_KEY: String = "day"
const ROUTINES_KEY: String = "routines"
# Seção do protótipo antigo ({"ids": [...]}), lida só quando a seção "diary" ainda não existe.
const LEGACY_SAVE_KEY: String = "evidences"
const LEGACY_IDS_KEY: String = "ids"

# Prefixo da apresentação de uma pessoa no CSV: DIARY_PERSON_INTRO_ZE, DIARY_PERSON_INTRO_ANA...
const PERSON_INTRO_PREFIX: String = "DIARY_PERSON_INTRO_"

const DAYS_PER_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# Se abrir o diário também pausa a árvore. Ler o diário com o mundo andando atrás não é o efeito
# desejado; é @export por ser decisão de design que pode mudar por build.
@export var pause_game_on_open: bool = true

@export_group("Calendário")
# A data do dia 1 de jogo, usada nas anotações ("14/03"). O jogo conta dias, não datas, então o
# calendário começa aqui.
@export_range(1, 31) var calendar_start_day: int = 1
@export_range(1, 12) var calendar_start_month: int = 3

@export_group("Páginas")
# Quantos itens cabem num par de folhas. Mudar o layout das cenas pede ajustar aqui junto.
# Quantas pessoas cabem na folha da direita do sumário. As que sobram vão pras páginas de Pessoas.
@export var people_on_contents: int = 4
@export var people_per_spread: int = 8
@export var evidence_per_spread: int = 6
@export var notes_per_spread: int = 4

@export_group("Rotina")
# Folga, em pixels de tela, ao decidir se o NPC "está na tela": um NPC com metade do corpo fora da
# borda ainda conta como visto.
@export var routine_visibility_margin: float = 48.0

var _roster: NPCRoster

# Fatos do diário (vão pro save).
var _people: Array[StringName] = []           # ordem em que o jogador conheceu cada pessoa
var _evidence_ids: Array[StringName] = []     # evidências fechadas, na ordem em que entraram
var _notes: Array[Dictionary] = []            # { "id": StringName, "day": int }, na ordem de entrada
var _routines_seen: Dictionary = {}           # StringName(npc) -> { String(chave de trecho): true }

# Estado de tela (não vai pro save).
var _pages: Array[DiaryPage] = []
var _pages_dirty: bool = true
var _current_key: String = "cover"
var _current_index: int = 0
var _is_open: bool = false
var _paused_by_diary: bool = false
var _sync_queued: bool = false
var _book: DiaryBook = null


func _ready() -> void:
	# O diário pausa a árvore ao abrir, e a mesma tecla L precisa chegar aqui pra fechar.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roster = load(ROSTER_PATH) as NPCRoster
	if _roster == null:
		push_error("[Diary] - ERRO: roster de NPCs não encontrado em %s" % ROSTER_PATH)

	SaveManager.session_opened.connect(_on_session_opened)
	SaveManager.register_participant(SAVE_KEY, to_dict, from_dict)
	ProfilingJournal.journal_changed.connect(_on_profiling_changed)
	EventBus.dream_started.connect(_on_dream_started)
	EventBus.insight_revealed.connect(_on_insight_revealed)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.time_changed.connect(_on_time_changed)

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Diário": ver docs/diary.md.
		_register_debug_entries()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"diary_toggle"):
		return
	# Jogo pausado por outra tela (menu de pausa, evidência aberta): o L não abre o diário por cima.
	if not _is_open and get_tree().paused:
		return
	toggle_diary()
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------------
# Abrir e fechar
# ------------------------------------------------------------------------------------

func is_open() -> bool:
	return _is_open


func toggle_diary() -> void:
	if _is_open:
		close_diary()
	else:
		open_diary()


# Abre o livro na página em que o jogador parou (a capa, na primeira vez da partida). Só abre com o
# jogador em cena: no menu principal e na tela de carregamento não há diário pra ler. Ignorado em
# troca de cena, como o PauseMenu: pausar no meio do fade trava a transição.
func open_diary() -> void:
	if _is_open or GameManager.in_transition:
		return
	if get_tree().get_first_node_in_group(Player.GROUP) == null:
		return

	if _book == null:
		var scene: PackedScene = load(BOOK_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[Diary] - ERRO: cena do diário não encontrada em %s" % BOOK_SCENE_PATH)
			return
		_book = scene.instantiate() as DiaryBook
		add_child(_book)

	# O que está na tela agora conta como visto antes de o jogo pausar.
	_observe_routines()

	_book.visible = true
	_book.refresh()

	if pause_game_on_open and not get_tree().paused:
		get_tree().paused = true
		_paused_by_diary = true

	_is_open = true
	diary_opened.emit()
	print("[Diary] - Diário aberto em \"%s\" (%d página(s))" % [_current_key, get_pages().size()])


# Fecha o livro. Só despausa o que o próprio diário pausou.
func close_diary() -> void:
	if not _is_open:
		return
	_book.close_overlays()
	_book.visible = false
	if _paused_by_diary:
		get_tree().paused = false
		_paused_by_diary = false
	_is_open = false
	diary_closed.emit()
	print("[Diary] - Diário fechado")


# ------------------------------------------------------------------------------------
# Páginas e navegação
# ------------------------------------------------------------------------------------

func get_pages() -> Array[DiaryPage]:
	if _pages_dirty:
		_rebuild_pages()
	return _pages


func get_current_page() -> DiaryPage:
	var pages: Array[DiaryPage] = get_pages()
	return pages[_current_index] if not pages.is_empty() else null


func get_current_page_index() -> int:
	get_pages()
	return _current_index


func next_page() -> void:
	go_to_page(get_current_page_index() + 1)


func previous_page() -> void:
	go_to_page(get_current_page_index() - 1)


# Vai pra uma página pelo índice, sem dar a volta nas pontas.
func go_to_page(index: int) -> void:
	var pages: Array[DiaryPage] = get_pages()
	index = clampi(index, 0, pages.size() - 1)
	if index == _current_index and pages[index].get_key() == _current_key:
		return
	_current_index = index
	_current_key = pages[index].get_key()
	page_changed.emit(_current_index)


# Vai pra uma página pela chave (DiaryPage.get_key) — é o caminho dos links do sumário, das abas e
# dos cartões de pessoa. Chave que não existe (pessoa que ainda não está no diário) é ignorada.
func go_to_key(key: String) -> void:
	var pages: Array[DiaryPage] = get_pages()
	for index: int in pages.size():
		if pages[index].get_key() == key:
			go_to_page(index)
			return
	print("[Diary] - Página \"%s\" não existe no diário agora" % key)


# Monta a sequência do livro a partir dos fatos. A página atual é reencontrada pela chave: conteúdo
# novo entrando antes dela não puxa o jogador pra outra página.
func _rebuild_pages() -> void:
	_pages_dirty = false
	_pages.clear()
	_pages.append(DiaryPage.new(DiaryPage.Kind.COVER))
	_pages.append(DiaryPage.new(DiaryPage.Kind.CONTENTS))

	# O primeiro grupo de pessoas está no sumário; página de Pessoas só pro que sobra.
	var overflow: int = _people.size() - people_on_contents
	if overflow > 0:
		for chunk: int in _chunk_count(overflow, people_per_spread):
			_pages.append(DiaryPage.new(DiaryPage.Kind.PEOPLE, &"", -1, chunk))

	for npc_id: StringName in _people:
		_pages.append(DiaryPage.new(DiaryPage.Kind.PERSON, npc_id))
		for chunk: int in _chunk_count(get_evidence_for_npc(npc_id).size(), evidence_per_spread):
			_pages.append(DiaryPage.new(DiaryPage.Kind.PERSON_EVIDENCE, npc_id, -1, chunk))
		_pages.append(DiaryPage.new(DiaryPage.Kind.PERSON_ROUTINE, npc_id))

	_pages.append(DiaryPage.new(DiaryPage.Kind.NOTES_INDEX))
	for topic: int in DiaryNote.Topic.values():
		for chunk: int in _chunk_count(get_notes(topic).size(), notes_per_spread):
			_pages.append(DiaryPage.new(DiaryPage.Kind.NOTES, &"", topic, chunk))

	var found: int = -1
	for index: int in _pages.size():
		if _pages[index].get_key() == _current_key:
			found = index
			break
	if found < 0:
		found = clampi(_current_index, 0, _pages.size() - 1)
		_current_key = _pages[found].get_key()
	_current_index = found


# Quantas páginas uma seção ocupa. Seção vazia ocupa uma (a página com o aviso de vazio).
func _chunk_count(item_count: int, per_spread: int) -> int:
	return maxi(1, ceili(float(item_count) / float(maxi(per_spread, 1))))


func _mark_changed() -> void:
	_pages_dirty = true
	content_changed.emit()


# ------------------------------------------------------------------------------------
# Pessoas
# ------------------------------------------------------------------------------------

# As pessoas do diário, na ordem em que o jogador as conheceu.
func get_people() -> Array[StringName]:
	return _people.duplicate()


func has_person(npc_id: StringName) -> bool:
	return _people.has(npc_id)


func get_definition(npc_id: StringName) -> NPCDefinition:
	return _roster.find(npc_id) if _roster != null else null


# Os parágrafos da história de uma pessoa: a apresentação (se o CSV tiver) e o que o jogador
# entendeu no profiling, na ordem das histórias do perfil.
func get_person_history(npc_id: StringName) -> PackedStringArray:
	var paragraphs: PackedStringArray = []
	var intro_key: String = PERSON_INTRO_PREFIX + String(npc_id).to_upper()
	if tr(intro_key) != intro_key:
		paragraphs.append(tr(intro_key))
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile != null:
		for story: ProfilingStory in profile.stories:
			if story != null and not story.journal_entry_key.is_empty() \
					and ProfilingJournal.is_story_solved(story.id):
				paragraphs.append(ClickableWordText.render_plain(tr(story.journal_entry_key)))
	return paragraphs


# Põe no fim da lista quem o ProfilingJournal já marcou como encontrado e o diário ainda não tem.
# Quem decide "conheceu" é o ProfilingJournal (a conversa no mundo real); o diário só lembra a ordem.
func _sync_people() -> void:
	_sync_queued = false
	var added: bool = false
	for npc_id: StringName in ProfilingJournal.get_met_ids():
		if _people.has(npc_id) or get_definition(npc_id) == null:
			continue
		_people.append(npc_id)
		added = true
		print("[Diary] - \"%s\" entrou nas páginas de Pessoas" % npc_id)
	if added:
		SaveManager.request_save()
		_mark_changed()


# ------------------------------------------------------------------------------------
# Evidências
# ------------------------------------------------------------------------------------

# Põe uma evidência no diário. Chamado pelo EvidenceViewer quando o jogador a fecha; a mesma
# evidência não entra duas vezes.
func add_evidence(item: ItemData) -> void:
	if item == null or _evidence_ids.has(item.id):
		return
	_evidence_ids.append(item.id)
	print("[Diary] - Evidência \"%s\" anotada no diário" % item.id)
	SaveManager.request_save()
	_mark_changed()


func has_evidence(item_id: StringName) -> bool:
	return _evidence_ids.has(item_id)


# As evidências que o jogador já leu, na ordem em que entraram. Id que o catálogo não acha mais
# (evidência removida ou renomeada) fica de fora sem erro.
func get_evidence_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item_id: StringName in _evidence_ids:
		var item: ItemData = ItemCatalog.find_item(item_id)
		if item != null:
			result.append(item)
	return result


# As evidências de uma pessoa: as que têm no texto alguma palavra do glossário dela. É a mesma regra
# que manda a palavra clicada na evidência pro glossário de quem a tem no pool.
func get_evidence_for_npc(npc_id: StringName) -> Array[ItemData]:
	var result: Array[ItemData] = []
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile == null:
		return result
	for item: ItemData in get_evidence_items():
		for word_id: StringName in ClickableWordText.find_word_ids(tr(item.description_key)):
			if profile.find_word(word_id) != null:
				result.append(item)
				break
	return result


# As evidências lidas que têm a palavra no texto: o "pop-up" de uma palavra do glossário.
func get_evidence_for_word(word_id: StringName) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item: ItemData in get_evidence_items():
		if ClickableWordText.find_word_ids(tr(item.description_key)).has(word_id):
			result.append(item)
	return result


# ------------------------------------------------------------------------------------
# Anotações pessoais
# ------------------------------------------------------------------------------------

# Põe uma anotação no diário, com a data de hoje. Devolve false se ela já estava ou não existe.
func add_note(note_id: StringName) -> bool:
	if has_note(note_id):
		return false
	var note: DiaryNote = DiaryNoteCatalog.find_note(note_id)
	if note == null:
		push_warning("[Diary] - AVISO: anotação \"%s\" não existe em %s" % [note_id, DiaryNoteCatalog.NOTES_DIR])
		return false
	var day: int = GameClock.time.get_day()
	_notes.append({ NOTE_ID_KEY: note_id, NOTE_DAY_KEY: day })
	print("[Diary] - Anotação \"%s\" adicionada em %s (%s)" % [
		note_id, format_date(day), DiaryNote.get_topic_name(note.topic)])
	SaveManager.request_save()
	_mark_changed()
	note_added.emit(note_id)
	return true


func has_note(note_id: StringName) -> bool:
	for entry: Dictionary in _notes:
		if entry[NOTE_ID_KEY] == note_id:
			return true
	return false


# As anotações de um subtópico, em ordem de entrada: [{ "note": DiaryNote, "day": int }, ...].
# topic = -1 devolve todas.
func get_notes(topic: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _notes:
		var note: DiaryNote = DiaryNoteCatalog.find_note(entry[NOTE_ID_KEY])
		if note == null or (topic >= 0 and note.topic != topic):
			continue
		result.append({ "note": note, "day": int(entry[NOTE_DAY_KEY]) })
	return result


# "14/03" — dia e mês do dia de jogo, contando de calendar_start_day/calendar_start_month. O formato
# vem do CSV porque a ordem dia/mês muda por idioma.
func format_date(game_day: int) -> String:
	var day: int = calendar_start_day + maxi(game_day, 1) - 1
	var month: int = calendar_start_month
	while day > DAYS_PER_MONTH[month - 1]:
		day -= DAYS_PER_MONTH[month - 1]
		month = month % 12 + 1
	return tr(&"DIARY_DATE_FORMAT").format({ "day": "%02d" % day, "month": "%02d" % month })


func _add_triggered_notes(trigger: DiaryNote.Trigger, trigger_id: StringName = &"") -> void:
	for note: DiaryNote in DiaryNoteCatalog.find_triggered(trigger, trigger_id):
		add_note(note.id)


# ------------------------------------------------------------------------------------
# Rotina observada
# ------------------------------------------------------------------------------------

# Chave de um trecho de rotina: slot de emoção, tipo de dia e o trecho ("e<minuto do relógio>" pra
# uma entrada, "x<índice>" pra uma exceção como a ronda). A tabela do diário monta a mesma chave.
static func routine_key(slot: int, day_type: int, part: String) -> String:
	return "%d:%d:%s" % [slot, day_type, part]


static func entry_part(entry: NPCRoutineEntry) -> String:
	return "e%d" % entry.get_clock_minutes()


static func exception_part(index: int) -> String:
	return "x%d" % index


func is_routine_seen(npc_id: StringName, key: String) -> bool:
	return (_routines_seen.get(npc_id, {}) as Dictionary).has(key)


func mark_routine_seen(npc_id: StringName, key: String) -> bool:
	var seen: Dictionary = _routines_seen.get(npc_id, {}) as Dictionary
	if seen.has(key):
		return false
	seen[key] = true
	_routines_seen[npc_id] = seen
	print("[Diary] - Rotina de \"%s\": trecho %s observado" % [npc_id, key])
	SaveManager.request_save()
	_mark_changed()
	return true


# Marca como visto o trecho de rotina que vale agora pra cada NPC que está na tela. É a regra de
# "conhecer a rotina" do diário: o jogador anota o que viu, e o resto da tabela fica com "?".
func _observe_routines() -> void:
	if GameClock.is_dreaming() or get_tree() == null:
		return
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null:
		return
	var screen: Rect2 = get_viewport().get_visible_rect().grow(routine_visibility_margin)
	for npc_id: StringName in director.get_body_ids():
		var body: NPC = director.get_body(npc_id)
		if body == null or not body.is_visible_in_tree():
			continue
		if not screen.has_point(body.get_global_transform_with_canvas().origin):
			continue
		_observe_current(director, npc_id)


func _observe_current(director: NPCDirector, npc_id: StringName) -> void:
	var decision: NPCRoutineResolver.Decision = director.get_decision(npc_id)
	if decision == null or decision.entry == null or decision.routine == null:
		return
	var part: String = entry_part(decision.entry)
	if decision.exception != null:
		part = exception_part(decision.routine.exceptions.find(decision.exception))
	mark_routine_seen(npc_id, routine_key(director.get_emotion_slot(npc_id), decision.day_type, part))


# ------------------------------------------------------------------------------------
# Eventos
# ------------------------------------------------------------------------------------

func _on_profiling_changed() -> void:
	# Adiado: no carregamento do save o ProfilingJournal avisa ANTES de o diário receber a própria
	# seção, e a sincronia rodando ali usaria a lista da partida anterior.
	if not _sync_queued:
		_sync_queued = true
		_sync_people.call_deferred()
	# Palavra nova, marca, história resolvida: a página aberta se redesenha.
	if _is_open:
		_mark_changed()


func _on_dream_started(_day: int) -> void:
	_add_triggered_notes(DiaryNote.Trigger.DREAM_ENTERED)


func _on_insight_revealed(event: InsightRevealedEvent) -> void:
	_add_triggered_notes(DiaryNote.Trigger.INSIGHT_READ, event.insight_id)


func _on_conversation_started(conversation_id: StringName, initiator_id: StringName) -> void:
	_add_triggered_notes(DiaryNote.Trigger.CONVERSATION_STARTED, conversation_id)
	if GameClock.is_dreaming():
		return
	# Quem está conversando com o jogador está, por definição, à vista: o trecho de rotina vale.
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null:
		return
	for npc_id: StringName in DialogueCatalog.cast_for(
			DialogueCatalog.read_participants(conversation_id), initiator_id):
		if director.get_body(npc_id) != null:
			_observe_current(director, npc_id)


func _on_time_changed(_total_minutes: int) -> void:
	_observe_routines()


# Partida aberta (novo jogo ou continuar): os fatos já chegaram por from_dict; o livro volta pra capa.
func _on_session_opened(slot: int) -> void:
	_current_key = "cover"
	_current_index = 0
	_sync_people()
	_mark_changed()
	print("[Diary] - Diário pronto para a partida do slot %d" % slot)


# ------------------------------------------------------------------------------------
# Save
# ------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var people: Array[String] = []
	for npc_id: StringName in _people:
		people.append(String(npc_id))
	var evidences: Array[String] = []
	for item_id: StringName in _evidence_ids:
		evidences.append(String(item_id))
	var notes: Array[Dictionary] = []
	for entry: Dictionary in _notes:
		notes.append({ NOTE_ID_KEY: String(entry[NOTE_ID_KEY]), NOTE_DAY_KEY: int(entry[NOTE_DAY_KEY]) })
	var routines: Dictionary = {}
	for npc_id: StringName in _routines_seen.keys():
		var keys: Array[String] = []
		for key: String in (_routines_seen[npc_id] as Dictionary).keys():
			keys.append(key)
		keys.sort()
		routines[String(npc_id)] = keys
	return {
		PEOPLE_KEY: people,
		EVIDENCE_IDS_KEY: evidences,
		NOTES_KEY: notes,
		ROUTINES_KEY: routines,
	}


# {} é o novo jogo. Na volta do JSON, StringName vira String e int vira float: as conversões são
# obrigatórias (mesma armadilha do ProfilingJournal).
func from_dict(data: Dictionary) -> void:
	_clear_facts()

	for raw_id: Variant in data.get(PEOPLE_KEY, []):
		_people.append(StringName(str(raw_id)))

	var evidences: Variant = data.get(EVIDENCE_IDS_KEY, null)
	if evidences == null:
		# Save do protótipo: a seção era "evidences" { "ids": [...] }.
		evidences = SaveManager.get_section(LEGACY_SAVE_KEY).get(LEGACY_IDS_KEY, [])
	if evidences is Array:
		for raw_id: Variant in evidences:
			_evidence_ids.append(StringName(str(raw_id)))

	for raw_entry: Variant in data.get(NOTES_KEY, []):
		if raw_entry is Dictionary:
			_notes.append({
				NOTE_ID_KEY: StringName(str((raw_entry as Dictionary).get(NOTE_ID_KEY, ""))),
				NOTE_DAY_KEY: int((raw_entry as Dictionary).get(NOTE_DAY_KEY, 1)),
			})

	var routines: Dictionary = data.get(ROUTINES_KEY, {}) as Dictionary
	for raw_npc: Variant in routines.keys():
		var seen: Dictionary = {}
		for raw_key: Variant in routines[raw_npc]:
			seen[str(raw_key)] = true
		_routines_seen[StringName(str(raw_npc))] = seen

	print("[Diary] - Diário carregado do save (%d pessoa(s), %d evidência(s), %d anotação(ões))" % [
		_people.size(), _evidence_ids.size(), _notes.size()])
	_pages_dirty = true


func _clear_facts() -> void:
	_people.clear()
	_evidence_ids.clear()
	_notes.clear()
	_routines_seen.clear()


# ------------------------------------------------------------------------------------
# Debug
# ------------------------------------------------------------------------------------

func _register_debug_entries() -> void:
	DebugMenu.register_action(DEBUG_SECTION, "Abrir/fechar diário", toggle_diary)
	DebugMenu.register_action(DEBUG_SECTION, "Página seguinte", next_page)
	DebugMenu.register_action(DEBUG_SECTION, "Página anterior", previous_page)
	DebugMenu.register_input(DEBUG_SECTION, "Adicionar anotação", _debug_add_note, [
		DebugParam.string_value("anotacao", "", _debug_note_suggestions)])
	DebugMenu.register_action(DEBUG_SECTION, "Adicionar todas as anotações", _debug_add_all_notes)
	DebugMenu.register_action(DEBUG_SECTION, "Revelar rotinas inteiras", _debug_reveal_routines)
	DebugMenu.register_action(DEBUG_SECTION, "Validar anotações", _debug_validate_notes)
	DebugMenu.register_action(DEBUG_SECTION, "Listar estado do diário", _debug_print_state)
	DebugMenu.register_action(DEBUG_SECTION, "Resetar diário", _debug_reset, true)


func _debug_add_note(note_id: String) -> void:
	add_note(StringName(note_id))


func _debug_add_all_notes() -> void:
	for note: DiaryNote in DiaryNoteCatalog.load_all():
		add_note(note.id)


# [DEBUG] Marca como vistos todos os trechos de rotina das pessoas do diário, pra revisar a tabela
# inteira sem seguir NPC nenhum pela cidade.
func _debug_reveal_routines() -> void:
	var wake_hour: int = GameClock.settings.wake_hour
	for npc_id: StringName in _people:
		var definition: NPCDefinition = get_definition(npc_id)
		for slot: int in NPCDefinition.EmotionSlot.values():
			for day_type: int in NPCDefinition.DayType.values():
				var routine: NPCRoutine = NPCRoutineResolver.resolve_routine(definition, slot, day_type)
				if routine == null:
					continue
				for entry: NPCRoutineEntry in NPCRoutineResolver.sorted_entries(routine, wake_hour):
					mark_routine_seen(npc_id, routine_key(slot, day_type, entry_part(entry)))
				for index: int in routine.exceptions.size():
					mark_routine_seen(npc_id, routine_key(slot, day_type, exception_part(index)))


func _debug_validate_notes() -> void:
	DiaryNoteCatalog.clear_cache()
	var problems: int = 0
	for note: DiaryNote in DiaryNoteCatalog.load_all():
		for issue: String in note.collect_issues():
			print("[Diary] -   %s" % issue)
			problems += 1
		if note.text_key != &"" and not ProfilingCatalog.has_translation_key(note.text_key):
			print("[Diary] -   Anotação \"%s\": chave \"%s\" não existe no translations.csv" % [note.id, note.text_key])
			problems += 1
	print("[Diary] - Validação de anotações: %s" % ("nenhum problema" if problems == 0 else "%d problema(s)" % problems))


func _debug_print_state() -> void:
	print("[Diary] - Aberto: %s, página %d/%d (\"%s\")" % [
		_is_open, get_current_page_index() + 1, get_pages().size(), _current_key])
	print("[Diary] - Pessoas: %s" % [_people])
	print("[Diary] - Evidências: %s" % [_evidence_ids])
	for entry: Dictionary in _notes:
		print("[Diary] - Anotação \"%s\" em %s" % [entry[NOTE_ID_KEY], format_date(int(entry[NOTE_DAY_KEY]))])
	for npc_id: StringName in _routines_seen.keys():
		print("[Diary] - Rotina de \"%s\": %d trecho(s) vistos" % [npc_id, (_routines_seen[npc_id] as Dictionary).size()])


func _debug_reset() -> void:
	_clear_facts()
	_current_key = "cover"
	_current_index = 0
	_sync_people()
	SaveManager.request_save()
	_mark_changed()
	print("[Diary] - Diário zerado")


func _debug_note_suggestions() -> PackedStringArray:
	var result: PackedStringArray = []
	for note: DiaryNote in DiaryNoteCatalog.load_all():
		result.append(String(note.id))
	return result
