# InsightBubble.gd — A caixa de texto do canal de ambiente: o que o mundo tem a dizer, dito no lugar
# onde está a coisa, sem parar o jogo.
#
# Nasce como filha da fonte, então acompanha o objeto se ele se mexer e some junto com ele. Fecha a
# qualquer clique (inclusive no próprio orbe, que funciona como liga/desliga), ao apertar Esc ou ao
# apertar de novo a tecla de interagir no mesmo orbe. Não fecha por distância: o insight de ambiente
# abre de qualquer lugar, e fechar ao se afastar contradiria isso.
#
# PALAVRAS DO GLOSSÁRIO: o texto aceita a marcação do GDD no translations.csv ("Achei uma [FACA] no
# beco.", ver ClickableWordText). A palavra aparece sublinhada, mas NÃO se clica: quando a caixa
# fecha, por qualquer caminho, todas as palavras marcadas vão pro glossário sozinhas e voam da caixa
# pro diário (WordDiscoveryToast.discover_from). Ler o insight já é ter achado a pista.
#
# PLACEHOLDER: o painel usa um StyleBox provisório (escuro, borda verde). A arte final troca o
# StyleBox da cena sem mexer neste script — ver a issue de substituição de placeholder.
class_name InsightBubble
extends Node2D

# Emitido quando a caixa se fecha, por qualquer um dos caminhos. A fonte escuta para esquecer a
# referência: signal local porque emissor e ouvinte têm relação direta.
signal closed

@export_group("Layout")
@export var bubble_width: float = 420.0
# Teto de linhas do canal de ambiente. Texto que não cabe em quatro linhas é fala de personagem, e
# fala de personagem vai para a tela de diálogo.
@export var max_lines: int = 4
# Distância entre a ponta de baixo da caixa e o ponto onde ela foi ancorada (o orbe).
@export var vertical_gap: float = 18.0

@export_group("Animação")
@export var fade_time: float = 0.12

@export_group("Palavras do glossário")
# Palavra marcada que o jogador ainda não tem: sublinhada nesta cor. O GDD pede vermelho, igual à
# fala do diálogo e ao ClickableWordText.
@export var glossary_word_color: Color = Color(1.0, 0.35, 0.3)
# Palavra marcada que já está no glossário: sem sublinhado. Por padrão, a cor do resto do texto.
@export var glossary_word_collected_color: Color = Color(0.875, 0.875, 0.875)

# O orbe que abriu esta caixa, ou null quando ela foi aberta sem orbe (pela ação de debug).
var _anchor_marker: InsightMarker = null
# O texto traduzido, ainda com a marcação [FACA]: é dele que saem as palavras colhidas ao fechar.
var _source_text: String = ""

@onready var _panel: PanelContainer = $Panel
@onready var _label: RichTextLabel = $Panel/Margin/Label


func _ready() -> void:
	_panel.custom_minimum_size.x = bubble_width
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_time)


func _process(_delta: float) -> void:
	# A altura do painel só é conhecida depois que o texto quebra em linhas, e ela muda quando o
	# idioma muda. Reposicionar todo frame custa duas contas e evita a caixa nascer torta no primeiro
	# frame — que é exatamente o frame em que o jogador olha para ela.
	_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y - vertical_gap)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and _is_click_button(mouse_event.button_index):
		close()
		# Na engine, _unhandled_input roda ANTES do physics picking que entrega o clique às Area2D.
		# Clique no próprio orbe: consome, senão o orbe recebe o mesmo clique e reabre a caixa que
		# acabou de fechar. Clique em qualquer outro lugar: deixa seguir, para clicar em outro orbe
		# trocar a caixa num clique só.
		if is_instance_valid(_anchor_marker) and _anchor_marker.is_mouse_event_inside(mouse_event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Guarda o orbe que abriu a caixa, para um clique nele fechar a caixa em vez de reabri-la.
func set_anchor_marker(marker: InsightMarker) -> void:
	_anchor_marker = marker


# Escreve o texto do insight na caixa. Recebe a chave, nunca o texto: tr() é chamado aqui, na hora de
# exibir, para a caixa aberta continuar certa se o idioma mudar.
func show_text(text_key: String) -> void:
	_source_text = tr(text_key)
	_label.text = ClickableWordText.render_markup(_source_text, &"", glossary_word_color,
		glossary_word_collected_color, false)
	_warn_if_too_long.call_deferred(text_key)


# Fecha a caixa. Idempotente: fechar duas vezes no mesmo frame não emite o signal duas vezes nem
# tenta liberar o nó de novo.
func close() -> void:
	if is_queued_for_deletion():
		return
	_collect_glossary_words()
	closed.emit()
	queue_free()


# Põe no glossário as palavras marcadas no texto, voando do meio da caixa. Palavra que o jogador já
# tinha não gera aviso nem animação (o ProfilingJournal só anuncia palavra nova).
func _collect_glossary_words() -> void:
	var word_ids: Array[StringName] = ClickableWordText.find_word_ids(_source_text)
	if word_ids.is_empty():
		return
	var center: Vector2 = _panel.get_global_transform_with_canvas() * (_panel.size * 0.5)
	if WordDiscoveryToast.discover_from(center, word_ids):
		print("[Insights] - Palavra(s) %s colhida(s) do insight" % [word_ids])


# O Label antigo cortava o texto em max_lines; o RichTextLabel (que o sublinhado exige) não tem esse
# corte, então o teto virou aviso: texto que não cabe é fala de personagem e vai pra tela de diálogo.
func _warn_if_too_long(text_key: String) -> void:
	if _label.get_line_count() > max_lines:
		push_warning("[Insights] - AVISO: \"%s\" ocupa %d linhas na caixa, o teto é %d" % [
			text_key, _label.get_line_count(), max_lines])


# Diz se o botão do mouse conta como clique para fechar a caixa. A roda do mouse chega como
# InputEventMouseButton pressionado também, e rolar a tela não pode fechar o que o jogador está lendo.
func _is_click_button(button_index: MouseButton) -> bool:
	return button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT or button_index == MOUSE_BUTTON_MIDDLE
