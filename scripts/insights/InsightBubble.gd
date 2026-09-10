# InsightBubble.gd — A caixa de texto do canal de ambiente: o que o mundo tem a dizer, dito no lugar
# onde está a coisa, sem parar o jogo.
#
# Nasce como filha da fonte, então acompanha o objeto se ele se mexer e some junto com ele. Fecha ao
# clicar fora, ao apertar Esc ou quando o jogador se afasta — quem manda fechar por distância é a
# própria fonte, que é quem sabe o raio.
#
# PLACEHOLDER: o painel usa o tema padrão da engine. A arte final troca o StyleBox da cena sem mexer
# neste script — ver a issue de substituição de placeholder.
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

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label


func _ready() -> void:
	_panel.custom_minimum_size.x = bubble_width
	_label.max_lines_visible = max_lines
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
	if mouse_event != null and mouse_event.pressed:
		# O clique no próprio orbe é consumido pelo marcador e nunca chega aqui, então "clicar fora"
		# é literalmente qualquer clique que sobrou.
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Escreve o texto do insight na caixa. Recebe a chave, nunca o texto: tr() é chamado aqui, na hora de
# exibir, para a caixa aberta continuar certa se o idioma mudar.
func show_text(text_key: String) -> void:
	_label.text = tr(text_key)


# Fecha a caixa. Idempotente: fechar duas vezes (clique e afastamento no mesmo frame) não emite o
# signal duas vezes nem tenta liberar o nó de novo.
func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
