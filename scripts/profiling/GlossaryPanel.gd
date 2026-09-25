## GlossaryPanel - o glossário de um NPC: as palavras que o jogador já descobriu, com contagem,
## filtros e pesquisa.
##
## COMO USAR: instancie scenes/profiling/GlossaryPanel.tscn e chame configure(). TODO o layout está
## na cena — título, contagem, os filtros, a lupa com o campo de pesquisa e a área das palavras — e
## as peças são soltas (âncoras, não contêineres): dá pra arrastar cada uma no editor. O script acha
## os nós pelo nome único (%), então mudar um nó de pai também não quebra nada. Este script só liga
## os nós, filtra a lista e instancia um chip (a cena apontada em "Chip Scene") por palavra
## descoberta.
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
## OS FILTROS: Lixo, Estrela, A-Z e Categoria, e a Lupa sempre à direita deles.
##
##   - Só UM filtro fica selecionado por vez (a lupa não conta: ela combina com qualquer um).
##   - O selecionado vai pra primeira posição; os outros ficam na ordem em que estão na cena.
##   - O selecionado pulsa devagar na escala, enquanto estiver selecionado.
##   - Lixo e Estrela têm dois passos: o 1º clique ORDENA (as marcadas primeiro), o 2º FILTRA (só as
##     marcadas) e o 3º desliga. A-Z e Categoria ligam e desligam.
##
## A CONTAGEM ("23/36") é palavras descobertas sobre o total do pool do NPC (NPCProfile).
##
## O painel não escreve nada no diário: ele avisa por signal, e a tela decide. Isso inclui a marca de
## lixo/estrela — o retângulo de marcas é um nó da tela (ver GlossaryMarkMenu), e não deste painel,
## justamente pra ele poder aparecer POR CIMA da lista sem ser empurrado pelo contêiner.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryPanel
extends Control

## Espaço para sinais

## Emitido quando o jogador clica numa palavra: ela vai pra primeira lacuna vazia que aceita a
## categoria dela. Quem resolve isso é a página.
signal word_activated(word_id: StringName)

## Emitido no clique direito numa palavra, com o retângulo dela na tela: é o pedido de abrir o
## retângulo de marcas ali.
signal mark_menu_requested(word_id: StringName, chip_rect: Rect2)

## Emitido quando uma palavra deve voltar pro glossário: o jogador a arrastou de uma lacuna e soltou
## aqui, ou soltou um arraste em cima de nada. Quem mexe na página é a tela.
signal word_returned(word_id: StringName)

## Espaço para enums

# Os filtros que disputam a seleção. TRASH e STAR ordenam e depois filtram; ALPHABETICAL e CATEGORY
# só ordenam. A lupa não está aqui: ela não disputa a seleção com ninguém.
enum Filter { TRASH, STAR, ALPHABETICAL, CATEGORY }

## Espaço para constantes

const NO_FILTER: int = -1

## Espaço para variáveis exportadas

## A cena de um retângulo de palavra (GlossaryWordChip.tscn).
@export var chip_scene: PackedScene

@export_group("Filtro selecionado")

## Escala do filtro selecionado, no meio do pulso.
@export_range(1.0, 1.5, 0.01) var selected_scale: float = 1.1

## Quanto a escala varia pra cima e pra baixo no pulso. Zero desliga o pulso.
@export_range(0.0, 0.3, 0.005) var pulse_amount: float = 0.04

## Duração de um pulso completo, em segundos. Maior = mais lento.
@export var pulse_period: float = 2.4

## Cor do Lixo/Estrela no segundo passo (mostrando SÓ as marcadas), pra diferenciar do primeiro
## (marcadas primeiro).
@export var only_marked_modulate: Color = Color(1.0, 0.85, 0.4)

## Espaço para variáveis

var _npc_id: StringName = &""
var _story: ProfilingStory

# Filter -> Button, montado a partir dos nós da cena. Existe pra o filtro ser tratado por valor de
# enum, e não por nome de nó espalhado pelo script.
var _filter_buttons: Dictionary = {}
# A ordem dos filtros na cena. É a ordem "fixa" dos que não estão selecionados.
var _scene_order: Array[int] = []
var _selected_filter: int = NO_FILTER
# Segundo passo do Lixo/Estrela: a lista mostra só as palavras com aquela marca.
var _only_marked: bool = false
var _pulse_time: float = 0.0

## Espaço para variáveis onready

@onready var _count_label: Label = %Count
@onready var _categories: Container = %Categories
@onready var _search_button: Button = %SearchFilter
@onready var _search_field: LineEdit = %SearchField
@onready var _words_container: Container = %Words

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if chip_scene == null:
		push_error("[Profiling] - Glossário sem \"Chip Scene\" apontada; nenhuma palavra vai aparecer")

	_filter_buttons = {
		Filter.TRASH: %TrashFilter,
		Filter.STAR: %StarFilter,
		Filter.ALPHABETICAL: %AlphabeticalFilter,
		Filter.CATEGORY: %CategoryFilter,
	}
	for filter: int in _filter_buttons.keys():
		var button: Button = _filter_buttons[filter] as Button
		button.pressed.connect(_on_filter_pressed.bind(filter))
		_scene_order.append(filter)
	_scene_order.sort_custom(func(left: int, right: int) -> bool:
		return (_filter_buttons[left] as Node).get_index() < (_filter_buttons[right] as Node).get_index())

	_search_button.toggled.connect(_on_search_toggled)
	_search_field.text_changed.connect(_on_search_text_changed)
	_search_field.hide()
	_apply_filter_buttons()


# Só roda com um filtro selecionado: é o pulso lento na escala dele.
func _process(delta: float) -> void:
	_pulse_time += delta
	var wave: float = sin(_pulse_time * TAU / maxf(pulse_period, 0.05))
	var value: float = selected_scale + pulse_amount * wave
	var button: Button = _filter_buttons[_selected_filter] as Button
	# O pivô no centro faz o botão crescer no lugar. Refeito a cada quadro porque o contêiner pode
	# redimensionar o botão (troca de idioma, por exemplo).
	button.pivot_offset = button.size * 0.5
	button.scale = Vector2(value, value)


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


# As palavras que a lista mostra agora: as descobertas, passadas pelo filtro, pela pesquisa e pela
# ordenação.
func _collect_words(profile: NPCProfile) -> Array[GlossaryWord]:
	var result: Array[GlossaryWord] = []
	var search: String = _search_field.text.strip_edges().to_lower() if _search_field != null else ""
	var mark_filter: GlossaryMark.Kind = _get_mark_filter()

	for word_id: StringName in ProfilingJournal.get_discovered_word_ids(_npc_id):
		var word: GlossaryWord = profile.find_word(word_id)
		if word == null:
			# Palavra no save que não está mais no pool do NPC: conteúdo renomeado ou removido depois
			# de alguém já ter jogado. Ignorar é o certo — o save não é reescrito, então voltar a
			# versão do conteúdo devolve a palavra.
			continue
		if _only_marked and ProfilingJournal.get_mark(_npc_id, word_id) != mark_filter:
			continue
		if not search.is_empty() and not word.get_display_text().to_lower().contains(search):
			continue
		result.append(word)

	# A ordem base é a alfabética de id (o diário devolve assim), que é estável e igual em qualquer
	# idioma. O filtro selecionado troca isso pelo que o jogador pediu.
	match _selected_filter:
		Filter.CATEGORY:
			result.sort_custom(_compare_by_category)
		Filter.ALPHABETICAL:
			result.sort_custom(_compare_by_text)
		Filter.TRASH, Filter.STAR:
			# As marcadas primeiro, sem embaralhar a ordem base dentro de cada grupo — sort_custom
			# não é estável, então é uma partição.
			var marked: Array[GlossaryWord] = []
			var rest: Array[GlossaryWord] = []
			for word: GlossaryWord in result:
				if ProfilingJournal.get_mark(_npc_id, word.id) == mark_filter:
					marked.append(word)
				else:
					rest.append(word)
			marked.append_array(rest)
			result = marked

	return result


# A marca que o filtro selecionado procura, ou NONE quando ele não é o Lixo nem a Estrela.
func _get_mark_filter() -> GlossaryMark.Kind:
	match _selected_filter:
		Filter.TRASH:
			return GlossaryMark.Kind.TRASH
		Filter.STAR:
			return GlossaryMark.Kind.STAR
		_:
			return GlossaryMark.Kind.NONE


# Diz se a palavra já está numa lacuna da história aberta. Sem história (o caso do diário), nenhuma
# palavra está em uso.
func _is_in_use(word: GlossaryWord) -> bool:
	if _story == null:
		return false
	return ProfilingJournal.find_blank_with_word(_story.id, word.id, _story.get_blank_count()) >= 0


# Põe os botões no estado da seleção: o selecionado primeiro e pressionado, os outros na ordem da
# cena, soltos e sem escala.
func _apply_filter_buttons() -> void:
	var order: Array[int] = _scene_order.duplicate()
	if _selected_filter != NO_FILTER:
		order.erase(_selected_filter)
		order.push_front(_selected_filter)

	for position_index: int in order.size():
		var filter: int = order[position_index]
		var button: Button = _filter_buttons[filter] as Button
		var is_selected: bool = filter == _selected_filter
		_categories.move_child(button, position_index)
		button.set_pressed_no_signal(is_selected)
		button.scale = Vector2.ONE
		button.modulate = only_marked_modulate if is_selected and _only_marked else Color.WHITE

	_pulse_time = 0.0
	set_process(_selected_filter != NO_FILTER)


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


# Clique num filtro. Outro filtro troca a seleção; o mesmo filtro avança o passo dele (Lixo/Estrela:
# ordenar -> só as marcadas -> desligado; A-Z/Categoria: ligado -> desligado).
func _on_filter_pressed(filter: int) -> void:
	if filter != _selected_filter:
		_selected_filter = filter
		_only_marked = false
	elif _get_mark_filter() != GlossaryMark.Kind.NONE and not _only_marked:
		_only_marked = true
	else:
		_selected_filter = NO_FILTER
		_only_marked = false

	print("[Profiling] - Filtro do glossário: %d%s" % [
		_selected_filter, " (só as marcadas)" if _only_marked else ""])
	_apply_filter_buttons()
	refresh()


func _on_search_toggled(pressed: bool) -> void:
	_search_field.visible = pressed
	if pressed:
		_search_field.grab_focus()
	else:
		# Fechar a lupa limpa a pesquisa: deixar um texto escondido filtrando a lista seria uma
		# lista misteriosamente incompleta.
		_search_field.clear()
		refresh()


func _on_search_text_changed(_text: String) -> void:
	refresh()


func _on_chip_word_activated(word_id: StringName) -> void:
	word_activated.emit(word_id)


func _on_chip_mark_menu_requested(word_id: StringName, chip_rect: Rect2) -> void:
	mark_menu_requested.emit(word_id, chip_rect)


func _on_chip_word_returned(word_id: StringName) -> void:
	word_returned.emit(word_id)
