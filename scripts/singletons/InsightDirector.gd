# InsightDirector.gd — Autoload: quem decide qual insight vale agora e anuncia a leitura.
#
# É o cérebro do sistema e não conhece nenhuma tela: resolve a escolha, emite o fato no EventBus e
# escolhe a apresentação pelo canal — caixa in loco (pedida à própria fonte, que sabe onde está) ou
# tela de diálogo (pedida pelo bus, para quem quer que esteja atendendo).
#
# As fontes da cena se registram aqui ao entrar na árvore e saem sozinhas ao sair. A reavaliação dos
# marcadores é adiada para o fim do frame: uma leitura marca o lido, concede uma flag e move a
# órbita, e reavaliar três vezes no mesmo frame daria exatamente o mesmo resultado.
#
# O guia completo está em docs/insights.md.
extends Node

const DEBUG_SECTION: StringName = &"Insights"
# Verde é a identidade do canal de ambiente, não valor de balanceamento: muda uma vez, para o jogo
# inteiro. O que é ajustável por fonte (raio, posição do orbe) é @export na InsightSource.
const ENVIRONMENT_COLOR: Color = Color(0.35, 0.85, 0.45)

var _sources: Array[InsightSource] = []
var _orbit_layer: HeadOrbitLayer = null
# [DEBUG] Mostra tudo que existe na cena, independente de flags e de cabeças desbloqueadas.
var _ignore_gates: bool = false
# [DEBUG] Desenha em jogo o raio de clique de cada fonte.
var _draw_click_radius: bool = false
var _refresh_queued: bool = false


func _ready() -> void:
	# Sem picking de física ligado no viewport, o input_event do Area2D do marcador nunca dispara e
	# o sistema inteiro fica mudo — o tipo de falha que se investiga por horas procurando no lugar
	# errado. Ligar aqui, uma vez, é mais barato que documentar a configuração.
	get_viewport().physics_object_picking = true
	# Adiado de propósito: este Autoload é declarado antes de HeadRegistry e InsightJournal (para as
	# ações de diagnóstico virem primeiro na seção de debug), e eles ainda não existem quando este
	# _ready() roda. A chamada adiada cai no fim do frame, com todos os Autoloads prontos.
	_connect_state_sources.call_deferred()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": responde "por que este insight não aparece?" (ver docs/insights.md).
		DebugMenu.register_action(DEBUG_SECTION, "Diagnóstico da cena", _debug_print_scene_report)
		DebugMenu.register_action(DEBUG_SECTION, "Validar todos os insights", _debug_print_project_report)
		DebugMenu.register_toggle(DEBUG_SECTION, "Ignorar portas", _debug_set_ignore_gates, _ignore_gates)
		DebugMenu.register_toggle(DEBUG_SECTION, "Desenhar raio de clique", _debug_set_draw_click_radius, _draw_click_radius)
		DebugMenu.register_input(DEBUG_SECTION, "Disparar insight", _debug_trigger_insight, [
			DebugParam.string_value("id", "", _debug_insight_suggestions)
		])


# Registra uma fonte da cena. Chamado pela própria InsightSource ao entrar na árvore; ninguém
# precisa manter lista de fontes em lugar nenhum.
func register_source(source: InsightSource) -> void:
	if _sources.has(source):
		return
	_sources.append(source)
	request_refresh()


# Tira a fonte do registro quando ela sai da árvore (troca de cena, objeto destruído).
func unregister_source(source: InsightSource) -> void:
	if not _sources.has(source):
		return
	_sources.erase(source)
	request_refresh()


# Guarda a órbita do jogador da cena atual. É por ela que os insights de cabeça viram orbes — o
# gatilho é a fonte, mas a âncora é o jogador.
func set_orbit_layer(layer: HeadOrbitLayer) -> void:
	_orbit_layer = layer
	request_refresh()


# Esquece a órbita ao sair da árvore. Compara antes de limpar para uma cena nova que já registrou a
# própria órbita não ser apagada pela saída da cena antiga.
func clear_orbit_layer(layer: HeadOrbitLayer) -> void:
	if _orbit_layer == layer:
		_orbit_layer = null


# Fontes registradas na cena atual, já sem as que foram liberadas. Usada pelos relatórios de debug.
func get_sources() -> Array[InsightSource]:
	_purge_dead_sources()
	return _sources.duplicate()


# Agenda a reavaliação de todos os marcadores para o fim do frame. Público porque qualquer coisa que
# mude o mundo (o jogador entrar no raio de uma fonte, uma flag nova) precisa pedir isso.
func request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


# Melhor insight de ambiente desta fonte, ou null quando nenhum passa nas portas — e aí a fonte não
# desenha marcador nenhum, que é o que mantém o mundo limpo conforme o jogador lê.
func pick_environment(source: InsightSource) -> InsightData:
	return _pick_best(source.insights, InsightData.Channel.ENVIRONMENT, &"")


# Uma oferta por cabeça, entre tudo que está ao alcance do jogador agora, na ordem em que a órbita
# deve mostrá-las. Um orbe por cabeça, nunca um por insight: quatro insights da mesma cabeça na
# mesma esquina viram um orbe só, e o Director escolhe o conteúdo no clique.
func collect_character_offers() -> Array[InsightOffer]:
	_purge_dead_sources()
	var best_by_head: Dictionary = {}
	for source: InsightSource in _sources:
		if not source.is_player_in_range():
			continue
		for insight: InsightData in source.insights:
			if insight == null or not insight.is_character() or not is_open(insight):
				continue
			var candidate: InsightOffer = InsightOffer.new(insight.head_id, insight, source, is_new(insight))
			var current: InsightOffer = best_by_head.get(insight.head_id, null) as InsightOffer
			if current == null or _candidate_beats(candidate, current):
				best_by_head[insight.head_id] = candidate
	var offers: Array[InsightOffer] = []
	for head_id: StringName in best_by_head:
		offers.append(best_by_head[head_id])
	offers.sort_custom(_compare_offers)
	return offers


# Diz se as portas do insight estão abertas: cabeça desbloqueada, required_flags concedidas e
# nenhuma blocked_by_flags no caminho. Insight fechado não vira marcador.
func is_open(insight: InsightData) -> bool:
	if _ignore_gates:
		return true
	if insight.is_character() and not HeadRegistry.has_head(insight.head_id):
		return false
	for flag: StringName in insight.required_flags:
		if not InsightJournal.has_flag(flag):
			return false
	for flag: StringName in insight.blocked_by_flags:
		if InsightJournal.has_flag(flag):
			return false
	return true


# Diz se o insight ainda é novidade. Com one_shot, ler tira o insight da fila de novidades mas não o
# apaga: ele continua relegível, e é isso que mantém o orbe vazado no lugar em vez de sumir.
func is_new(insight: InsightData) -> bool:
	if not is_open(insight):
		return false
	if not insight.one_shot:
		return true
	return not InsightJournal.is_read(insight.id)


# Anuncia a leitura e escolhe a apresentação pelo canal. É o único caminho para um insight aparecer
# na tela: marcador, ação de debug e console passam todos por aqui.
func reveal(insight: InsightData, source: InsightSource) -> void:
	if insight == null:
		push_warning("[Insights] - AVISO: reveal() chamado sem insight")
		return
	var first_time: bool = not InsightJournal.is_read(insight.id)
	var source_id: int = source.get_instance_id() if source != null else 0
	EventBus.insight_revealed.emit(InsightRevealedEvent.new(insight.id, insight.channel,
		insight.head_id, insight.text_key, source_id, first_time))
	if first_time and insight.grants_flag != &"":
		InsightJournal.grant_flag(insight.grants_flag)
	print("[Insights] - Insight \"%s\" lido (%s)" % [insight.id, "primeira vez" if first_time else "releitura"])

	if insight.is_character():
		EventBus.dialogue_requested.emit(insight.head_id, insight.text_key)
	elif source != null:
		source.open_bubble(insight)
	else:
		push_warning("[Insights] - AVISO: insight de ambiente \"%s\" sem fonte na cena; nada a exibir" % insight.id)


# Diz se o debug mandou ignorar todas as portas. Lido pelos relatórios, que precisam avisar que o
# diagnóstico está saindo com as portas desligadas.
func is_ignoring_gates() -> bool:
	return _ignore_gates


# Diz se o debug mandou desenhar o raio de clique das fontes. Lido pela própria InsightSource.
func is_drawing_click_radius() -> bool:
	return _draw_click_radius


# Conecta o Director às duas fontes de estado que mudam o que está disponível. Signals diretos (e
# não eventos de bus) porque o interessado é exatamente um — ver docs/event_bus.md, "Quando usar".
func _connect_state_sources() -> void:
	InsightJournal.journal_changed.connect(_on_world_state_changed)
	HeadRegistry.heads_changed.connect(_on_world_state_changed)


# Reavalia tudo quando o diário ou o elenco de cabeças muda: é isso que faz um orbe nascer no
# instante em que a flag que o destrava é concedida, sem ninguém recarregar a cena.
func _on_world_state_changed() -> void:
	request_refresh()


# Executa a reavaliação agendada por request_refresh().
func _refresh() -> void:
	_refresh_queued = false
	_purge_dead_sources()
	for source: InsightSource in _sources:
		source.refresh_marker()
	if _orbit_layer != null:
		_orbit_layer.show_offers(collect_character_offers())


# Tira do registro as fontes já liberadas. Acontece na troca de cena: a fonte some sem passar pelo
# _exit_tree() em alguns caminhos de liberação, e uma lista com nós mortos quebraria a reavaliação.
func _purge_dead_sources() -> void:
	var alive: Array[InsightSource] = []
	for source: InsightSource in _sources:
		if is_instance_valid(source):
			alive.append(source)
	_sources = alive


# Melhor insight da lista para um canal (e, no canal de personagem, para uma cabeça específica).
# Novidade ganha de relido; entre iguais, ganha a prioridade mais alta.
func _pick_best(insights: Array[InsightData], channel: InsightData.Channel, head_id: StringName) -> InsightData:
	var best_new: InsightData = null
	var best_read: InsightData = null
	for insight: InsightData in insights:
		if insight == null or insight.channel != channel:
			continue
		if head_id != &"" and insight.head_id != head_id:
			continue
		if not is_open(insight):
			continue
		if is_new(insight):
			if best_new == null or insight.priority > best_new.priority:
				best_new = insight
		elif best_read == null or insight.priority > best_read.priority:
			best_read = insight
	return best_new if best_new != null else best_read


# Desempate entre duas ofertas da mesma cabeça: novidade primeiro, depois prioridade, depois id —
# o id no fim garante resultado igual entre execuções, sem depender da ordem de registro das fontes.
func _candidate_beats(candidate: InsightOffer, current: InsightOffer) -> bool:
	if candidate.is_new != current.is_new:
		return candidate.is_new
	if candidate.insight.priority != current.insight.priority:
		return candidate.insight.priority > current.insight.priority
	return String(candidate.insight.id) < String(current.insight.id)


# Ordena as ofertas por prioridade e, no empate, por id de cabeça. Ordem estável é o que impede um
# orbe de trocar de lugar entre um frame e outro e o jogador clicar no errado.
func _compare_offers(left: InsightOffer, right: InsightOffer) -> bool:
	if left.insight.priority != right.insight.priority:
		return left.insight.priority > right.insight.priority
	return String(left.head_id) < String(right.head_id)


# [DEBUG] Imprime no log o diagnóstico da cena atual: cada fonte, cada insight e o ✓/✗ de cada
# porta. É a resposta para "por que este insight não aparece?" sem precisar ler código.
func _debug_print_scene_report() -> void:
	print(InsightDebugReport.scene_report())


# [DEBUG] Varre todos os .tres do projeto atrás de id repetido, text_key inexistente, head_id
# inexistente e porta morta — o insight que nunca vai aparecer para ninguém.
func _debug_print_project_report() -> void:
	InsightCatalog.clear_cache()
	print(InsightDebugReport.project_report())


# [DEBUG] Liga/desliga o bypass das portas.
func _debug_set_ignore_gates(enabled: bool) -> void:
	_ignore_gates = enabled
	print("[Insights] - Ignorar portas %s" % ("ligado" if enabled else "desligado"))
	request_refresh()


# [DEBUG] Liga/desliga o desenho do raio de clique das fontes em jogo.
func _debug_set_draw_click_radius(enabled: bool) -> void:
	_draw_click_radius = enabled
	print("[Insights] - Desenho do raio de clique %s" % ("ligado" if enabled else "desligado"))
	request_refresh()


# [DEBUG] Dispara um insight pelo id, sem precisar chegar perto de nada. Procura primeiro nas fontes
# da cena (para a caixa de ambiente ter onde nascer) e, se não achar, no catálogo do projeto.
func _debug_trigger_insight(insight_id: String) -> void:
	var wanted: StringName = StringName(insight_id)
	_purge_dead_sources()
	for source: InsightSource in _sources:
		for insight: InsightData in source.insights:
			if insight != null and insight.id == wanted:
				reveal(insight, source)
				return
	for insight: InsightData in InsightCatalog.load_all_insights():
		if insight.id == wanted:
			reveal(insight, null)
			return
	push_warning("[Insights] - AVISO: nenhum insight com id \"%s\"" % insight_id)


# [DEBUG] Sugere ao autocomplete do console os ids que existem no projeto.
func _debug_insight_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for insight: InsightData in InsightCatalog.load_all_insights():
		result.append(String(insight.id))
	return result
