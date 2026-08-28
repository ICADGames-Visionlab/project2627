# DebugStatsOverlay.gd — OSD de desempenho no estilo MSI Afterburner / RivaTuner Statistics Server.
#
# Fica por cima do jogo mostrando o custo real de cada quadro: quanto tempo ele levou, quanto disso
# foi trabalho de CPU, quanto foi de GPU, quanta memória o processo segura e qual a ocupação de
# CPU/GPU dentro do orçamento do quadro. Cada linha tem um mini-gráfico do histórico recente,
# porque a média esconde justamente o que interessa numa investigação de performance: o pico de um
# quadro só que causou o engasgo.
#
# A cena é casca: nenhuma linha existe nela, todas nascem em _build_rows(). Mesmo padrão do
# DebugMenuOverlay — trocar as métricas exibidas é mexer só neste script.
#
# O que cada métrica realmente mede (e o que ela não mede) está em docs/debug_menu.md. A diferença
# mais importante em relação ao Afterburner: "uso de CPU/GPU" aqui é ocupação do orçamento do
# quadro, não a utilização do sistema inteiro que o Afterburner lê do driver — um jogo não tem
# acesso a esse número.
#
# Os textos deste painel são intencionalmente hardcoded: a exigência de tr() do Guideline vale
# para texto exibido ao jogador, e este overlay não existe em build de release.
extends CanvasLayer

# Métricas exibidas. A ordem na tela é a ordem de _build_rows(), não a daqui.
enum Metric {
	FRAME_MS,
	CPU_MS,
	GPU_MS,
	RAM_MB,
	CPU_PERCENT,
	GPU_PERCENT,
}

# Cantos onde o painel pode ficar. O prefixo evita colidir com o enum global `Corner` do Godot.
enum PanelCorner {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_RIGHT,
	BOTTOM_LEFT,
}

# Amostras guardadas pelos gráficos das métricas medidas por quadro (~3 s a 60 fps). Acima disso o
# histórico vira uma mancha na largura estreita do painel.
const SAMPLE_CAPACITY: int = 180
# Amostras dos gráficos de uso, que ganham um ponto por refresh e não por quadro (~15 s no
# intervalo padrão). Menos pontos porque cada ponto já representa um intervalo inteiro.
const USAGE_SAMPLE_CAPACITY: int = 60
const BYTES_PER_MEGABYTE: float = 1048576.0
# Famílias monoespaçadas por ordem de preferência. SystemFont cai na fonte padrão da engine se
# nenhuma delas existir na máquina, então a lista pode ser otimista.
const MONO_FONT_NAMES: Array[String] = [
	"Consolas", "Cascadia Mono", "JetBrains Mono", "DejaVu Sans Mono", "Menlo",
	"Liberation Mono", "Courier New"
]
# Texto de uma métrica que ainda não recebeu nenhuma leitura válida (ver MetricRow.has_reading).
const NO_READING_TEXT: String = "--"
# Piso de escala dos gráficos de tempo de CPU e GPU. Baixo de propósito: com o piso do gráfico de
# quadro (dezenas de ms), um custo saudável de fração de milissegundo vira uma linha reta colada no
# fundo e o gráfico não mostra forma nenhuma. Acima deste piso a escala acompanha o pico da janela.
const TIME_GRAPH_FLOOR_MS: float = 1.0
# Prioridades de processamento do relógio de quadro e do overlay. A ordem de processamento no Godot
# é global e ordenada por prioridade, então valores extremos garantem "primeiro de todos" e "último
# de todos" sem depender de quem mais existe na árvore. Não usamos os limites do int32 porque a
# engine trunca a prioridade nesse tipo.
const PROCESS_PRIORITY_FIRST: int = -1000000
const PROCESS_PRIORITY_LAST: int = 1000000
# Largura das colunas em caracteres. Multiplicadas pela largura de um caractere da fonte, mantêm o
# alinhamento das casas decimais mesmo quando font_size muda.
const NAME_COLUMN_CHARS: float = 10.0
const VALUE_COLUMN_CHARS: float = 7.0
const UNIT_COLUMN_CHARS: float = 3.0
# Proporção largura/altura típica de uma fonte monoespaçada, usada só para dimensionar as colunas.
const MONO_CHAR_RATIO: float = 0.62

@export_group("Layout")
# Largura fixa do painel. O default cabe em 720p sem cobrir HUD de jogo.
@export var panel_width: float = 272.0
# Distância do painel até a borda da tela, no canto em que ele estiver.
@export var screen_margin: float = 8.0
@export var font_size: int = 13
@export var graph_height: float = 16.0
@export var show_graphs: bool = true
# Intervalo de atualização dos números. As amostras continuam sendo colhidas todo quadro; só a
# escrita na tela é espaçada, porque a 60 fps o valor instantâneo troca rápido demais para ler.
@export var refresh_interval_seconds: float = 0.25

@export_group("Limites de alerta")
# Orçamento de um quadro a 60 fps: acima disso a linha fica amarela.
@export var frame_budget_ms: float = 16.67
# Orçamento de um quadro a 30 fps: acima disso a linha fica vermelha.
@export var frame_critical_ms: float = 33.33
@export var ram_budget_mb: float = 768.0
@export var ram_critical_mb: float = 1536.0
@export var usage_warning_percent: float = 70.0
@export var usage_critical_percent: float = 90.0

@export_group("Cores")
@export var color_normal: Color = Color("7cfc5a")
@export var color_warning: Color = Color("ffd23f")
@export var color_critical: Color = Color("ff5a5a")
@export var color_label: Color = Color("9fb2c4")
# Cor de métrica ainda sem leitura válida.
@export var color_unavailable: Color = Color("6b7785")
@export var panel_color: Color = Color(0.03, 0.04, 0.06, 0.78)
@export var panel_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)

var _rows: Dictionary = {}   # Metric -> MetricRow, na ordem de _build_rows()
var _corner: PanelCorner = PanelCorner.TOP_RIGHT
var _viewport_rid: RID
var _mono_font: SystemFont
var _last_frame_tick_usec: int = 0
var _elapsed_seconds: float = 0.0
var _frame_clock: FrameClock
# Soma dos passos de física deste quadro. A física roda antes do passo de processamento e pode
# rodar zero ou várias vezes no mesmo quadro, por isso acumula em vez de guardar um instante.
var _physics_span_usec: int = 0

@onready var _anchor: Control = $Anchor
@onready var _panel: PanelContainer = $Anchor/Panel
@onready var _title_label: Label = $Anchor/Panel/Margin/Layout/Header/Title
@onready var _fps_label: Label = $Anchor/Panel/Margin/Layout/Header/Fps
@onready var _rows_container: VBoxContainer = $Anchor/Panel/Margin/Layout/Rows


# Marca o instante em que cada passo do quadro começa, do lado da CPU. É um nó separado por causa
# de como o Godot ordena o processamento: a ordem é global e definida por prioridade, então este nó
# roda com a prioridade mínima (primeiro de todos) e o overlay com a máxima (último de todos). A
# diferença entre os dois instantes é o tempo que a árvore inteira levou naquele passo.
#
# Este rodeio existe porque a engine não expõe o custo de CPU de um quadro específico: os monitores
# Performance.TIME_PROCESS/TIME_PHYSICS_PROCESS são publicados uma vez por segundo e trazem o PIOR
# quadro do segundo. Num teste com vsync a 60 fps eles reportavam 30 a 44 ms para quadros de
# 16,67 ms — usá-los aqui deixava a linha "Uso CPU" grudada em 100%.
class FrameClock extends Node:
	var process_started_usec: int = 0
	var physics_started_usec: int = 0

	func _process(_delta: float) -> void:
		process_started_usec = Time.get_ticks_usec()

	func _physics_process(_delta: float) -> void:
		physics_started_usec = Time.get_ticks_usec()


# Mini-gráfico de uma métrica ao longo das últimas `capacity` amostras. Desenhado à mão em _draw()
# porque um Line2D dentro de um container exigiria reconverter coordenadas a cada redimensionamento
# do painel — aqui o desenho já acontece no retângulo final da linha.
class Sparkline extends Control:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var capacity: int = 1
	var line_color: Color = Color.WHITE
	# Piso da escala vertical. Sem ele, um gráfico de valores minúsculos se auto-escalaria e
	# transformaria ruído irrelevante em picos dramáticos.
	var scale_floor: float = 1.0
	# Fundo discreto, mas visível o bastante para emoldurar o gráfico: sem ele, uma linha colada no
	# fundo da caixa parece um separador perdido em vez de uma métrica em repouso.
	var background_color: Color = Color(1.0, 1.0, 1.0, 0.08)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
		if samples.size() < 2 or capacity < 2:
			return
		var peak: float = scale_floor
		for value: float in samples:
			peak = maxf(peak, value)
		if peak <= 0.0:
			return
		# Histórico incompleto fica encostado na direita: o gráfico cresce da direita para a
		# esquerda, como no RivaTuner, então o instante atual está sempre na mesma posição.
		var step: float = size.x / float(capacity - 1)
		var offset: int = capacity - samples.size()
		var usable_height: float = maxf(size.y - 1.0, 1.0)
		var points: PackedVector2Array = PackedVector2Array()
		points.resize(samples.size())
		for index: int in samples.size():
			var normalized: float = clampf(samples[index] / peak, 0.0, 1.0)
			points[index] = Vector2(
				float(offset + index) * step,
				usable_height - normalized * usable_height
			)
		draw_polyline(points, line_color, 1.0, true)


# Uma linha do OSD: os três rótulos (nome, valor, unidade), o mini-gráfico, o acumulador que
# transforma as amostras do intervalo num número legível e os limites de cor dela.
#
# A linha guarda os próprios limites em vez de o código consultar a métrica: assim _paint_row() não
# precisa saber qual métrica está desenhando, e acrescentar uma métrica nova é uma chamada a
# _add_row() e nada mais.
class MetricRow:
	var name_label: Label
	var value_label: Label
	var unit_label: Label
	var graph: Sparkline
	# Formato de impressão do valor, com casas decimais fixas. Casa decimal variável faria a coluna
	# dançar a cada atualização e derrubaria o alinhamento que a fonte monoespaçada garante.
	var value_format: String = "%.2f"
	var warning_threshold: float = 0.0
	var critical_threshold: float = 0.0
	# true para linhas calculadas em _derive_usage_rows() a partir de outras, e não amostradas
	# diretamente por quadro.
	var derived: bool = false
	var accumulator: float = 0.0
	var sample_count: int = 0
	var last_average: float = 0.0
	# Vira true na primeira leitura maior que zero. Enquanto for false a linha mostra "--": há
	# métrica que a engine só publica depois de um segundo e métrica que o driver simplesmente não
	# reporta, e nos dois casos escrever "0,00" seria mentira, não medição.
	var has_reading: bool = false


func _ready() -> void:
	# Sem isto, o OSD congela junto com o jogo quando o menu de debug pausa a árvore — e o custo de
	# um quadro com o jogo pausado é exatamente o que se quer comparar contra o jogo rodando.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# O overlay fecha os dois passos do quadro; o FrameClock abre. Ver FrameClock.
	process_priority = PROCESS_PRIORITY_LAST
	process_physics_priority = PROCESS_PRIORITY_LAST
	_frame_clock = FrameClock.new()
	_frame_clock.name = "FrameClock"
	_frame_clock.process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_clock.process_priority = PROCESS_PRIORITY_FIRST
	_frame_clock.process_physics_priority = PROCESS_PRIORITY_FIRST
	add_child(_frame_clock)
	_viewport_rid = get_viewport().get_viewport_rid()
	# Sem esta linha, viewport_get_measured_render_time_* devolve 0: a medição por viewport é
	# opcional justamente porque custa uma consulta ao driver por quadro.
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_last_frame_tick_usec = Time.get_ticks_usec()
	_build_font()
	_style_panel()
	_build_rows()
	# O tamanho do Anchor só existe depois da primeira passada de layout; sem o deferred, o painel
	# nasceria fora da tela nos cantos inferior e direito.
	_apply_corner.call_deferred()


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _last_frame_tick_usec) / 1000.0
	_last_frame_tick_usec = now_usec
	# Tempo de CPU ocupado neste quadro: física + processamento da árvore, medidos contra o
	# FrameClock, mais o custo de CPU de submeter o desenho. O que sobra até frame_ms é folga —
	# espera de vsync ou de GPU.
	var cpu_ms: float = float(now_usec - _frame_clock.process_started_usec + _physics_span_usec) / 1000.0 \
		+ RenderingServer.get_frame_setup_time_cpu() \
		+ RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
	_physics_span_usec = 0
	_collect_samples(frame_ms, cpu_ms)
	# Tempo de parede, não `delta`: o toggle de câmera lenta do menu escala o delta e faria o OSD
	# atualizar 4x mais devagar justamente quando alguém está olhando para ele.
	_elapsed_seconds += frame_ms / 1000.0
	if _elapsed_seconds < refresh_interval_seconds:
		return
	_elapsed_seconds = 0.0
	_refresh_display()


# Fecha o passo de física somando quanto a árvore inteira levou nele. Acumula porque um quadro pode
# conter vários passos de física (ou nenhum), e todos eles custam CPU dentro do mesmo quadro.
func _physics_process(_delta: float) -> void:
	_physics_span_usec += Time.get_ticks_usec() - _frame_clock.physics_started_usec


# Desliga a medição de tempo de render ao sair da árvore. Ela custa uma consulta ao driver por
# quadro e não pode sobreviver ao overlay que a pediu.
func _exit_tree() -> void:
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


# Move o painel para um dos quatro cantos. Público porque quem decide o canto é o DebugMenu, que
# guarda a preferência mesmo enquanto o overlay não existe.
#
# O guard de is_node_ready() cobre quem chama isto no mesmo passo em que adicionou o overlay à
# árvore: dependendo do contexto, o _ready() ainda não rodou e os @onready ainda são null.
func set_corner(corner: int) -> void:
	_corner = corner as PanelCorner
	if is_node_ready():
		_apply_corner()


# Liga/desliga os mini-gráficos. Com eles desligados o painel encolhe para só os números, que é o
# modo mais próximo do OSD padrão do RivaTuner.
func set_graphs_visible(value: bool) -> void:
	show_graphs = value
	# Antes do _ready() não há linha nenhuma para esconder — _build_rows() já nasce com a
	# visibilidade certa, porque lê show_graphs.
	if not is_node_ready():
		return
	for row: MetricRow in _rows.values():
		row.graph.visible = value
	_apply_corner()


# Empurra as métricas medidas diretamente nos seus históricos. Roda todo quadro de propósito:
# amostrar só a cada refresh perderia o pico de um quadro isolado, que costuma ser exatamente o que
# se está caçando.
func _collect_samples(frame_ms: float, cpu_ms: float) -> void:
	_push_sample(Metric.FRAME_MS, frame_ms)
	_push_sample(Metric.CPU_MS, cpu_ms)
	_push_sample(Metric.GPU_MS, RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
	_push_sample(Metric.RAM_MB, float(OS.get_static_memory_usage()) / BYTES_PER_MEGABYTE)


# Guarda uma amostra no acumulador do texto e no histórico do gráfico.
func _push_sample(metric: Metric, value: float) -> void:
	var row: MetricRow = _rows[metric]
	row.accumulator += value
	row.sample_count += 1
	if value > 0.0:
		row.has_reading = true
	_append_graph_sample(row, value)


# Empurra um ponto no gráfico, descartando o mais antigo. O descarte pela frente é um memmove de
# poucas centenas de bytes — barato o bastante para não justificar a complexidade de um buffer
# circular com índice de escrita.
func _append_graph_sample(row: MetricRow, value: float) -> void:
	row.graph.samples.append(value)
	if row.graph.samples.size() > row.graph.capacity:
		row.graph.samples.remove_at(0)


# Fecha a janela de amostras, deriva as linhas de uso e reescreve o painel.
func _refresh_display() -> void:
	for row: MetricRow in _rows.values():
		if not row.derived:
			_consume_average(row)
	_derive_usage_rows()
	for row: MetricRow in _rows.values():
		_paint_row(row)
	_update_header()
	# Reposiciona a cada refresh, e não só ao trocar de canto: a janela pode ser redimensionada a
	# qualquer momento e a altura do painel muda quando os gráficos são ligados/desligados.
	_apply_corner()


# Guarda a média das amostras do intervalo e zera o acumulador para a próxima janela.
func _consume_average(row: MetricRow) -> void:
	row.last_average = row.accumulator / float(maxi(row.sample_count, 1))
	row.accumulator = 0.0
	row.sample_count = 0


# Calcula a ocupação de CPU/GPU dentro do orçamento do quadro, a partir das médias já fechadas.
#
# A razão é feita entre as médias, e não quadro a quadro: calculada por quadro e depois promediada,
# ela infla — quadro curto leva a razão ao teto de 100% e puxa a média para cima. Medindo num teste
# de 3,6 s, a mesma carga aparecia como 55% pelo caminho errado e 18% pela razão entre as médias.
func _derive_usage_rows() -> void:
	var frame_ms: float = maxf(_rows[Metric.FRAME_MS].last_average, 0.001)
	_set_derived_value(Metric.CPU_PERCENT, _rows[Metric.CPU_MS], frame_ms)
	_set_derived_value(Metric.GPU_PERCENT, _rows[Metric.GPU_MS], frame_ms)


# Escreve o valor de uma linha derivada. A disponibilidade vem da linha de origem: uma ocupação de
# 0% é um valor legítimo, então a linha derivada não pode decidir sozinha se já tem leitura.
func _set_derived_value(metric: Metric, source: MetricRow, frame_ms: float) -> void:
	var row: MetricRow = _rows[metric]
	row.has_reading = source.has_reading
	row.last_average = clampf(source.last_average / frame_ms * 100.0, 0.0, 100.0)
	_append_graph_sample(row, row.last_average)


# Pinta valor e gráfico da linha com a cor do limite atingido.
func _paint_row(row: MetricRow) -> void:
	var color: Color = _color_for(row, row.last_average) if row.has_reading else color_unavailable
	row.value_label.text = row.value_format % row.last_average if row.has_reading else NO_READING_TEXT
	row.value_label.add_theme_color_override(&"font_color", color)
	row.graph.line_color = color
	if row.graph.visible:
		row.graph.queue_redraw()


# Mostra o FPS derivado do tempo de quadro medido aqui, e não de Engine.get_frames_per_second():
# são dois contadores com suavizações diferentes, e ver "60 FPS" ao lado de "20,00 ms" na mesma
# linha destruiria a confiança no painel inteiro.
func _update_header() -> void:
	var frame_row: MetricRow = _rows[Metric.FRAME_MS]
	var fps: float = 1000.0 / maxf(frame_row.last_average, 0.001)
	_fps_label.text = "%d FPS" % roundi(fps)
	_fps_label.add_theme_color_override(&"font_color", _color_for(frame_row, frame_row.last_average))


# Traduz o valor atual em cor: verde dentro do orçamento, amarelo no limite, vermelho acima. É o
# que permite ler o OSD de canto de olho, sem interpretar número nenhum.
func _color_for(row: MetricRow, value: float) -> Color:
	if value >= row.critical_threshold:
		return color_critical
	return color_warning if value >= row.warning_threshold else color_normal


# Monta as linhas na ordem em que aparecem na tela. Rótulos curtos porque o painel é estreito de
# propósito: um OSD que cobre o jogo deixa de ser um OSD.
func _build_rows() -> void:
	_add_row(Metric.FRAME_MS, "Quadro", "ms", 2, frame_budget_ms, frame_critical_ms, frame_critical_ms)
	_add_row(Metric.CPU_MS, "Quadro CPU", "ms", 2, frame_budget_ms, frame_critical_ms, TIME_GRAPH_FLOOR_MS)
	_add_row(Metric.GPU_MS, "Quadro GPU", "ms", 2, frame_budget_ms, frame_critical_ms, TIME_GRAPH_FLOOR_MS)
	_add_row(Metric.RAM_MB, "RAM", "MB", 0, ram_budget_mb, ram_critical_mb, ram_budget_mb)
	_add_row(Metric.CPU_PERCENT, "Uso CPU", "%", 0, usage_warning_percent, usage_critical_percent, 100.0)
	_add_row(Metric.GPU_PERCENT, "Uso GPU", "%", 0, usage_warning_percent, usage_critical_percent, 100.0)
	_mark_as_derived(Metric.CPU_PERCENT)
	_mark_as_derived(Metric.GPU_PERCENT)


# Marca a linha como calculada no refresh. O gráfico dela guarda menos pontos porque ganha um ponto
# por intervalo, e não por quadro: com a mesma capacidade das outras, o histórico levaria minutos
# para encher.
func _mark_as_derived(metric: Metric) -> void:
	var row: MetricRow = _rows[metric]
	row.derived = true
	row.graph.capacity = USAGE_SAMPLE_CAPACITY


# Cria os quatro nós de uma linha (nome, valor, unidade, gráfico) e registra a linha em _rows.
func _add_row(
	metric: Metric,
	name_text: String,
	unit_text: String,
	decimals: int,
	warning_threshold: float,
	critical_threshold: float,
	graph_scale_floor: float
) -> void:
	var char_width: float = float(font_size) * MONO_CHAR_RATIO
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 4)

	var row: MetricRow = MetricRow.new()
	row.value_format = "%%.%df" % decimals
	row.warning_threshold = warning_threshold
	row.critical_threshold = critical_threshold
	row.name_label = _make_label(name_text, HORIZONTAL_ALIGNMENT_LEFT, NAME_COLUMN_CHARS * char_width, color_label)
	# Alinhado à direita para as casas decimais ficarem na mesma coluna em todas as linhas.
	row.value_label = _make_label(NO_READING_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_COLUMN_CHARS * char_width, color_unavailable)
	row.unit_label = _make_label(unit_text, HORIZONTAL_ALIGNMENT_LEFT, UNIT_COLUMN_CHARS * char_width, color_label)

	row.graph = Sparkline.new()
	row.graph.capacity = SAMPLE_CAPACITY
	row.graph.scale_floor = graph_scale_floor
	row.graph.visible = show_graphs
	row.graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.graph.custom_minimum_size = Vector2(0.0, graph_height)
	row.graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.graph.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	line.add_child(row.name_label)
	line.add_child(row.value_label)
	line.add_child(row.unit_label)
	line.add_child(row.graph)
	_rows_container.add_child(line)
	_rows[metric] = row


# Cria um rótulo do OSD já com fonte monoespaçada, largura de coluna e cor aplicadas.
func _make_label(text: String, alignment: HorizontalAlignment, min_width: float, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.custom_minimum_size.x = min_width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _mono_font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


# Carrega a fonte monoespaçada e aplica no cabeçalho. Sem largura fixa de caractere os dígitos
# mudam de tamanho a cada atualização e o número "pula" na tela — é o detalhe que separa um OSD
# legível de um borrão piscando.
func _build_font() -> void:
	_mono_font = SystemFont.new()
	_mono_font.font_names = PackedStringArray(MONO_FONT_NAMES)
	for label: Label in [_title_label, _fps_label]:
		label.add_theme_font_override(&"font", _mono_font)
		label.add_theme_font_size_override(&"font_size", font_size)
	_title_label.add_theme_color_override(&"font_color", color_label)


# Dá ao painel o fundo escuro translúcido do OSD do Afterburner: escuro o bastante para o texto ser
# legível sobre qualquer cena, translúcido o bastante para não esconder o que está atrás.
func _style_panel() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	_panel.add_theme_stylebox_override(&"panel", style)


# Encosta o painel no canto atual, respeitando screen_margin. A altura vem do conteúdo, então é
# recalculada aqui em vez de ficar fixa na cena.
func _apply_corner() -> void:
	var area: Vector2 = _anchor.size
	_panel.size = Vector2(panel_width, _panel.get_combined_minimum_size().y)
	var on_left: bool = _corner == PanelCorner.TOP_LEFT or _corner == PanelCorner.BOTTOM_LEFT
	var on_top: bool = _corner == PanelCorner.TOP_LEFT or _corner == PanelCorner.TOP_RIGHT
	_panel.position = Vector2(
		screen_margin if on_left else area.x - _panel.size.x - screen_margin,
		screen_margin if on_top else area.y - _panel.size.y - screen_margin
	)
