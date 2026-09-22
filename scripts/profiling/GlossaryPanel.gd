## GlossaryPanel - o glossário de um NPC: as palavras que o jogador já descobriu, com contagem,
## filtros e pesquisa.
##
## COMO USAR: instancie scenes/profiling/GlossaryPanel.tscn e chame configure(). TODO o layout está
## na cena — título, contagem, os cinco botões de filtro, o campo de pesquisa e a área das palavras.
## Este script só liga os nós, filtra a lista e instancia um chip (a cena apontada em "Chip Scene")
## por palavra descoberta.
##
## Ele aparece em dois lugares (um deles ainda não existe):
##
##   - dentro da página do profiling, no sonho, com a história aberta — e aí ele sabe quais palavras
##     já estão em lacunas e apaga essas;
##   - dentro do diário do jogador, na página "Pessoas Importantes", sem história nenhuma. O DIÁRIO
##     AINDA NÃO EXISTE (ver docs/sistema_de_profiling.md, "O que ainda não existe"); é por isso que
##     "story" é opcional em configure(): sem história, o painel é só a lista de palavras, que é
##     exatamente o que o diário vai pedir.
##
## OS FILTROS, como o GDD pede: Lixo, Estrela, A-Z, Categoria e Lupa, no canto superior direito. Ao
## serem ligados eles ficam preenchidos e VÃO PRA PRIMEIRA POSIÇÃO. Podem ser combinados: lixo +
## estrela mostra as palavras marcadas de qualquer jeito, e A-Z + Categoria agrupa por categoria e
## ordena dentro de cada grupo.
##
## A CONTAGEM ("23/36") é palavras descobertas sobre o total do pool do NPC (NPCProfile).
##
## O painel não escreve nada no diário: ele avisa por signal, e a tela decide. Isso inclui a marca de
## lixo/estrela — o retângulo de marcas é um nó da tela (ver GlossaryMarkMenu), e não deste painel,
## justamente pra ele poder aparecer POR CIMA da lista sem ser empurrado pelo contêiner.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryPanel
extends VBoxContainer

## Espaço para sinais

## Emitido quando o jogador clica numa palavra: ela vai pra primeira lacuna vazia, ou volta pro
## glossário se já estiver numa lacuna. Quem resolve isso é a página.
signal word_activated(word_id: StringName)

## Emitido no clique direito numa palavra, com o retângulo dela na tela: é o pedido de abrir o
## retângulo de marcas ali.
signal mark_menu_requested(word_id: StringName, chip_rect: Rect2)

## Emitido quando uma palavra deve voltar pro glossário: o jogador a arrastou de uma lacuna e soltou
## aqui, ou soltou um arraste em cima de nada. Quem mexe na página é a tela.
signal word_returned(word_id: StringName)

## Espaço para enums

# Os cinco filtros do GDD. TRASH e STAR escondem o que não está marcado; ALPHABETICAL e CATEGORY
# ordenam; SEARCH abre o campo de pesquisa.
enum Filter { TRASH, STAR, ALPHABETICAL, CATEGORY, SEARCH }

## Espaço para variáveis exportadas

## A cena de um retângulo de palavra (GlossaryWordChip.tscn).
@export var chip_scene: PackedScene

## Espaço para variáveis

var _npc_id: StringName = &""
var _story: ProfilingStory

# Filter -> Button, montado a partir dos nós da cena. Existe pra o filtro ser tratado por valor de
# enum, e não por nome de nó espalhado pelo script.
var _filter_buttons: Dictionary = {}
var _active_filters: Dictionary = {}    # Filter -> true

## Espaço para variáveis onready

@onready var _count_label: Label = $Header/Count
@onready var _filter_bar: HBoxContainer = $Header/Filters
@onready var _search_field: LineEdit = $SearchField
@onready var _words_container: HFlowContainer = $Scroll/Margin/Words

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if chip_scene == null:
		push_error("[Profiling] - Glossário sem \"Chip Scene\" apontada; nenhuma palavra vai aparecer")

	_filter_buttons = {
		Filter.TRASH: $Header/Filters/TrashFilter,
		Filter.STAR: $Header/Filters/StarFilter,
		Filter.ALPHABETICAL: $Header/Filters/AlphabeticalFilter,
		Filter.CATEGORY: $Header/Filters/CategoryFilter,
		Filter.SEARCH: $Header/Filters/SearchFilter,
	}
	for filter: int in _filter_buttons.keys():
		var button: Button = _filter_buttons[filter] as Button
		button.toggled.connect(_on_filter_toggled.bind(filter))

	_search_field.text_changed.connect(_on_search_text_changed)
	_search_field.hide()

# Aceita palavra que está VINDO DE UMA LACUNA: arrastar pra cima do glossário é o gesto de devolver.
# Palavra arrastada de dentro do próprio glossário não tem "from_blank" e é recusada — soltá-la de
# volta na lista não deveria fazer nada.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var payload: Dictionary = data as Dictionary
	return payload != null and payload.has("from_blank")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data as Dictionary
	if payload == null or not payload.has("from_blank"):
		return
	word_returned.emit(StringName(payload["word_id"]))

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

	if chip_scene != null:
		for word: GlossaryWord in _collect_words(profile):
			var chip: GlossaryWordChip = chip_scene.instantiate() as GlossaryWordChip
			if chip == null:
				push_error("[Profiling] - A cena de chip apontada no glossário não é um "
					+ "GlossaryWordChip")
				break
			_words_container.add_child(chip)
			chip.configure(word, ProfilingJournal.get_mark(_npc_id, word.id), _is_in_use(word))
			chip.word_activated.connect(_on_chip_word_activated)
			chip.mark_menu_requested.connect(_on_chip_mark_menu_requested)
			chip.word_returned.connect(_on_chip_word_returned)

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

	print("[Profiling] - Filtro do glossário %d: %s" % [filter, "ligado" if pressed else "desligado"])
	refresh()


func _on_search_text_changed(_text: String) -> void:
	refresh()


func _on_chip_word_activated(word_id: StringName) -> void:
	word_activated.emit(word_id)


func _on_chip_mark_menu_requested(word_id: StringName, chip_rect: Rect2) -> void:
	mark_menu_requested.emit(word_id, chip_rect)


func _on_chip_word_returned(word_id: StringName) -> void:
	word_returned.emit(word_id)
