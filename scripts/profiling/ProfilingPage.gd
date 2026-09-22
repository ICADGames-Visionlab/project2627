## ProfilingPage - a página do profiling: o texto da história com as lacunas, a mensagem de acerto e,
## depois de resolvida, a história contada por inteiro.
##
## COMO USAR: a ProfilingScreen instancia isto e chama configure(). A página não abre nem fecha nada
## e não decide nada sobre o sonho: ela desenha o estado que está no ProfilingJournal, escreve nele
## quando o jogador mexe numa lacuna, e anuncia o resultado da correção por signal.
##
## COMO O TEXTO É MONTADO: o texto vem do CSV com as lacunas escritas como {0}, {1}... (ver
## ProfilingStory). Cada parágrafo é uma fileira que embrulha sozinha (HFlowContainer) e cada palavra
## do texto é um Label dentro dela — é isso que deixa uma lacuna cheia empurrar o resto da frase sem
## sair da página, em vez de o texto virar uma linha só que estoura pra fora da tela.
##
## O jogador pode preencher parte das lacunas e sair: o que está preenchido fica no diário, e a
## página reabre exatamente como ele deixou, mesmo que ele tenha acordado no meio.
##
## A CORREÇÃO SÓ ACONTECE COM A PÁGINA CHEIA, e ela nunca aponta QUAL lacuna está errada — só quantas
## (ver ProfilingEvaluation e o topo de ProfilingBlank.gd).
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingPage
extends VBoxContainer

## Espaço para sinais

## Emitido a cada redesenho, com o resultado da correção do estado atual. Quem decide o que fazer
## com um resultado "tudo certo" é a tela — inclusive porque ela precisa saber se a história JÁ
## estava resolvida antes (reabrir uma história resolvida não toca música de novo).
signal evaluated(evaluation: ProfilingEvaluation)

## Espaço para constantes

# Cor de cada mensagem de resultado, na ordem do GDD: verde no acerto, amarelo em duas ou menos
# erradas, vermelho em três ou mais.
const COLOR_ALL_CORRECT: Color = Color(0.45, 0.9, 0.5)
const COLOR_FEW_WRONG: Color = Color(1.0, 0.85, 0.3)
const COLOR_MANY_WRONG: Color = Color(1.0, 0.4, 0.35)

## Espaço para variáveis exportadas

## Até quantas palavras erradas contam como "duas ou menos" na mensagem amarela. É a variável de
## balanceamento da dificuldade da correção; o GDD pede 2.
@export var few_wrong_limit: int = ProfilingEvaluation.FEW_WRONG_LIMIT

## Tamanho da fonte do texto da história.
@export var text_font_size: int = 24

## Espaço entre as palavras do texto, em pixels. Some ao espaço natural da fonte, então valores
## grandes soltam a frase.
@export var word_separation: int = 6

## Espaço para variáveis

var _profile: NPCProfile
var _story: ProfilingStory
# Depois de resolvida, a página troca as lacunas pelo texto completo. A troca não é automática: a
# tela pede, porque o GDD manda mostrar a mensagem de acerto por alguns segundos antes.
var _show_resolved: bool = false

var _message: Label
var _panel: PanelContainer
var _lines: VBoxContainer
var _resolved_text: ClickableWordText

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

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
			ProfilingJournal.set_blank(_story.id, index, word_id, blank_count)
			return

	print("[Profiling] - Página cheia: a palavra \"%s\" não tem lacuna vazia pra entrar" % word_id)


# Desenha o texto com as lacunas.
func _draw_template(fills: PackedStringArray, evaluation: ProfilingEvaluation) -> void:
	_clear_lines()
	_resolved_text.hide()
	_lines.show()

	var row: HFlowContainer = _add_row()
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
			for word: String in paragraphs[paragraph_index].split(" ", false):
				row.add_child(_build_word_label(word))


# Desenha o texto completo da história, que substitui o texto com lacunas quando o jogador acerta.
#
# Ele é um ClickableWordText porque a história resolvida é texto de NPC como qualquer outro: se o
# design marcar uma palavra nele com a notação do GDD ([FACA]), ela vira palavra clicável e entra no
# glossário. Sem marcação nenhuma, ele é só um texto.
func _draw_resolved() -> void:
	_clear_lines()
	_lines.hide()
	_resolved_text.show()
	var owner_id: StringName = _profile.npc_id if _profile != null else &""
	_resolved_text.set_marked_text(_story.get_resolved_text().replace("\\n", "\n"), owner_id)


# Põe uma lacuna na fileira, já com a palavra que está nela (se estiver).
#
# O checkmark verde só aparece quando a página INTEIRA está correta: é o "todas as palavras ganham um
# checkmark verde ao seu lado" do GDD, que acontece no acerto, e não lacuna por lacuna.
func _add_blank(row: HFlowContainer, index: int, fills: PackedStringArray,
		evaluation: ProfilingEvaluation) -> void:
	var blank: ProfilingBlank = ProfilingBlank.new()
	blank.word_dropped.connect(_on_blank_word_dropped)
	blank.cleared.connect(_on_blank_cleared)
	row.add_child(blank)

	var word: GlossaryWord = null
	if index < fills.size() and not fills[index].is_empty():
		word = ProfilingCatalog.find_word(StringName(fills[index]))
	blank.configure(index, word, evaluation.is_solved())


# Uma palavra do texto da história. Não é clicável: o texto com lacunas é o enunciado, e as palavras
# que o jogador junta vêm do glossário.
func _build_word_label(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	# O texto já veio traduzido do CSV; traduzir de novo faria o Godot procurar cada palavra da frase
	# como se fosse uma chave.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", text_font_size)
	return label


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
			_message.add_theme_color_override("font_color", COLOR_ALL_CORRECT)
		ProfilingEvaluation.Result.FEW_WRONG:
			_message.add_theme_color_override("font_color", COLOR_FEW_WRONG)
		_:
			_message.add_theme_color_override("font_color", COLOR_MANY_WRONG)
	_message.show()


# Monta a moldura da página: mensagem em cima, painel com o texto embaixo.
func _build() -> void:
	add_theme_constant_override("separation", 12)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_message.add_theme_font_size_override("font_size", 26)
	_message.hide()
	add_child(_message)

	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_theme_stylebox_override("panel", _build_page_style())
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	margin.add_child(content)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 18)
	content.add_child(_lines)

	_resolved_text = ClickableWordText.new()
	_resolved_text.add_theme_font_size_override("normal_font_size", text_font_size)
	_resolved_text.hide()
	content.add_child(_resolved_text)


# Uma fileira de texto: embrulha sozinha quando a frase não cabe na largura da página.
func _add_row() -> HFlowContainer:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", word_separation)
	row.add_theme_constant_override("v_separation", 10)
	_lines.add_child(row)
	return row


func _clear_lines() -> void:
	for child: Node in _lines.get_children():
		child.queue_free()


# O fundo da página. PLACEHOLDER: papel resolvido em StyleBox, sem arte.
func _build_page_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.11, 0.96)
	style.border_color = Color(1.0, 0.95, 0.85, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style


func _on_blank_word_dropped(index: int, word_id: StringName) -> void:
	if _story != null:
		ProfilingJournal.set_blank(_story.id, index, word_id, _story.get_blank_count())


func _on_blank_cleared(index: int) -> void:
	if _story != null:
		ProfilingJournal.clear_blank(_story.id, index, _story.get_blank_count())
