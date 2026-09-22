## ProfilingPage - a página do profiling: o texto da história com as lacunas, a mensagem de acerto e,
## depois de resolvida, a história contada por inteiro.
##
## COMO USAR: o layout está em scenes/profiling/ProfilingPage.tscn (moldura do papel, margens, fonte
## da mensagem, espaçamento entre parágrafos). A ProfilingScreen instancia essa cena e chama
## configure(). A página não abre nem fecha nada e não decide nada sobre o sonho: ela desenha o
## estado que está no ProfilingJournal, escreve nele quando o jogador mexe numa lacuna, e anuncia o
## resultado da correção por signal.
##
## COMO O TEXTO É MONTADO: o texto vem do CSV com as lacunas escritas como {0}, {1}... (ver
## ProfilingStory). Cada parágrafo é uma cena de LINHA que embrulha sozinha, e cada palavra do texto
## é uma cena de PALAVRA dentro dela — as três cenas (linha, palavra, lacuna) estão apontadas no
## Inspector, então mexer na aparência do texto é abrir a cena, e não este script. É isso que deixa
## uma lacuna cheia empurrar o resto da frase sem sair da página.
##
## O jogador pode preencher parte das lacunas e sair: o que está preenchido fica no diário, e a
## página reabre exatamente como ele deixou, mesmo que ele tenha acordado no meio.
##
## A CORREÇÃO SÓ ACONTECE COM A PÁGINA CHEIA, e ela nunca aponta QUAL lacuna está errada (ver
## ProfilingEvaluation e o topo de ProfilingBlank.gd).
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingPage
extends VBoxContainer

## Espaço para sinais

## Emitido a cada redesenho, com o resultado da correção do estado atual. Quem decide o que fazer
## com um resultado "tudo certo" é a tela — inclusive porque ela precisa saber se a história JÁ
## estava resolvida antes (reabrir uma história resolvida não toca música de novo).
signal evaluated(evaluation: ProfilingEvaluation)

## Espaço para variáveis exportadas

@export_group("Peças")

## A cena de uma lacuna (ProfilingBlank.tscn).
@export var blank_scene: PackedScene

## A cena de um parágrafo do texto: um contêiner que embrulha (ProfilingPageLine.tscn).
@export var line_scene: PackedScene

## A cena de uma palavra do texto da história (ProfilingPageWord.tscn).
@export var word_scene: PackedScene

@export_group("Regras")

## Até quantas palavras erradas contam como "duas ou menos" na mensagem amarela. É a variável de
## balanceamento da dificuldade da correção; o GDD pede 2.
@export var few_wrong_limit: int = ProfilingEvaluation.FEW_WRONG_LIMIT

@export_group("Cores da mensagem")

## Cor da mensagem de acerto total.
@export var color_all_correct: Color = Color(0.45, 0.9, 0.5)

## Cor da mensagem de "duas ou menos erradas".
@export var color_few_wrong: Color = Color(1.0, 0.85, 0.3)

## Cor da mensagem de "várias incorretas".
@export var color_many_wrong: Color = Color(1.0, 0.4, 0.35)

## Espaço para variáveis

var _profile: NPCProfile
var _story: ProfilingStory
# Depois de resolvida, a página troca as lacunas pelo texto completo. A troca não é automática: a
# tela pede, porque o GDD manda mostrar a mensagem de acerto por alguns segundos antes.
var _show_resolved: bool = false

## Espaço para variáveis onready

@onready var _message: Label = $Message
@onready var _lines: VBoxContainer = $PagePanel/Margin/Content/Lines
@onready var _resolved_text: ClickableWordText = $PagePanel/Margin/Content/ResolvedText

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if blank_scene == null or line_scene == null or word_scene == null:
		push_error("[Profiling] - Página sem as cenas de lacuna/linha/palavra apontadas; "
			+ "o texto da história não vai ser montado")
	_message.hide()
	_resolved_text.hide()

## Espaço para funções personalizadas

# Aponta a página para a história de uma emoção. Uma história já resolvida abre direto no texto
# completo: o jogador pode reler a história quantas vezes quiser.
func configure(profile: NPCProfile, story: ProfilingStory) -> void:
	_profile = profile
	_story = story
	_show_resolved = story != null and ProfilingJournal.is_story_solved(story.id)
	refresh()


# Redesenha a página e anuncia a correção. Chamada a cada mudança do diário — reconstruir é simples,
# e o texto tem dezenas de nós, não milhares.
func refresh() -> void:
	if _lines == null or _story == null:
		return

	var fills: PackedStringArray = ProfilingJournal.get_fills(_story.id, _story.get_blank_count())
	var evaluation: ProfilingEvaluation = ProfilingEvaluation.evaluate(_story, fills, few_wrong_limit)

	if _show_resolved:
		_draw_resolved()
	else:
		_draw_template(fills, evaluation)

	_update_message(evaluation)
	evaluated.emit(evaluation)


# Troca as lacunas pelo texto completo da história. Chamada pela tela depois da mensagem de acerto.
func show_resolved() -> void:
	_show_resolved = true
	refresh()


# Usa uma palavra do glossário sem arrastar: ela vai pra primeira lacuna vazia, ou volta pro
# glossário se já estiver numa lacuna.
#
# É o atalho de quem joga de teclado/controle (não há como arrastar com um analógico) e de quem está
# preenchendo rápido. Ele não escolhe lacuna "melhor" de propósito: a primeira vazia é previsível, e
# palpite nenhum da tela sobre onde a palavra "deveria" ir é desejável num quebra-cabeça.
func activate_word(word_id: StringName) -> void:
	if _story == null or _show_resolved:
		return

	var blank_count: int = _story.get_blank_count()
	var current: int = ProfilingJournal.find_blank_with_word(_story.id, word_id, blank_count)
	if current >= 0:
		ProfilingJournal.clear_blank(_story.id, current, blank_count)
		return

	var fills: PackedStringArray = ProfilingJournal.get_fills(_story.id, blank_count)
	for index: int in blank_count:
		if fills[index].is_empty():
			_fill_blank(index, word_id)
			return

	print("[Profiling] - Página cheia: a palavra \"%s\" não tem lacuna vazia pra entrar" % word_id)


# Devolve uma palavra ao glossário: acha a lacuna em que ela está e esvazia.
#
# Público porque este gesto TERMINA fora da página — o jogador solta a palavra em cima do glossário,
# ou solta em cima de nada. Recebe o ID da palavra, e não o índice da lacuna, porque nos dois casos
# quem sobrou na mão de quem avisa é a palavra. Palavra que não está em lacuna nenhuma não faz nada.
func return_word(word_id: StringName) -> void:
	if _story == null:
		return
	var blank_count: int = _story.get_blank_count()
	var index: int = ProfilingJournal.find_blank_with_word(_story.id, word_id, blank_count)
	if index < 0:
		return
	ProfilingJournal.clear_blank(_story.id, index, blank_count)


# Põe uma palavra numa lacuna.
#
# PALAVRA EM CONJUNTO NÃO PREENCHE JUNTO: "[MARCOS]/[CASTRO]" vem junto na DESCOBERTA (clicar
# em uma delas no texto traz as duas pro glossário), e para aí. Em que lacuna cada metade entra é
# escolha do jogador — inclusive porque a página não pode olhar a solução pra adivinhar a ordem
# sem entregar a resposta.
func _fill_blank(index: int, word_id: StringName) -> void:
	ProfilingJournal.set_blank(_story.id, index, word_id, _story.get_blank_count())


# Desenha o texto com as lacunas.
func _draw_template(fills: PackedStringArray, evaluation: ProfilingEvaluation) -> void:
	_clear_lines()
	_resolved_text.hide()
	_lines.show()
	if line_scene == null or word_scene == null or blank_scene == null:
		return

	var row: HFlowContainer = _add_row()
	if row == null:
		return
	# O CSV guarda a quebra de parágrafo como "\n". Dependendo de como o texto foi escrito, ela chega
	# aqui já como quebra de linha ou ainda como os dois caracteres — normalizar cobre os dois casos.
	var source: String = _story.get_template_text().replace("\\n", "\n")

	for segment: Dictionary in _story.build_segments(source):
		var blank_index: int = int(segment.get("blank", -1))
		if blank_index >= 0:
			_add_blank(row, blank_index, fills, evaluation)
			continue

		var paragraphs: PackedStringArray = String(segment.get("text", "")).split("\n")
		for paragraph_index: int in paragraphs.size():
			if paragraph_index > 0:
				row = _add_row()
			for word_text: String in paragraphs[paragraph_index].split(" ", false):
				_add_word(row, word_text)


# Desenha o texto completo da história, que substitui o texto com lacunas quando o jogador acerta.
#
# Ele é um ClickableWordText porque a história resolvida é texto de NPC como qualquer outro: se o
# design marcar uma palavra nele com a notação do GDD ([FACA]), ela vira palavra clicável e entra no
# glossário. Sem marcação nenhuma, ele é só um texto.
func _draw_resolved() -> void:
	_clear_lines()
	_lines.hide()
	_resolved_text.show()
	_resolved_text.set_marked_text(_story.get_resolved_text().replace("\\n", "\n"), _get_owner_id())


# Põe uma lacuna na fileira, já com a palavra que está nela (se estiver).
#
# O checkmark verde só aparece quando a página INTEIRA está correta: é o "todas as palavras ganham um
# checkmark verde ao seu lado" do GDD, que acontece no acerto, e não lacuna por lacuna.
func _add_blank(row: HFlowContainer, index: int, fills: PackedStringArray,
		evaluation: ProfilingEvaluation) -> void:
	var blank: ProfilingBlank = blank_scene.instantiate() as ProfilingBlank
	if blank == null:
		push_error("[Profiling] - A cena de lacuna apontada na página não é um ProfilingBlank")
		return
	blank.word_dropped.connect(_on_blank_word_dropped)
	blank.cleared.connect(_on_blank_cleared)
	row.add_child(blank)

	var word: GlossaryWord = null
	if index < fills.size() and not fills[index].is_empty():
		word = ProfilingCatalog.find_word(StringName(fills[index]))
	blank.configure(index, word, evaluation.is_solved())


# Põe uma palavra do texto da história na fileira. Ela não é clicável: o texto com lacunas é o
# enunciado, e as palavras que o jogador junta vêm do glossário.
func _add_word(row: HFlowContainer, text_value: String) -> void:
	var label: Label = word_scene.instantiate() as Label
	if label == null:
		push_error("[Profiling] - A cena de palavra apontada na página não é um Label")
		return
	label.text = text_value
	row.add_child(label)


# Uma fileira de texto: embrulha sozinha quando a frase não cabe na largura da página.
func _add_row() -> HFlowContainer:
	var row: HFlowContainer = line_scene.instantiate() as HFlowContainer
	if row == null:
		push_error("[Profiling] - A cena de linha apontada na página não é um HFlowContainer")
		return null
	_lines.add_child(row)
	return row


# Escreve a mensagem acima da página, na cor do resultado. Página incompleta não tem mensagem: o GDD
# só avisa quando tudo está preenchido.
func _update_message(evaluation: ProfilingEvaluation) -> void:
	var key: String = evaluation.get_message_key()
	if key.is_empty() or _show_resolved:
		_message.hide()
		return

	_message.text = tr(key)
	match evaluation.result:
		ProfilingEvaluation.Result.ALL_CORRECT:
			_message.modulate = color_all_correct
		ProfilingEvaluation.Result.FEW_WRONG:
			_message.modulate = color_few_wrong
		_:
			_message.modulate = color_many_wrong
	_message.show()


func _clear_lines() -> void:
	for child: Node in _lines.get_children():
		child.queue_free()


# De quem é o glossário desta página. A página precisa disso pra saber se a palavra em conjunto já
# foi descoberta, e pra mandar as palavras do texto resolvido pro glossário certo.
func _get_owner_id() -> StringName:
	if _profile == null:
		return &""
	return _profile.npc_id


func _on_blank_word_dropped(index: int, word_id: StringName) -> void:
	if _story != null:
		_fill_blank(index, word_id)


func _on_blank_cleared(index: int) -> void:
	if _story != null:
		ProfilingJournal.clear_blank(_story.id, index, _story.get_blank_count())
