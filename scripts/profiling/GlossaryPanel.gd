## GlossaryPanel - o glossário de um NPC: as palavras que o jogador já descobriu, com contagem,
## filtros e pesquisa.
##
## COMO USAR: instancie GlossaryPanel.tscn e chame configure(). Ele aparece em dois lugares (um
## deles ainda não existe):
##
##   - dentro da página do profiling, no sonho, com a história aberta — e aí ele sabe quais palavras
##     já estão em lacunas e apaga essas;
##   - dentro do diário do jogador, na página "Pessoas Importantes", sem história nenhuma. O DIÁRIO
##     AINDA NÃO EXISTE (ver docs/sistema_de_profiling.md, "O que ainda não existe"); é por isso que
##     "story" é opcional em configure(): sem história, o painel é só a lista de palavras, que é
##     exatamente o que o diário vai pedir.
##
## OS FILTROS, como o GDD pede: Lixo, Estrela, A-Z, Categoria e Lupa. Eles aparecem como retângulos
## vazados no canto superior direito e, ao serem ligados, ficam preenchidos e VÃO PRA PRIMEIRA
## POSIÇÃO. Podem ser combinados: lixo + estrela mostra as palavras marcadas de qualquer jeito, e
## A-Z + Categoria agrupa por categoria e ordena dentro de cada grupo.
##
## A CONTAGEM ("23/36") é palavras descobertas sobre o total do pool do NPC (NPCProfile).
##
## O painel não escreve no diário: ele avisa por signal, e a página (ou o diário) decide. A única
## exceção é a marca de lixo/estrela, que é organização pessoal do jogador e não mexe em nada do
## profiling — essa ele grava direto, pra não obrigar cada tela a repassar o recado.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryPanel
extends VBoxContainer

## Espaço para sinais

## Emitido quando o jogador clica numa palavra: ela vai pra primeira lacuna vazia, ou volta pro
## glossário se já estiver numa lacuna. Quem resolve isso é a página.
signal word_activated(word_id: StringName)

## Espaço para enums

# Os cinco filtros do GDD. LIXO e ESTRELA escondem o que não está marcado; ALPHABETICAL e CATEGORY
# ordenam; SEARCH abre o campo de pesquisa.
enum Filter { TRASH, STAR, ALPHABETICAL, CATEGORY, SEARCH }

## Espaço para constantes

# Chave de localização de cada filtro, na ordem do enum.
const FILTER_KEYS: Array[String] = [
	"GLOSSARY_FILTER_TRASH",
	"GLOSSARY_FILTER_STAR",
	"GLOSSARY_FILTER_ALPHABETICAL",
	"GLOSSARY_FILTER_CATEGORY",
	"GLOSSARY_FILTER_SEARCH",
]

## Espaço para variáveis exportadas

## Espaço entre os retângulos das palavras, em pixels.
@export var word_separation: int = 8

## Altura máxima da lista de palavras, em pixels. Acima disso a lista rola — um glossário de 36
## palavras não cabe embaixo da página sem empurrar a história pra fora da tela.
@export var words_max_height: float = 190.0

## Espaço para variáveis

var _npc_id: StringName = &""
var _story: ProfilingStory

var _count_label: Label
var _filter_bar: HBoxContainer
var _filter_buttons: Dictionary = {}    # Filter -> Button
var _active_filters: Dictionary = {}    # Filter -> true
var _search_field: LineEdit
var _words_container: HFlowContainer

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

## Espaço para funções personalizadas

# Aponta o painel para o glossário de um NPC. story pode ser null: é assim que o diário vai usar
# este painel, sem página nenhuma aberta.
func configure(npc_id: StringName, story: ProfilingStory = null) -> void:
	_npc_id = npc_id
	_story = story
	refresh()


# Redesenha a lista inteira. Chamada a cada mudança do diário (palavra nova, lacuna preenchida,
# marca posta) — a lista é curta, e reconstruí-la é mais simples e mais seguro do que sincronizar
# chip por chip.
func refresh() -> void:
	if _words_container == null:
		return

	for child: Node in _words_container.get_children():
		child.queue_free()

	var profile: NPCProfile = ProfilingCatalog.find_profile(_npc_id)
	if profile == null:
		_count_label.text = ""
		return

	var words: Array[GlossaryWord] = _collect_words(profile)
	for word: GlossaryWord in words:
		var chip: GlossaryWordChip = GlossaryWordChip.new()
		_words_container.add_child(chip)
		chip.configure(word, ProfilingJournal.get_mark(_npc_id, word.id), _is_in_use(word))
		chip.word_activated.connect(_on_chip_word_activated)
		chip.mark_chosen.connect(_on_chip_mark_chosen)

	# A contagem é do POOL, não da lista filtrada: o jogador quer saber quanto falta descobrir, e
	# não quantas palavras o filtro dele deixou passar.
	_count_label.text = "%d/%d" % [
		ProfilingJournal.count_discovered_words(_npc_id), profile.get_total_word_count()]


# As palavras que a lista mostra agora: as descobertas, passadas pelos filtros e pela ordenação.
func _collect_words(profile: NPCProfile) -> Array[GlossaryWord]:
	var result: Array[GlossaryWord] = []
	var search: String = _search_field.text.strip_edges().to_lower() if _search_field != null else ""

	for word_id: StringName in ProfilingJournal.get_discovered_word_ids(_npc_id):
		var word: GlossaryWord = profile.find_word(word_id)
		if word == null:
			# Palavra no save que não está mais no pool do NPC: conteúdo renomeado ou removido depois
			# de alguém já ter jogado. Ignorar é o certo — o save não é reescrito, então voltar a
			# versão do conteúdo devolve a palavra.
			continue

		var mark: GlossaryMark.Kind = ProfilingJournal.get_mark(_npc_id, word_id)
		var wants_trash: bool = _active_filters.has(Filter.TRASH)
		var wants_star: bool = _active_filters.has(Filter.STAR)
		if wants_trash or wants_star:
			var matches_mark: bool = (wants_trash and mark == GlossaryMark.Kind.TRASH) \
				or (wants_star and mark == GlossaryMark.Kind.STAR)
			if not matches_mark:
				continue

		if not search.is_empty() and not word.get_display_text().to_lower().contains(search):
			continue

		result.append(word)

	# A ordem base é a alfabética de id (o diário devolve assim), que é estável e igual em qualquer
	# idioma. Os filtros de ordenação trocam isso pelo que o jogador está lendo na tela.
	if _active_filters.has(Filter.CATEGORY):
		result.sort_custom(_compare_by_category)
	elif _active_filters.has(Filter.ALPHABETICAL):
		result.sort_custom(_compare_by_text)

	return result


# Diz se a palavra já está numa lacuna da história aberta. Sem história (o caso do diário), nenhuma
# palavra está em uso.
func _is_in_use(word: GlossaryWord) -> bool:
	if _story == null:
		return false
	return ProfilingJournal.find_blank_with_word(_story.id, word.id, _story.get_blank_count()) >= 0


# Ordena por categoria e, dentro dela, pelo texto que o jogador lê. Sem o desempate por texto, as
# palavras de uma mesma categoria sairiam em ordem arbitrária e o filtro pareceria não ter feito
# nada dentro do grupo.
func _compare_by_category(left: GlossaryWord, right: GlossaryWord) -> bool:
	var left_order: int = left.category.sort_order if left.category != null else 9999
	var right_order: int = right.category.sort_order if right.category != null else 9999
	if left_order != right_order:
		return left_order < right_order
	return _compare_by_text(left, right)


func _compare_by_text(left: GlossaryWord, right: GlossaryWord) -> bool:
	return left.get_display_text().naturalnocasecmp_to(right.get_display_text()) < 0


# Monta o painel: cabeçalho com contagem e filtros, campo de pesquisa e a lista de palavras.
#
# Tudo em código, e não na .tscn, porque o conteúdo é dado: são N palavras descobertas, com cor de
# categoria e marca, e uma .tscn com chips soltos ficaria desatualizada no primeiro filtro novo.
func _build() -> void:
	add_theme_constant_override("separation", 8)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)

	var title: Label = Label.new()
	title.text = "GLOSSARY_TITLE"
	header.add_child(title)

	_count_label = Label.new()
	_count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	header.add_child(_count_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_filter_bar = HBoxContainer.new()
	_filter_bar.add_theme_constant_override("separation", 6)
	header.add_child(_filter_bar)
	for filter: int in Filter.values():
		_build_filter_button(filter)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "GLOSSARY_SEARCH_PLACEHOLDER"
	_search_field.clear_button_enabled = true
	_search_field.hide()
	_search_field.text_changed.connect(_on_search_text_changed)
	add_child(_search_field)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, words_max_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_words_container = HFlowContainer.new()
	_words_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_words_container.add_theme_constant_override("h_separation", word_separation)
	_words_container.add_theme_constant_override("v_separation", word_separation)
	scroll.add_child(_words_container)


# Um retângulo de filtro: vazado quando desligado, preenchido quando ligado.
func _build_filter_button(filter: int) -> void:
	var button: Button = Button.new()
	button.toggle_mode = true
	button.text = FILTER_KEYS[filter]
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(_on_filter_toggled.bind(filter))
	_filter_bar.add_child(button)
	_filter_buttons[filter] = button


func _on_filter_toggled(pressed: bool, filter: int) -> void:
	if pressed:
		_active_filters[filter] = true
		# "O retângulo é preenchido e movido para a primeira posição" (GDD).
		_filter_bar.move_child(_filter_buttons[filter] as Node, 0)
	else:
		_active_filters.erase(filter)

	if filter == Filter.SEARCH:
		_search_field.visible = pressed
		if pressed:
			_search_field.grab_focus()
		else:
			# Fechar a lupa limpa a pesquisa: deixar um texto escondido filtrando a lista seria uma
			# lista misteriosamente incompleta.
			_search_field.clear()

	print("[Profiling] - Filtro do glossário \"%s\": %s" % [
		FILTER_KEYS[filter], "ligado" if pressed else "desligado"])
	refresh()


func _on_search_text_changed(_text: String) -> void:
	refresh()


func _on_chip_word_activated(word_id: StringName) -> void:
	word_activated.emit(word_id)


# A marca é organização pessoal do jogador: não muda lacuna, não muda história, então o painel grava
# direto em vez de fazer a página repassar o recado. O refresh vem do journal_changed, como todo o
# resto.
func _on_chip_mark_chosen(word_id: StringName, kind: GlossaryMark.Kind) -> void:
	ProfilingJournal.set_mark(_npc_id, word_id, kind)
