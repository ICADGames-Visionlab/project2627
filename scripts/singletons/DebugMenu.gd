# DebugMenu.gd — Autoload: registro de ações de debug, teclas de atalho (F4 e F2) e instância das
# cenas de debug sob demanda. É "o lugar onde as ações vão ser penduradas" quando os sistemas de
# jogo existirem — hoje só as seções "Sistema" e "Desempenho" (registradas abaixo) usam o registro.
#
# Registrar não exige desregistrar: o Callable de um sistema descarregado é limpo sozinho na
# próxima abertura do menu (ver _purge_dead_entries()). O par (seção, rótulo) é a identidade de
# uma entrada — registrar de novo substitui em vez de duplicar, o que também cobre o caso de
# recarregar a cena.
#
# Em build de release, register_action()/register_toggle() retornam na primeira linha e o atalho
# de abrir o menu fica desligado: o autoload continua existindo (é um Node vazio), mas custa zero.
#
# O guia completo está em docs/debug_menu.md.
extends Node

const TOGGLE_ACTION: StringName = &"debug_toggle_menu"
const OVERLAY_SCENE_PATH: String = "res://scenes/debugs/DebugMenu.tscn"

const STATS_TOGGLE_ACTION: StringName = &"debug_toggle_stats"
const STATS_SCENE_PATH: String = "res://scenes/debugs/DebugStats.tscn"
const STATS_SECTION: StringName = &"Desempenho"
# O rótulo é a identidade da entrada no registro, então precisa ser constante: é por ele que
# _set_stats_enabled() reescreve o toggle com o estado real depois de um F2.
const STATS_TOGGLE_LABEL: String = "Overlay de desempenho (F2)"
const STATS_CORNER_NAMES: Array[String] = [
	"superior esquerdo", "superior direito", "inferior direito", "inferior esquerdo"
]

var _sections: Dictionary = {}   # StringName(seção) -> Array[DebugEntry], na ordem de registro
var _overlay: CanvasLayer
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _stats_overlay: CanvasLayer
var _stats_enabled: bool = false
var _stats_graphs_visible: bool = true
# Canto superior direito por padrão: o menu de debug ocupa o canto superior esquerdo, e os dois
# abertos ao mesmo tempo é o caso normal, não a exceção.
var _stats_corner: int = 1


# Uma entrada registrada: um botão (action) ou um interruptor com estado (toggle).
class DebugEntry:
	var section: StringName = &""
	var label: String = ""
	var callable: Callable
	var is_toggle: bool = false
	var toggle_state: bool = false


func _ready() -> void:
	# Sem isto, o menu para de responder assim que ele mesmo pausa o jogo (ver "Pausar jogo").
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_debug_build():
		return
	# [DEBUG] Seção "Sistema": ações de engine que não dependem de nenhum sistema de jogo,
	# registradas antes de qualquer cena, então ficam sempre em primeiro (ver docs/debug_menu.md).
	register_toggle(&"Sistema", "Pausar jogo", _on_pause_toggled)
	register_toggle(&"Sistema", "Câmera lenta (0.25x)", _on_slow_motion_toggled)
	register_action(&"Sistema", "Avançar 1 frame", _advance_one_frame)
	register_action(&"Sistema", "Recarregar cena", _reload_scene)
	register_action(&"Sistema", "Sair do jogo", _quit_game)
	# [DEBUG] Seção "Desempenho": controles do OSD de métricas (ver docs/debug_menu.md).
	register_toggle(STATS_SECTION, STATS_TOGGLE_LABEL, _on_stats_toggled, _stats_enabled)
	register_toggle(STATS_SECTION, "Gráficos das métricas", _on_stats_graphs_toggled, _stats_graphs_visible)
	register_action(STATS_SECTION, "Mover para o próximo canto", _cycle_stats_corner)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_debug_build():
		return
	if _is_shortcut_pressed(event, TOGGLE_ACTION, KEY_F4):
		_toggle_menu()
		get_viewport().set_input_as_handled()
	elif _is_shortcut_pressed(event, STATS_TOGGLE_ACTION, KEY_F2):
		_set_stats_enabled(not _stats_enabled)
		get_viewport().set_input_as_handled()


# Registra um botão que dispara uma ação imediata. Não faz nada em build de release.
func register_action(section: StringName, label: String, action: Callable) -> void:
	if not _is_debug_build():
		return
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = action
	entry.is_toggle = false
	_store_entry(entry)


# Registra um interruptor com estado visível no menu. O menu é dono do bool: guarda o valor e
# avisa a mudança via on_changed(novo_valor). Se o sistema alterar o valor por outro caminho, o
# menu desencontra até ser reaberto — ver docs/debug_menu.md. Não faz nada em build de release.
func register_toggle(section: StringName, label: String, on_changed: Callable, initial: bool = false) -> void:
	if not _is_debug_build():
		return
	var entry: DebugEntry = DebugEntry.new()
	entry.section = section
	entry.label = label
	entry.callable = on_changed
	entry.is_toggle = true
	entry.toggle_state = initial
	_store_entry(entry)


# Devolve o registro atual, já sem entradas cujo dono saiu da árvore. É a única leitura do
# registro (o overlay chama isto ao montar a UI), então a limpeza acontece de graça, sem exigir
# unregister() de ninguém.
func get_sections() -> Dictionary:
	_purge_dead_entries()
	return _sections


# Insere a entrada na seção, substituindo qualquer entrada anterior com o mesmo rótulo. É o que
# torna o registro idempotente quando a cena que registra recarrega.
func _store_entry(entry: DebugEntry) -> void:
	var entries: Array = _sections.get(entry.section, [])
	for index: int in entries.size():
		var existing: DebugEntry = entries[index]
		if existing.label == entry.label:
			entries[index] = entry
			return
	entries.append(entry)
	_sections[entry.section] = entries


# Remove entradas cujo Callable aponta para um nó já liberado (cena descarregada). Sem isto, o
# menu acumularia botões mortos toda vez que uma cena de jogo troca.
func _purge_dead_entries() -> void:
	for section: StringName in _sections.keys():
		var alive: Array = []
		for entry: DebugEntry in _sections[section]:
			if entry.callable.is_valid():
				alive.append(entry)
		if alive.is_empty():
			_sections.erase(section)
		else:
			_sections[section] = alive


# Abre ou fecha o menu, instanciando a cena na primeira vez que é pedido: enquanto ninguém aperta
# F4, o menu não custa nada.
func _toggle_menu() -> void:
	if _overlay == null:
		var scene: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugMenu] - ERRO: cena do menu de debug não encontrada em %s" % OVERLAY_SCENE_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		add_child(_overlay)
		_on_menu_opened()
		return
	if _overlay.visible:
		_overlay.visible = false
		_on_menu_closed()
	else:
		_overlay.visible = true
		_on_menu_opened()


# Guarda o modo de mouse anterior e força o cursor visível: o jogo pode estar com o mouse
# capturado, e sem isto não dá para clicar em nada no menu.
func _on_menu_opened() -> void:
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.call(&"refresh")
	print("[DebugMenu] - Menu de debug aberto")


# Restaura o modo de mouse anterior ao fechar, para não deixar o cursor visível dentro do jogo.
func _on_menu_closed() -> void:
	Input.mouse_mode = _previous_mouse_mode
	print("[DebugMenu] - Menu de debug fechado")


# Liga/desliga a pausa da árvore. É a ação mais usada de um mod menu: metade do debug é olhar o
# jogo parado num instante específico.
func _on_pause_toggled(enabled: bool) -> void:
	get_tree().paused = enabled


# Liga/desliga câmera lenta via time_scale, para observar movimento rápido demais para o olho.
func _on_slow_motion_toggled(enabled: bool) -> void:
	Engine.time_scale = 0.25 if enabled else 1.0


# Despausa por exatamente um frame e pausa de novo. Só faz sentido com o jogo já pausado — é a
# única forma honesta de investigar um bug que dura um frame só.
func _advance_one_frame() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().paused = true


# Recarrega a cena atual, tirando a pausa antes para a cena não nascer congelada.
func _reload_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# Encerra o jogo. Útil para testar o caminho de saída sem alt+F4.
func _quit_game() -> void:
	get_tree().quit()


# Liga/desliga o OSD de desempenho, instanciando a cena na primeira vez e liberando-a ao desligar.
# Liberar (em vez de esconder) é proposital: o overlay pede à RenderingServer a medição de tempo de
# render do viewport, que custa uma consulta ao driver por quadro. Um medidor invisível que continua
# cobrando pela medição é exatamente o tipo de coisa que envenena um profiling.
func _set_stats_enabled(enabled: bool) -> void:
	_stats_enabled = enabled
	if enabled:
		var scene: PackedScene = load(STATS_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugMenu] - ERRO: cena do overlay de desempenho não encontrada em %s" % STATS_SCENE_PATH)
			_stats_enabled = false
			return
		_stats_overlay = scene.instantiate() as CanvasLayer
		add_child(_stats_overlay)
		# As preferências vivem aqui, não no overlay: elas precisam sobreviver ao overlay ser
		# liberado e recriado a cada F2.
		_stats_overlay.call(&"set_corner", _stats_corner)
		_stats_overlay.call(&"set_graphs_visible", _stats_graphs_visible)
		print("[DebugMenu] - Overlay de desempenho ligado (canto %s)" % STATS_CORNER_NAMES[_stats_corner])
	else:
		if _stats_overlay != null:
			_stats_overlay.queue_free()
			_stats_overlay = null
		print("[DebugMenu] - Overlay de desempenho desligado")
	# Reescreve o toggle com o estado real. Sem isto, ligar o OSD pelo F2 deixaria o interruptor do
	# menu marcando o valor errado na próxima abertura — o menu é dono do bool que ele exibe.
	register_toggle(STATS_SECTION, STATS_TOGGLE_LABEL, _on_stats_toggled, _stats_enabled)


# Reage ao interruptor do menu. Mesmo caminho do F2, para os dois não poderem divergir.
func _on_stats_toggled(enabled: bool) -> void:
	_set_stats_enabled(enabled)


# Liga/desliga os mini-gráficos do OSD, deixando só os números. Guarda a preferência mesmo com o
# overlay desligado, para ela valer no próximo F2.
func _on_stats_graphs_toggled(enabled: bool) -> void:
	_stats_graphs_visible = enabled
	if _stats_overlay != null:
		_stats_overlay.call(&"set_graphs_visible", enabled)
	print("[DebugMenu] - Gráficos do overlay de desempenho %s" % ("ligados" if enabled else "desligados"))


# Gira o OSD entre os quatro cantos da tela. Existe porque o canto certo depende do que se está
# investigando: um HUD de jogo ou o próprio menu de debug empurram o OSD para outro lugar.
func _cycle_stats_corner() -> void:
	_stats_corner = (_stats_corner + 1) % STATS_CORNER_NAMES.size()
	if _stats_overlay != null:
		_stats_overlay.call(&"set_corner", _stats_corner)
	print("[DebugMenu] - Overlay de desempenho movido para o canto %s" % STATS_CORNER_NAMES[_stats_corner])


# Aceita a ação de input configurada e, se ela não existir no projeto, cai para a tecla direta.
# Evita que uma falha de configuração do Input Map deixe uma ferramenta de debug inacessível.
func _is_shortcut_pressed(event: InputEvent, action: StringName, fallback_keycode: Key) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == fallback_keycode


# Único ponto de checagem de build: editor ou build de debug. Release cai fora de register_*,
# do input de abertura e do registro de fábrica, sem precisar de um `if` em cada call site.
func _is_debug_build() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()
