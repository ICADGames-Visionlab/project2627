# DebugLogOverlay.gd — Visualizador do log dentro do próprio jogo: print(), push_warning(),
# push_error() e os erros da engine, sem alternar para o terminal (ou sem terminal nenhum, que é o
# caso de uma build rodando num playtest).
#
# De onde vêm as linhas: do arquivo de log que a própria engine escreve
# (debug/file_logging/log_path, por padrão user://logs/godot.log). O GDScript não tem gancho para
# interceptar print(), e um wrapper do tipo DebugLog.info() só enxergaria o que o NOSSO código
# escreve — justamente o contrário do que se quer aqui, porque o mais valioso de ver é o erro
# vermelho da engine que passou despercebido. Ler o arquivo pega tudo, inclusive o que aconteceu
# antes de o overlay abrir.
#
# O painel só lê e desenha: quem liga, desliga e guarda as preferências é o DebugLogViewer.
#
# Os textos deste painel são intencionalmente hardcoded: a exigência de tr() do Guideline vale
# para texto exibido ao jogador, e este overlay não existe em build de release.
extends CanvasLayer

# Gravidade de uma linha. A ordem importa: o "nível mínimo" do menu é um índice deste enum, então
# filtrar é comparar números (ver _matches_filters()).
enum Level {
	INFO,
	WARNING,
	ERROR,
}

const LOG_PATH_SETTING: String = "debug/file_logging/log_path"
const LOG_ENABLED_SETTING: String = "debug/file_logging/enable_file_logging"
const DEFAULT_LOG_PATH: String = "user://logs/godot.log"
# Prefixos com que a engine marca a gravidade no arquivo. Os "USER ..." são os que saem de
# push_error()/push_warning() do GDScript; o resto vem da própria engine e do compilador.
const ERROR_PREFIXES: PackedStringArray = [
	"ERROR:", "USER ERROR:", "SCRIPT ERROR:", "USER SCRIPT ERROR:", "SHADER ERROR:", "USER SHADER ERROR:"
]
const WARNING_PREFIXES: PackedStringArray = [
	"WARNING:", "USER WARNING:", "SCRIPT WARNING:", "USER SCRIPT WARNING:", "SHADER WARNING:"
]
# Rastro de um erro ("   at: _ready (res://Player.gd:12)"). Herda o nível da linha anterior, senão
# a parte mais útil de um erro apareceria como linha neutra solta e sumiria no filtro "Erros".
const CONTINUATION_PREFIX: String = "at:"
# Altura mínima do painel em janelas baixas, para ele nunca virar uma faixa ilegível.
const MIN_PANEL_HEIGHT: float = 120.0

@export_group("Layout")
@export var panel_width: float = 640.0
@export var panel_height: float = 300.0
@export var screen_margin: float = 8.0
# Faixa reservada no rodapé para o console (F1), que mora ancorado ali. Sem isto, os dois painéis
# se sobrepõem justamente na combinação mais usada: ler o log enquanto se digita comandos.
@export var console_margin: float = 196.0
@export var font_size: int = 12
# Intervalo entre leituras do arquivo. Nenhuma linha se perde entre uma leitura e outra (o arquivo
# guarda tudo), então espaçar aqui é de graça.
@export var refresh_interval_seconds: float = 0.25

@export_group("Limites")
# Linhas guardadas em memória. Acima disso as mais antigas caem — o arquivo continua completo no
# disco, então nada some de verdade.
@export var buffer_capacity: int = 2000
# Linhas efetivamente desenhadas. Separado da capacidade porque o custo de desenhar é do
# RichTextLabel, não do buffer: dá para guardar muito e mostrar pouco.
@export var visible_lines: int = 400

@export_group("Cores")
@export var color_info: Color = Color("c8d3de")
@export var color_warning: Color = Color("ffd23f")
@export var color_error: Color = Color("ff5a5a")
@export var color_header: Color = Color("9fb2c4")
@export var panel_color: Color = Color(0.03, 0.04, 0.06, 0.86)
@export var panel_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)

# As três listas são paralelas e só são mexidas por _append_line() e clear_view(): texto exibido,
# gravidade e o mesmo texto normalizado, guardado uma vez para o filtro não precisar normalizar
# duas mil linhas a cada atualização.
var _line_texts: PackedStringArray = PackedStringArray()
var _line_levels: PackedInt32Array = PackedInt32Array()
var _line_search: PackedStringArray = PackedStringArray()

var _log_path: String = DEFAULT_LOG_PATH
# Byte a partir do qual a próxima leitura começa.
var _read_position: int = 0
# Sobra da última leitura: a linha que ainda não terminou em quebra de linha. Guardar em vez de
# exibir evita mostrar meia linha e depois repeti-la inteira.
var _pending_text: String = ""
# Gravidade da última linha completa, usada pelas linhas de continuação para herdar o nível.
var _last_level: int = Level.INFO

var _min_level: int = Level.INFO
var _text_filter: String = ""
var _text_needle: String = ""
var _following: bool = true
# Linhas que chegaram com o painel pausado, mostradas no cabeçalho.
var _paused_count: int = 0
var _visible_count: int = 0
# Marca que chegou linha nova desde o último desenho. É um sinalizador, e não uma comparação de
# tamanho do buffer: com o buffer cheio, cada linha nova empurra uma velha para fora e o tamanho
# fica parado em buffer_capacity — o painel congelaria exatamente na sessão mais barulhenta.
var _dirty: bool = false
# Motivo de o painel estar vazio quando o arquivo de log não pode ser lido. Vazio quando está tudo
# bem.
var _status_message: String = ""
# Relógio de parede, e não `delta`: o toggle de câmera lenta do menu escala o delta e faria o
# painel atualizar 4x mais devagar justamente durante uma investigação.
var _last_refresh_msec: int = 0

@onready var _anchor: Control = $Anchor
@onready var _panel: PanelContainer = $Anchor/Panel
@onready var _header: Label = $Anchor/Panel/Margin/Layout/Header
@onready var _output: RichTextLabel = $Anchor/Panel/Margin/Layout/Output


func _ready() -> void:
	# Sem isto, o painel congela junto com o jogo assim que "Pausar jogo" é ligado — e ler o log é
	# exatamente o que se quer fazer com o jogo parado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Entra no grupo dos overlays de debug para a captura de tela (F6) poder escondê-lo sem
	# conhecer esta cena (ver DebugScreenCapture).
	add_to_group(DebugMenu.OVERLAY_GROUP)
	_log_path = String(ProjectSettings.get_setting(LOG_PATH_SETTING, DEFAULT_LOG_PATH))
	_style_panel()
	_style_text()
	_read_log_file()
	_rebuild_output()
	_update_header()
	# O tamanho do Anchor só existe depois da primeira passada de layout; sem o deferred, o painel
	# nasceria posicionado fora da tela.
	_apply_placement.call_deferred()


func _process(_delta: float) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_refresh_msec < roundi(refresh_interval_seconds * 1000.0):
		return
	_last_refresh_msec = now_msec
	_read_log_file()
	if _following and _dirty:
		_rebuild_output()
	_update_header()
	# Reposiciona a cada atualização porque a janela pode ser redimensionada a qualquer momento —
	# inclusive pelo testador de proporção da seção "Tela".
	_apply_placement()


# Define o nível mínimo exibido (índice de Level). Público porque quem guarda a preferência é o
# DebugLogViewer: ela precisa sobreviver ao painel ser liberado e recriado.
func set_min_level(level: int) -> void:
	_min_level = clampi(level, Level.INFO, Level.ERROR)
	if not is_node_ready():
		return
	_rebuild_output()
	_update_header()


# Define o filtro de texto. Guarda o texto original (para o cabeçalho) e a versão normalizada, que
# é contra a qual as linhas são comparadas — o mesmo casamento sem acento e sem diferenciar
# maiúsculas do filtro do menu.
func set_text_filter(text: String) -> void:
	_text_filter = text.strip_edges()
	_text_needle = DebugTextFilter.normalize(_text_filter)
	if not is_node_ready():
		return
	_rebuild_output()
	_update_header()


# Liga/desliga o acompanhamento do fim do log. Pausado, o painel para de se redesenhar (dá para
# ler e rolar em paz) mas continua guardando o que chega; religar mostra tudo de uma vez.
func set_following(value: bool) -> void:
	_following = value
	if not is_node_ready():
		return
	if _following:
		_rebuild_output()
	_update_header()


# Esvazia o painel. Não toca no arquivo de log: "limpar" aqui é marcar um novo começo para a
# leitura, e reabrir o overlay traz o histórico inteiro de volta.
func clear_view() -> void:
	_line_texts = PackedStringArray()
	_line_levels = PackedInt32Array()
	_line_search = PackedStringArray()
	_paused_count = 0
	_rebuild_output()
	_update_header()


# Devolve, em texto puro, todas as linhas que passam pelos filtros atuais — não só as desenhadas.
# Quem copia para um report de bug quer o recorte inteiro, não a última tela dele.
func get_visible_text() -> String:
	var matched: PackedStringArray = PackedStringArray()
	for index: int in _line_texts.size():
		if _matches_filters(index):
			matched.append(_line_texts[index])
	return "\n".join(matched)


# Lê o que foi acrescentado ao arquivo de log desde a última passada.
#
# O arquivo é reaberto a cada leitura em vez de manter um handle aberto: quem escreve é a própria
# engine, por outro handle do mesmo processo, e reabrir é a forma barata de garantir que o tamanho
# lido é o atual. O arquivo é pequeno e a leitura acontece 4x por segundo.
func _read_log_file() -> void:
	var file: FileAccess = FileAccess.open(_log_path, FileAccess.READ)
	if file == null:
		_status_message = _unavailable_message()
		return
	_status_message = ""
	var length: int = file.get_length()
	if length < _read_position:
		# Arquivo rotacionado ou truncado no meio da sessão: recomeça em vez de ler lixo.
		_read_position = 0
		_pending_text = ""
	if length == _read_position:
		return
	file.seek(_read_position)
	var chunk: PackedByteArray = file.get_buffer(length - _read_position)
	_read_position = length
	var text: String = _pending_text + chunk.get_string_from_utf8()
	var parts: PackedStringArray = text.split("\n")
	# O último pedaço é sempre a sobra: string vazia quando o texto terminou em quebra de linha.
	_pending_text = parts[parts.size() - 1]
	for index: int in parts.size() - 1:
		_append_line(parts[index].trim_suffix("\r"))


# Guarda uma linha completa nas três listas paralelas, descartando a mais antiga quando o buffer
# enche.
func _append_line(line: String) -> void:
	_line_texts.append(line)
	_line_levels.append(_classify(line))
	_line_search.append(DebugTextFilter.normalize(line))
	if _line_texts.size() > buffer_capacity:
		_line_texts.remove_at(0)
		_line_levels.remove_at(0)
		_line_search.remove_at(0)
	_dirty = true
	if not _following:
		_paused_count += 1


# Deduz a gravidade da linha pelo prefixo que a engine escreveu. Linha indentada ou começada por
# "at:" é continuação do erro anterior e herda o nível dele.
func _classify(line: String) -> int:
	var trimmed: String = line.strip_edges()
	if trimmed.is_empty():
		return _last_level
	if line.begins_with(" ") or line.begins_with("\t") or trimmed.begins_with(CONTINUATION_PREFIX):
		return _last_level
	for prefix: String in ERROR_PREFIXES:
		if trimmed.begins_with(prefix):
			_last_level = Level.ERROR
			return _last_level
	for prefix: String in WARNING_PREFIXES:
		if trimmed.begins_with(prefix):
			_last_level = Level.WARNING
			return _last_level
	_last_level = Level.INFO
	return _last_level


# Uma linha passa quando é grave o bastante E casa com o filtro de texto.
func _matches_filters(index: int) -> bool:
	if _line_levels[index] < _min_level:
		return false
	if _text_needle.is_empty():
		return true
	return _line_search[index].contains(_text_needle)


# Remonta o texto do painel a partir do buffer. Roda inteiro a cada atualização (e não de forma
# incremental) porque trocar de filtro ou de nível muda o passado, não só o que chega depois.
func _rebuild_output() -> void:
	if not _status_message.is_empty():
		_output.text = _colorize(_status_message, color_warning)
		_visible_count = 0
		return
	var matched: PackedStringArray = PackedStringArray()
	for index: int in _line_texts.size():
		if _matches_filters(index):
			matched.append(_colorize(_line_texts[index], _color_for(_line_levels[index])))
	_visible_count = matched.size()
	if matched.size() > visible_lines:
		matched = matched.slice(matched.size() - visible_lines)
	_output.text = "\n".join(matched)
	_paused_count = 0
	_dirty = false


# Envelopa a linha na cor do nível dela, neutralizando os colchetes do texto: o painel usa BBCode
# para colorir, e os prints do projeto começam justamente com "[Area] - ...", que o RichTextLabel
# tentaria ler como tag.
func _colorize(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]


# Cor da linha por nível. Info fica num cinza claro de propósito: se toda linha fosse colorida, a
# cor pararia de significar alguma coisa.
func _color_for(level: int) -> Color:
	match level:
		Level.ERROR:
			return color_error
		Level.WARNING:
			return color_warning
	return color_info


# Cabeçalho com o que está sendo mostrado e por quê: sem ele, um painel filtrado parece um painel
# vazio.
func _update_header() -> void:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("LOG")
	parts.append("%d de %d linhas" % [_visible_count, _line_texts.size()])
	if _min_level > Level.INFO:
		parts.append("nível: %s" % DebugLogViewer.LEVEL_NAMES[_min_level])
	if not _text_filter.is_empty():
		parts.append("filtro: \"%s\"" % _text_filter)
	if not _following:
		parts.append("PAUSADO (%d novas)" % _paused_count)
	_header.text = "  ·  ".join(parts)


# Explica por que o painel está vazio quando o arquivo de log não abre. O log em arquivo vem
# ligado por padrão em desktop, então o caso comum é alguém ter desligado a opção no projeto.
func _unavailable_message() -> String:
	var enabled: bool = bool(ProjectSettings.get_setting_with_override(LOG_ENABLED_SETTING))
	if not enabled:
		return "O log em arquivo está desligado (%s). Ligue essa opção nas configurações do projeto para o painel ter o que mostrar." % LOG_ENABLED_SETTING
	return "Não foi possível abrir o arquivo de log em %s." % _log_path


# Encosta o painel no canto inferior esquerdo, acima da faixa do console, encolhendo se a janela
# for baixa ou estreita demais para o tamanho pedido.
func _apply_placement() -> void:
	var area: Vector2 = _anchor.size
	var width: float = minf(panel_width, maxf(area.x - screen_margin * 2.0, MIN_PANEL_HEIGHT))
	var available_height: float = area.y - console_margin - screen_margin
	var height: float = clampf(panel_height, MIN_PANEL_HEIGHT, maxf(available_height, MIN_PANEL_HEIGHT))
	_panel.size = Vector2(width, height)
	_panel.position = Vector2(screen_margin, maxf(area.y - height - console_margin, screen_margin))


# Fundo escuro translúcido, igual ao do painel de desempenho: escuro o bastante para o texto ser
# legível sobre qualquer cena, translúcido o bastante para não esconder o que está atrás.
func _style_panel() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	_panel.add_theme_stylebox_override(&"panel", style)


# Aplica a fonte monoespaçada do debug no cabeçalho e no corpo. Log é texto alinhado por coluna
# (caminhos, números, prefixos de área), e fonte proporcional embaralha isso.
func _style_text() -> void:
	var mono_font: SystemFont = DebugFonts.mono()
	_header.add_theme_font_override(&"font", mono_font)
	_header.add_theme_font_size_override(&"font_size", font_size)
	_header.add_theme_color_override(&"font_color", color_header)
	_output.add_theme_font_override(&"normal_font", mono_font)
	_output.add_theme_font_size_override(&"normal_font_size", font_size)
