# EventBusLogger.gd — Instrumentação dos eventos do bus. Existe apenas em build de debug/editor.
# Motivação: a maior objeção ao padrão Event Bus é a dificuldade de depuração; a resposta do
# projeto é instrumentar, não abandonar o padrão.
#
# Mecanismo: GDScript não tem callbacks variádicas, então existe um handler por aridade e o nome
# do evento chega por Callable.bind() — argumentos ligados vêm DEPOIS dos do sinal.
# A varredura usa Script.get_script_signal_list(), que devolve só os sinais declarados no
# EventBus.gd (get_signal_list() traria também ready, renamed, tree_entered etc.).
class_name EventBusLogger
extends Node

# Aridade máxima instrumentada: acima disso, o evento deveria usar uma classe de payload.
const MAX_TRACKED_ARITY: int = 4
const HISTORY_SIZE: int = 256
const REQUEST_SUFFIX: String = "_requested"
const TOGGLE_ACTION: StringName = &"debug_toggle_event_bus"
const OVERLAY_SCENE_PATH: String = "res://scenes/debugs/EventBusOverlay.tscn"
const HANDLER_REFRESH_INTERVAL_FRAMES: int = 60

# Limiares de alerta exportados para permitir calibragem pelo Inspetor sem tocar no código.
@export var same_frame_repeat_threshold: int = 8
@export var max_cascade_depth: int = 2
@export var warn_on_zero_listeners: bool = true
# Log de toda emissão: muito verboso, ligar sob demanda durante uma investigação.
@export var log_every_emission: bool = false
# Rastreio de profundidade de cascata via get_stack(): caro, ligar só em auditoria.
@export var deep_trace: bool = false

# Array de EventRecord. Sem tipo de elemento porque a tipagem de Array com classe interna
# não é confiável em todas as versões da engine.
var _history: Array = []
var _history_head: int = 0
var _history_count: int = 0

var _bus: Node
var _signals: Dictionary = {}              # StringName(evento) -> SignalInfo
var _total_by_event: Dictionary = {}       # StringName(evento) -> int
var _repeat_frame: Dictionary = {}         # StringName(evento) -> int
var _repeat_count: Dictionary = {}         # StringName(evento) -> int
var _silent_events: Dictionary = {}        # StringName(evento) -> true
var _handler_ids: Dictionary = {}          # "script::method" -> true, usado pelo deep_trace

var _current_frame: int = -1
var _frame_emissions: int = 0
var _last_frame_emissions: int = 0
var _overlay: CanvasLayer


# Registro de uma emissão, guardado no histórico circular exibido pelo overlay de debug.
class EventRecord:
	var event_name: StringName = &""
	var frame: int = 0
	var msec: int = 0
	var listeners: int = 0
	var payload_text: String = ""


# Metadados de um sinal instrumentado, resolvidos uma vez no attach para evitar
# custo de lookup a cada emissão.
class SignalInfo:
	var event_name: StringName = &""
	var is_request: bool = false
	# Quantas conexões pertencem ao próprio logger e precisam ser descontadas da contagem.
	var probe_count: int = 1
	# Argumentos do sinal (name + type), na ordem declarada. Guardado aqui para
	# _register_event_actions() não precisar varrer get_script_signal_list() de novo.
	var args: Array[Dictionary] = []


func _ready() -> void:
	_history.resize(HISTORY_SIZE)
	for index: int in HISTORY_SIZE:
		_history[index] = EventRecord.new()
	_register_performance_monitors()


func _exit_tree() -> void:
	_remove_performance_monitors()


func _unhandled_key_input(event: InputEvent) -> void:
	if _is_toggle_pressed(event):
		_toggle_overlay()
		get_viewport().set_input_as_handled()


# Conecta um handler de log a cada sinal declarado no EventBus.
# Chamado uma única vez pelo próprio bus, no _ready().
func attach_to_bus(bus: Node) -> void:
	_bus = bus
	var script: Script = bus.get_script() as Script
	if script == null:
		push_warning("[EventBus] - Bus sem script; instrumentação desligada")
		return
	for signal_data: Dictionary in script.get_script_signal_list():
		_attach_signal(signal_data)
	print("[EventBus] - Instrumentação ativa em %d eventos" % _signals.size())
	# Adiado de propósito: o EventBus é o primeiro Autoload da lista e o DebugMenu ainda não
	# existe quando este _ready() roda. A chamada adiada cai no fim do frame, com todos os
	# Autoloads prontos — e é isso que também mantém "Sistema" como a primeira seção da lista.
	_register_event_actions.call_deferred()


# Conecta o handler da aridade correspondente e guarda os metadados do sinal.
func _attach_signal(signal_data: Dictionary) -> void:
	var event_name: StringName = signal_data["name"]
	var args: Array[Dictionary] = []
	for arg: Dictionary in (signal_data["args"] as Array):
		args.append(arg)
	var arity: int = args.size()
	if arity > MAX_TRACKED_ARITY:
		push_warning("[EventBus] - %s tem %d parâmetros; acima do limite instrumentável de %d"
			% [event_name, arity, MAX_TRACKED_ARITY])
		return

	var info: SignalInfo = SignalInfo.new()
	info.event_name = event_name
	info.is_request = String(event_name).ends_with(REQUEST_SUFFIX)
	info.args = args
	_signals[event_name] = info

	_bus.connect(event_name, Callable(self, "_on_event_%d" % arity).bind(event_name))


# Pendura uma ação de debug por evento declarado no bus. Os parâmetros saem dos tipos (e nomes)
# declarados no próprio signal, então eventos novos aparecem no menu e no console
# (eventos.emitir_<evento>) sem ninguém registrar nada — a mesma propriedade que esta
# instrumentação já tem.
func _register_event_actions() -> void:
	for event_name: StringName in _signals:
		var info: SignalInfo = _signals[event_name]
		var params: Array[DebugParam] = _params_from_signal(info.args)
		if params.size() != info.args.size():
			push_warning("[EventBus] - AVISO: %s tem parâmetro de tipo não suportado pelo Debug Menu (ex.: classe de payload); sem botão na seção \"Eventos\" — registre a ação manualmente" % event_name)
			continue
		DebugMenu.register_input(&"Eventos", "Emitir %s" % event_name,
			Callable(self, "_emit_event_%d" % params.size()).bind(event_name), params)


# Mapeia os argumentos declarados no sinal (nome + tipo) para DebugParam. Devolve um array mais
# curto que args assim que encontra um tipo não suportado — o chamador compara os tamanhos para
# detectar isso.
func _params_from_signal(args: Array[Dictionary]) -> Array[DebugParam]:
	var params: Array[DebugParam] = []
	for arg: Dictionary in args:
		var arg_name: String = String(arg["name"])
		match int(arg["type"]):
			TYPE_INT:
				params.append(DebugParam.int_value(arg_name, 0))
			TYPE_FLOAT:
				params.append(DebugParam.float_value(arg_name, 0.0))
			TYPE_STRING, TYPE_STRING_NAME:
				params.append(DebugParam.string_value(arg_name))
			TYPE_BOOL:
				params.append(DebugParam.bool_value(arg_name))
			_:
				return params
	return params


# Handlers de log, um por aridade: GDScript não tem callback variádica, então _attach_signal()
# escolhe o handler pelo número de parâmetros do sinal. O nome do evento chega por
# Callable.bind() e por isso é sempre o ÚLTIMO parâmetro, depois dos argumentos do sinal.
# Cada handler só formata o payload para leitura humana; a contabilidade toda vive em _record().

# Handler de eventos sem parâmetro.
func _on_event_0(event_name: StringName) -> void:
	_record(event_name, "")


# Handler de eventos com um parâmetro.
func _on_event_1(a0: Variant, event_name: StringName) -> void:
	_record(event_name, str(a0))


# Handler de eventos com dois parâmetros.
func _on_event_2(a0: Variant, a1: Variant, event_name: StringName) -> void:
	_record(event_name, "%s, %s" % [a0, a1])


# Handler de eventos com três parâmetros.
func _on_event_3(a0: Variant, a1: Variant, a2: Variant, event_name: StringName) -> void:
	_record(event_name, "%s, %s, %s" % [a0, a1, a2])


# Handler de eventos com quatro parâmetros — a maior aridade instrumentada
# (ver MAX_TRACKED_ARITY). Acima disso o evento deve usar uma classe de payload.
func _on_event_4(a0: Variant, a1: Variant, a2: Variant, a3: Variant, event_name: StringName) -> void:
	_record(event_name, "%s, %s, %s, %s" % [a0, a1, a2, a3])


# Handlers de emissão manual, um por aridade — imagem espelhada de _on_event_0..4 pelo mesmo
# motivo: GDScript não tem callable variádica. Ligados por _register_event_actions() via
# Callable(self, "_emit_event_N").bind(event_name), então o nome do evento chega por bind() e é
# sempre o ÚLTIMO parâmetro, como nos handlers de log.

func _emit_event_0(event_name: StringName) -> void:
	_bus.emit_signal(event_name)


func _emit_event_1(a0: Variant, event_name: StringName) -> void:
	_bus.emit_signal(event_name, a0)


func _emit_event_2(a0: Variant, a1: Variant, event_name: StringName) -> void:
	_bus.emit_signal(event_name, a0, a1)


func _emit_event_3(a0: Variant, a1: Variant, a2: Variant, event_name: StringName) -> void:
	_bus.emit_signal(event_name, a0, a1, a2)


func _emit_event_4(a0: Variant, a1: Variant, a2: Variant, a3: Variant, event_name: StringName) -> void:
	_bus.emit_signal(event_name, a0, a1, a2, a3)


# Registra a emissão, atualiza contadores e dispara os alertas de fiação.
# O logger é ele próprio um listener, por isso a contagem desconta a conexão de sondagem.
func _record(event_name: StringName, payload_text: String) -> void:
	var info: SignalInfo = _signals[event_name]
	var listeners: int = _bus.get_signal_connection_list(event_name).size() - info.probe_count

	_track_frame()
	_frame_emissions += 1
	_total_by_event[event_name] = int(_total_by_event.get(event_name, 0)) + 1
	_push_history(event_name, listeners, payload_text)

	if log_every_emission:
		print("[EventBus] - %s → %d listeners %s" % [event_name, listeners, payload_text])

	if listeners == 0:
		# O aviso sai uma única vez por evento: push_warning imprime backtrace inteiro e um
		# evento órfão emitido em laço afogaria o console. A lista completa continua
		# disponível em get_silent_events() e no overlay.
		if warn_on_zero_listeners and not _silent_events.has(event_name):
			push_warning("[EventBus] - AVISO: %s emitido sem nenhum listener conectado" % event_name)
		_silent_events[event_name] = true

	if info.is_request and listeners != 1:
		push_error("[EventBus] - ERRO: pedido %s tem %d listeners (esperado exatamente 1)"
			% [event_name, listeners])

	if _count_repeat(event_name) == same_frame_repeat_threshold:
		push_warning("[EventBus] - AVISO: %s emitido %d vezes no frame %d (possível laço)"
			% [event_name, same_frame_repeat_threshold, _current_frame])

	if deep_trace:
		var depth: int = _measure_cascade_depth()
		if depth > max_cascade_depth:
			push_warning("[EventBus] - AVISO: %s em cascata de profundidade %d (o limite é %d)"
				% [event_name, depth, max_cascade_depth])


# Detecta a virada de frame sem depender da ordem de _process entre logger e emissores:
# a referência é o contador de frames da engine, consultado no momento da emissão.
func _track_frame() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _current_frame:
		return
	_last_frame_emissions = _frame_emissions
	_frame_emissions = 0
	_current_frame = frame
	if deep_trace and frame % HANDLER_REFRESH_INTERVAL_FRAMES == 0:
		_refresh_handler_ids()


# Conta quantas vezes o evento já foi emitido dentro do frame corrente.
# A contagem reinicia sozinha na virada de frame, sem varredura periódica.
func _count_repeat(event_name: StringName) -> int:
	if int(_repeat_frame.get(event_name, -1)) != _current_frame:
		_repeat_frame[event_name] = _current_frame
		_repeat_count[event_name] = 0
	var count: int = int(_repeat_count[event_name]) + 1
	_repeat_count[event_name] = count
	return count


# Grava a emissão no histórico circular usado pelo overlay para reconstruir cascatas.
func _push_history(event_name: StringName, listeners: int, payload_text: String) -> void:
	var record: EventRecord = _history[_history_head]
	record.event_name = event_name
	record.frame = _current_frame
	record.msec = Time.get_ticks_msec()
	record.listeners = listeners
	record.payload_text = payload_text
	_history_head = (_history_head + 1) % HISTORY_SIZE
	_history_count = mini(_history_count + 1, HISTORY_SIZE)


# Mede a profundidade da cascata contando, na pilha de chamadas, quantos quadros pertencem a
# handlers conectados ao bus. Só funciona em build de debug e só roda com deep_trace ligado,
# porque get_stack() é caro o bastante para distorcer a medição que o logger existe para fazer.
func _measure_cascade_depth() -> int:
	var depth: int = 0
	for frame: Dictionary in get_stack():
		var id: String = "%s::%s" % [frame.get("source", ""), frame.get("function", "")]
		if _handler_ids.has(id):
			depth += 1
	return depth


# Reconstrói a tabela de handlers conhecidos usada pelo deep_trace.
# Roda no máximo uma vez por segundo porque varre a lista de conexões de todos os sinais.
func _refresh_handler_ids() -> void:
	_handler_ids.clear()
	for event_name: StringName in _signals:
		for connection: Dictionary in _bus.get_signal_connection_list(event_name):
			var callable: Callable = connection["callable"]
			var target: Object = callable.get_object()
			if target == null or target == self:
				continue
			var script: Script = target.get_script() as Script
			if script == null:
				continue
			_handler_ids["%s::%s" % [script.resource_path, callable.get_method()]] = true


# Devolve as últimas emissões em ordem cronológica, para exibição no overlay de debug.
func get_recent_history(count: int) -> Array:
	var wanted: int = mini(count, _history_count)
	var result: Array = []
	for offset: int in range(wanted, 0, -1):
		var index: int = (_history_head - offset + HISTORY_SIZE) % HISTORY_SIZE
		result.append(_history[index])
	return result


# Total acumulado de emissões por evento na sessão. Usado pelo overlay e pelas auditorias.
func get_total_by_event() -> Dictionary:
	return _total_by_event.duplicate()


# Eventos que já foram emitidos ao menos uma vez sem nenhum listener conectado.
# É a lista mais útil do overlay: quase sempre indica fiação esquecida.
func get_silent_events() -> Array:
	return _silent_events.keys()


# Quantidade de eventos instrumentados.
func get_tracked_event_count() -> int:
	return _signals.size()


# Quantas emissões ocorreram no frame anterior. É o anterior, e não o corrente, porque o frame
# em curso ainda está sendo contado quando o overlay ou o profiler perguntam.
func get_last_frame_emissions() -> int:
	return _last_frame_emissions


# Registra os contadores do bus no profiler da engine, na categoria "event_bus".
func _register_performance_monitors() -> void:
	if not Performance.has_custom_monitor(&"event_bus/emissions_per_frame"):
		Performance.add_custom_monitor(&"event_bus/emissions_per_frame", _monitor_emissions_per_frame)
	if not Performance.has_custom_monitor(&"event_bus/tracked_events"):
		Performance.add_custom_monitor(&"event_bus/tracked_events", _monitor_tracked_events)


# Remove os monitores ao sair da árvore para o editor não acumular monitores mortos
# entre execuções do jogo.
func _remove_performance_monitors() -> void:
	if Performance.has_custom_monitor(&"event_bus/emissions_per_frame"):
		Performance.remove_custom_monitor(&"event_bus/emissions_per_frame")
	if Performance.has_custom_monitor(&"event_bus/tracked_events"):
		Performance.remove_custom_monitor(&"event_bus/tracked_events")


# Alimenta o monitor "event_bus/emissions_per_frame" do profiler. A engine chama este Callable
# uma vez por frame, então ele só devolve valor pronto — nada de cálculo aqui dentro.
func _monitor_emissions_per_frame() -> int:
	return _last_frame_emissions


# Alimenta o monitor "event_bus/tracked_events" do profiler. Serve para flagrar no gráfico o
# momento em que um evento novo entra ou some da instrumentação.
func _monitor_tracked_events() -> int:
	return _signals.size()


# Aceita a ação de input configurada e, se ela não existir no projeto, cai para F3 direto.
# Isso evita que uma falha de configuração do Input Map deixe o overlay inacessível.
func _is_toggle_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(TOGGLE_ACTION):
		return event.is_action_pressed(TOGGLE_ACTION)
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3


# Cria o overlay na primeira vez que é pedido: enquanto ninguém aperta a tecla, ele não custa nada.
func _toggle_overlay() -> void:
	if _overlay == null:
		var scene: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[EventBus] - ERRO: overlay de debug não encontrado em %s" % OVERLAY_SCENE_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		add_child(_overlay)
		_overlay.call(&"attach_to_logger", self)
		print("[EventBus] - Overlay de debug aberto")
		return
	_overlay.visible = not _overlay.visible
	print("[EventBus] - Overlay de debug %s" % ("aberto" if _overlay.visible else "fechado"))
