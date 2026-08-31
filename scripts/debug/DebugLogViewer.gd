# DebugLogViewer.gd — Controle do visualizador de log (F5): liga/desliga o overlay e guarda as
# preferências de exibição (nível mínimo, filtro de texto, acompanhar ou não as novas linhas).
#
# Mesma divisão do overlay de desempenho: as preferências vivem aqui porque precisam sobreviver ao
# overlay ser liberado e recriado a cada F5; o overlay (DebugLogOverlay) só lê o log e desenha.
#
# Vive como nó filho do Autoload DebugMenu e registra a própria seção; não existe em release.
class_name DebugLogViewer
extends Node

const SECTION: StringName = &"Log"
const SCENE_PATH: String = "res://scenes/debugs/DebugLog.tscn"
# O rótulo é a identidade da entrada no registro, então precisa ser constante: é por ele que
# set_enabled() reescreve o toggle com o estado real depois de um F5.
const TOGGLE_LABEL: String = "Overlay de log (F5)"
# Ordem igual à do enum Level do overlay: o índice escolhido aqui É o nível mínimo exibido lá.
const LEVEL_NAMES: PackedStringArray = ["Tudo", "Avisos", "Erros"]

var _enabled: bool = false
var _overlay: CanvasLayer
var _min_level: int = 0
var _text_filter: String = ""
var _following: bool = true


func _ready() -> void:
	# [DEBUG] Seção "Log": visualizador do log do jogo (ver docs/debug_menu.md).
	DebugMenu.register_toggle(SECTION, TOGGLE_LABEL, _on_enabled_toggled, _enabled)
	DebugMenu.register_value(SECTION, "Nível mínimo", _on_level_changed,
		DebugParam.enum_value("nivel", LEVEL_NAMES, _min_level), _get_min_level)
	DebugMenu.register_value(SECTION, "Filtrar texto", _on_text_filter_changed,
		DebugParam.string_value("texto", _text_filter), _get_text_filter)
	DebugMenu.register_toggle(SECTION, "Acompanhar novas linhas", _on_following_toggled, _following)
	DebugMenu.register_action(SECTION, "Limpar visualização", _clear_view)
	DebugMenu.register_action(SECTION, "Copiar log visível", _copy_visible)


# Estado atual do overlay. Lido pelo DebugMenu para o F5 alternar sem duplicar o bool.
func is_enabled() -> bool:
	return _enabled


# Liga/desliga o overlay, instanciando a cena na primeira vez e liberando-a ao desligar. Liberar
# (em vez de esconder) é proposital: o overlay relê o arquivo de log a cada atualização, e um
# leitor invisível continuaria cobrando por isso. Nada se perde — o histórico está no arquivo, e o
# próximo F5 remonta a lista desde o início da sessão.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if enabled:
		var scene: PackedScene = load(SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[DebugLog] - ERRO: cena do overlay de log não encontrada em %s" % SCENE_PATH)
			_enabled = false
			return
		_overlay = scene.instantiate() as CanvasLayer
		add_child(_overlay)
		_push_preferences()
		print("[DebugLog] - Overlay de log ligado")
	else:
		if _overlay != null:
			_overlay.queue_free()
			_overlay = null
		print("[DebugLog] - Overlay de log desligado")
	# Reescreve o toggle com o estado real. Sem isto, ligar o overlay pelo F5 deixaria o
	# interruptor do menu marcando o valor errado na próxima abertura.
	DebugMenu.register_toggle(SECTION, TOGGLE_LABEL, _on_enabled_toggled, _enabled)


# Empurra as preferências guardadas para um overlay recém-criado.
func _push_preferences() -> void:
	_overlay.call(&"set_min_level", _min_level)
	_overlay.call(&"set_text_filter", _text_filter)
	_overlay.call(&"set_following", _following)


# Reage ao interruptor do menu. Mesmo caminho do F5, para os dois não poderem divergir.
func _on_enabled_toggled(enabled: bool) -> void:
	set_enabled(enabled)


# Esconde tudo abaixo do nível escolhido (Tudo / Avisos / Erros). É o corte que transforma um log
# barulhento em "só o que quebrou".
func _on_level_changed(level: int) -> void:
	_min_level = clampi(level, 0, LEVEL_NAMES.size() - 1)
	if _overlay != null:
		_overlay.call(&"set_min_level", _min_level)
	print("[DebugLog] - Nível mínimo do log: %s" % LEVEL_NAMES[_min_level])


# Filtra as linhas por texto (sem acento e sem diferenciar maiúsculas, como o filtro do menu).
func _on_text_filter_changed(text: String) -> void:
	_text_filter = text
	if _overlay != null:
		_overlay.call(&"set_text_filter", _text_filter)


# Liga/desliga o acompanhamento do fim do log. Desligado, o painel congela o que está na tela para
# dar tempo de ler e rolar; as linhas novas continuam sendo guardadas e entram quando religar.
func _on_following_toggled(enabled: bool) -> void:
	_following = enabled
	if _overlay != null:
		_overlay.call(&"set_following", _following)
	print("[DebugLog] - Acompanhamento do log %s" % ("ligado" if enabled else "pausado"))


# Esvazia o painel sem tocar no arquivo de log: serve para marcar "daqui pra frente" antes de
# reproduzir um bug.
func _clear_view() -> void:
	if _overlay == null:
		print("[DebugLog] - Nada a limpar: o overlay de log está desligado")
		return
	_overlay.call(&"clear_view")
	print("[DebugLog] - Visualização do log limpa")


# Copia para a área de transferência as linhas que passam pelos filtros atuais — o gesto de montar
# um report de bug sem precisar caçar o arquivo de log no disco.
func _copy_visible() -> void:
	if _overlay == null:
		print("[DebugLog] - Nada a copiar: o overlay de log está desligado")
		return
	var text: String = _overlay.call(&"get_visible_text")
	DisplayServer.clipboard_set(text)
	var line_count: int = 0 if text.is_empty() else text.split("\n").size()
	print("[DebugLog] - %d linha(s) copiada(s) para a área de transferência" % line_count)


# Lidos pelo menu ao remontar a UI, para os widgets mostrarem o estado real em vez da cópia
# guardada no registro.
func _get_min_level() -> int:
	return _min_level


func _get_text_filter() -> String:
	return _text_filter
