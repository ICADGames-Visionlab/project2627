## NPCDirector - povoa a cena com os NPCs que a rotina de cada um manda estar aqui agora, e os move
## quando o relógio anda.
##
## COMO USAR: um nó com este script na cena de gameplay, com o roster apontado e "Agents Parent"
## apontando pro nó de Y-sort da cena. Só isso — nenhum NPC é colocado na cena à mão.
##
## POR QUE UM NÓ DE CENA E NÃO UM AUTOLOAD: porque não existe estado de NPC a preservar entre cenas.
## A posição de cada NPC é DERIVADA do relógio (ver NPCRoutineResolver), e a emoção vigente é
## decidida na virada de dia — a partir da escolha que o jogador fez no sonho, que é guardada e
## salva pelo ProfilingJournal, não aqui. Um Autoload existiria só pra guardar o que já dá pra
## recalcular — e o guideline pede discussão com o Lead de Programação antes de criar Autoload novo.
## Quando a emoção passar a mudar dentro do dia, aí sim vale essa conversa (ver
## docs/sistema_de_npc.md).
##
## O CICLO, INTEIRO:
##
##   1. O relógio anda e o EventBus avisa.
##   2. Para cada NPC do roster, o resolver diz qual é a entrada vigente da rotina dele — ou, se uma
##      exceção estiver valendo (a ronda do policial), a parada em que ela o coloca agora.
##   3. Entrada nesta cena e sem corpo em cena  -> nasce no waypoint.
##      Entrada nesta cena e corpo já em cena   -> anda até o waypoint.
##      Entrada em outra cena e corpo em cena   -> desaparece.
##
## O guia completo está em docs/sistema_de_npc.md.
class_name NPCDirector
extends Node2D

## Espaço para constantes

# Grupo em que este nó se registra, pra quem precisar dele (menu de debug, futuros sistemas de
# diálogo) não depender de NodePath.
const GROUP: StringName = &"npc_director"

# Seção em que os controles deste sistema aparecem no menu de debug (F4) e no console (F1).
const DEBUG_SECTION: StringName = &"NPCs"

# Opções do comando de debug que força a emoção, na ordem do enum NPCDefinition.EmotionSlot.
const DEBUG_SLOT_OPTIONS: PackedStringArray = ["neutro", "emocao1", "emocao2"]

# Opções do comando que força o tipo de dia. O índice 0 é "automático" (o calendário do NPC decide),
# e os outros dois são NPCDefinition.DayType deslocado em 1.
const DEBUG_DAY_TYPE_OPTIONS: PackedStringArray = ["automatico", "trabalho", "folga"]

## Espaço para variáveis exportadas

## Os NPCs que existem no jogo (res://resources/npcs/npc_roster.tres).
@export var roster: NPCRoster

## A cena do corpo do NPC (res://scenes/npc/NPC.tscn).
@export var npc_scene: PackedScene

## Onde os NPCs são instanciados. Tem que ser o nó com y_sort_enabled da cena (o "YSort"), senão
## eles não se ordenam com os prédios e aparecem sempre na frente ou sempre atrás.
@export var agents_parent: Node2D

## Raio, em pixels de tela, do espalhamento em volta do waypoint. Dois NPCs que a rotina manda pro
## MESMO waypoint no mesmo horário não podem mirar o mesmo pixel: eles se empurram, travam um ao
## outro e um dos dois desiste do caminho. Zero desliga o espalhamento (todos param no ponto exato).
@export var waypoint_scatter: float = 56.0

## Espaço para variáveis

# Corpos em cena agora: id do NPC -> NPC. Quem não está aqui simplesmente não existe como nó, e
# isso é o normal — a maioria dos NPCs está em outra cena na maior parte do dia.
var _bodies: Dictionary = {}

# Emoção vigente de cada NPC hoje: id -> NPCDefinition.EmotionSlot.
var _slots: Dictionary = {}

# Entrada de rotina vigente de cada NPC: id -> NPCRoutineEntry. Serve pra saber se a entrada MUDOU
# nesta resolução — é a mudança que dispara o caminhar, não o tique do relógio.
var _entries: Dictionary = {}

# Última decisão de cada NPC: id -> NPCRoutineResolver.Decision. Só o menu de debug lê.
var _decisions: Dictionary = {}

# Exceção que mandava em cada NPC na última resolução: id -> NPCRoutineException (ou null). Serve só
# pra logar o instante em que a ronda começa e termina; onde o NPC está continua sendo derivado do
# relógio, e nada aqui o decide.
var _exceptions: Dictionary = {}

# Waypoints que já foram reclamados, pra o aviso sair uma vez por nome e não a cada tique.
var _missing_waypoints: Dictionary = {}

# O que as exceções perguntam sobre a caminhada (NPCRoutineException.TravelTimes), um por NPC porque a
# velocidade é do NPC: id -> TravelTimes.
var _travel_times: Dictionary = {}

# Minutos de caminhada já calculados: "npc|de|para" -> int. O cenário não muda em jogo, então cada trecho
# é medido uma vez só.
var _travel_cache: Dictionary = {}

# Achatamento e fator vertical do corpo do NPC, lidos da cena dele na primeira vez que a caminhada precisa
# ser calculada. São exports do NPC.gd, e a conta de velocidade (Isometric) tem que usar os mesmos números
# que o corpo usa pra andar.
var _walk_shape_loaded: bool = false
var _y_ratio: float = 0.5
var _vertical_factor: float = 0.75

# [DEBUG] Estado dos controles do menu de debug.
var _draw_paths: bool = false
var _day_type_override: int = -1

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)

	if roster == null:
		push_error("[NPCDirector] - Sem roster apontado; nenhum NPC vai existir")
		return
	if npc_scene == null:
		push_error("[NPCDirector] - Sem cena de NPC apontada; nenhum NPC vai existir")
		return
	if agents_parent == null:
		push_warning("[NPCDirector] - AVISO: \"Agents Parent\" não apontado; usando o nó pai. "
			+ "Se ele não tiver y_sort_enabled, os NPCs não vão se ordenar com os prédios")

	EventBus.time_changed.connect(_on_time_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.dream_started.connect(_on_dream_started)

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "NPCs" do menu (F4) e do console (F1).
		_register_debug_entries()

	_refresh_emotion_slots()

	# Espera um frame antes de povoar, pelo mesmo motivo do Pathfinder: os waypoints e as estruturas
	# instanciados junto com a cena ainda podem estar entrando na árvore, e um waypoint que chegue
	# depois não seria encontrado.
	await get_tree().process_frame
	_apply_routines(true)
	print("[NPCDirector] - Cidade povoada: %d de %d NPCs estão nesta cena" % [
		_bodies.size(), roster.npcs.size()])

## Espaço para funções personalizadas

# Troca a emoção vigente de um NPC AGORA e recoloca ele na rotina correspondente.
#
# É a troca imediata, usada pelo menu de debug pra revisar as seis rotinas de um NPC em dois minutos.
# O caminho do JOGO é outro: o jogador escolhe a emoção no sonho (profiling), e ela entra em vigor na
# virada de dia, por _refresh_emotion_slots() — que é onde o sistema de emoção mora. Forçar aqui não
# grava escolha nenhuma, então a próxima virada de dia devolve a emoção que o profiling manda.
func set_emotion_slot(id: StringName, slot: int) -> void:
	var definition: NPCDefinition = roster.find(id)
	if definition == null:
		push_warning("[NPCDirector] - AVISO: \"%s\" não está no roster" % id)
		return

	_slots[id] = slot
	var body: NPC = _bodies.get(id) as NPC
	if body != null:
		body.set_emotion(definition.get_emotion(slot))

	print("[NPCDirector] - \"%s\" agora está em %s" % [id, definition.describe_slot(slot)])

	# Sem snap: o NPC ANDA até o novo lugar, o que é justamente o que se quer ver ao testar as
	# rotinas de uma emoção pelo menu de debug.
	_apply_routines(false)


# A emoção vigente de um NPC hoje.
func get_emotion_slot(id: StringName) -> int:
	return _slots.get(id, NPCDefinition.EmotionSlot.NEUTRAL)


# O corpo de um NPC, ou null se ele não está nesta cena. É por aqui que outros sistemas (diálogo,
# quest) vão achar um NPC sem precisar varrer a árvore.
func get_body(id: StringName) -> NPC:
	return _bodies.get(id) as NPC


# Escolhe a emoção vigente de cada NPC para o dia.
#
# ESTE É O PONTO DE EXTENSÃO DO SISTEMA DE EMOÇÃO, e quem o ocupa hoje é o profiling: a emoção de um
# NPC é a que o JOGADOR escolheu no espírito dele, dentro do sonho, e que passou a valer no dia
# seguinte. Sem escolha nenhuma, vale a emoção inicial que o design marcou no .tres — e é por isso
# que a cidade funciona igual antes de o jogador sonhar pela primeira vez.
#
# A conta de "qual escolha já venceu" é do ProfilingJournal (ele é o dono desse estado e o que o
# grava no save); ver ProfilingJournal.resolve_emotion_slot e docs/sistema_de_profiling.md. O resto
# deste sistema continua só consultando o slot já decidido, sem saber nada sobre o que causa emoção.
func _refresh_emotion_slots() -> void:
	for definition: NPCDefinition in roster.npcs:
		if definition != null:
			_slots[definition.id] = ProfilingJournal.resolve_emotion_slot(definition)


# Resolve a rotina de todos os NPCs e ajusta a cena.
#
# snap = true faz os NPCs ASSUMIREM a posição em vez de caminhar até ela. É o comportamento certo
# quando não houve trajeto a percorrer: ao montar a cena, ao virar o dia e quando o tempo pula.
func _apply_routines(snap: bool) -> void:
	# No sonho a rotina não vale: todo mundo está na posição fixa de sonho. Desviar aqui, no ponto
	# por onde TODA resolução passa (tique, virada de dia, debug), é o que garante que nenhum caminho
	# esquecido tire um NPC do lugar enquanto o jogador sonha.
	if GameClock.is_dreaming():
		_apply_dream_positions()
		return

	var weekday: int = GameClock.time.get_weekday()
	var minutes_into_day: int = GameClock.time.get_minutes_into_day()
	var wake_hour: int = GameClock.settings.wake_hour

	for definition: NPCDefinition in roster.npcs:
		if definition == null:
			continue

		var travel: NPCRoutineException.TravelTimes = _get_travel(definition)
		var decision: NPCRoutineResolver.Decision = NPCRoutineResolver.resolve(
			definition, get_emotion_slot(definition.id), weekday, minutes_into_day, wake_hour, travel)

		# Muda o tipo de dia por cima da decisão quando o menu de debug está forçando um.
		if _day_type_override >= 0 and decision.day_type != _day_type_override:
			decision = NPCRoutineResolver.resolve(definition, get_emotion_slot(definition.id),
				_weekday_for_override(definition), minutes_into_day, wake_hour, travel)

		_decisions[definition.id] = decision
		_log_exception_change(definition, decision)
		_apply_entry(definition, decision.entry, snap)


# Põe cada NPC na posição fixa de sonho, sem caminhar: ninguém atravessa a cidade para chegar a um
# sonho. Quem não tem posição de sonho some — diferente do dia, em que o NPC sem rotina fica onde
# está, porque no sonho "onde ele estava" é justamente o mundo acordado.
func _apply_dream_positions() -> void:
	for definition: NPCDefinition in roster.npcs:
		if definition == null:
			continue

		if definition.dream_entry == null:
			var body: NPC = _bodies.get(definition.id) as NPC
			if body != null:
				_despawn(definition.id, body)
			continue

		_apply_entry(definition, definition.dream_entry, true)


# Aplica a entrada vigente de um NPC: nascer, andar, ficar ou desaparecer.
func _apply_entry(definition: NPCDefinition, entry: NPCRoutineEntry, snap: bool) -> void:
	var body: NPC = _bodies.get(definition.id) as NPC

	if entry == null:
		# Sem rotina executável. Quem já está em cena fica onde está (melhor que sumir), e quem não
		# está não nasce. O aviso sai do "Validar rotinas", não daqui, pra não repetir a cada tique.
		return

	if not _is_current_scene(entry.scene_path):
		if body != null:
			_despawn(definition.id, body)
		_entries[definition.id] = entry
		return

	var waypoint: Waypoint = Waypoint.find(get_tree(), entry.waypoint)
	if waypoint == null:
		_warn_missing_waypoint(definition, entry)
		return

	# Compara o LUGAR, e não a identidade da entrada: as paradas de uma exceção (a ronda) são entradas
	# avulsas, recriadas a cada resolução, e o que faz o NPC andar é ter que ir pra um lugar diferente.
	var changed: bool = not entry.is_same_place(_entries.get(definition.id) as NPCRoutineEntry)
	_entries[definition.id] = entry

	var target: Vector2 = _scattered_position(waypoint, definition)
	if body == null:
		_spawn(definition, target)
	elif snap:
		body.snap_to(target)
	elif changed:
		body.walk_to(target)


# O TravelTimes de um NPC, criado na primeira vez que ele é resolvido. É por aqui que uma exceção (a
# ronda) descobre quanto o NPC leva pra andar entre dois pontos, sem conhecer Pathfinder nem cena.
func _get_travel(definition: NPCDefinition) -> NPCRoutineException.TravelTimes:
	var travel: NPCRoutineException.TravelTimes = _travel_times.get(definition.id) as NPCRoutineException.TravelTimes
	if travel == null:
		travel = NPCRoutineException.TravelTimes.new(_travel_minutes.bind(definition))
		_travel_times[definition.id] = travel
	return travel


# Quantos minutos de jogo o NPC leva pra andar de um waypoint a outro desta cena.
#
# É o caminho de verdade (Pathfinder, entre os pontos EXATOS onde este NPC para, com o deslocamento dele)
# percorrido na velocidade de verdade (a conta do movimento, Isometric.walk_seconds), passado pra minutos
# de jogo pelo ritmo do relógio. Arredonda PRA CIMA em blocos de TICK_MINUTES: o relógio só anuncia a
# passagem do tempo a cada tique, então uma caminhada que terminasse fora dele só seria notada no tique
# seguinte, e arredondar pra cima garante que a parada nunca dure menos do que o design pediu. Menos de
# um minuto de jogo não conta.
#
# É uma função do cenário e da velocidade, e de mais nada: dois dias iguais dão a mesma caminhada, e é isso
# que mantém a ronda idêntica todo dia. Quem trava o NPC no meio do caminho (o Player parado na rota)
# encurta a parada dele, mas não desloca a agenda.
func _travel_minutes(from_id: StringName, to_id: StringName, definition: NPCDefinition) -> int:
	var key: String = "%s|%s|%s" % [definition.id, from_id, to_id]
	if _travel_cache.has(key):
		return _travel_cache[key]

	var from_waypoint: Waypoint = Waypoint.find(get_tree(), from_id)
	var to_waypoint: Waypoint = Waypoint.find(get_tree(), to_id)
	if from_waypoint == null or to_waypoint == null:
		# Sem guardar no cache: o waypoint pode só não ter entrado na cena ainda.
		return 0

	var from_position: Vector2 = _scattered_position(from_waypoint, definition)
	var to_position: Vector2 = _scattered_position(to_waypoint, definition)

	var path: PackedVector2Array = PackedVector2Array([to_position])
	var pathfinder: Pathfinder = get_tree().get_first_node_in_group(Pathfinder.GROUP) as Pathfinder
	if pathfinder != null:
		var found: PackedVector2Array = pathfinder.find_path(from_position, to_position, [])
		if not found.is_empty():
			path = found

	_load_walk_shape()
	var seconds: float = Isometric.walk_seconds(
		from_position, path, definition.walk_speed, _y_ratio, _vertical_factor)
	var minutes: float = seconds / GameClock.settings.seconds_per_game_minute()

	var rounded: int = 0
	if minutes >= 1.0:
		rounded = ceili(minutes / GameClock.TICK_MINUTES) * GameClock.TICK_MINUTES
	_travel_cache[key] = rounded
	return rounded


# Lê o achatamento e o fator vertical da cena do NPC (o corpo é quem os tem como export), uma vez só.
# Instancia sem pôr na árvore: o _ready não roda e o corpo de teste some logo em seguida.
func _load_walk_shape() -> void:
	if _walk_shape_loaded:
		return
	_walk_shape_loaded = true

	var probe: NPC = npc_scene.instantiate() as NPC
	if probe == null:
		return
	_y_ratio = probe.isometric_y_ratio
	_vertical_factor = probe.vertical_speed_factor
	probe.free()


# Registra no log quando uma exceção passa a mandar no NPC e quando deixa de mandar. É o instante em
# que a ronda começa e termina, que de outro jeito só se percebe olhando o NPC andar. Só loga na
# TRANSIÇÃO: a resolução roda a cada tique do relógio, e uma linha por tique seria ruído.
func _log_exception_change(definition: NPCDefinition, decision: NPCRoutineResolver.Decision) -> void:
	var previous: NPCRoutineException = _exceptions.get(definition.id) as NPCRoutineException
	if decision.exception == previous:
		return

	_exceptions[definition.id] = decision.exception
	if decision.exception != null:
		print("[NPCDirector] - \"%s\" assumiu a exceção: %s" % [definition.id, decision.exception.describe()])
	else:
		print("[NPCDirector] - \"%s\" saiu da exceção e voltou à rotina padrão" % definition.id)


# Instancia o corpo de um NPC já no lugar certo.
func _spawn(definition: NPCDefinition, position: Vector2) -> void:
	var body: NPC = npc_scene.instantiate() as NPC
	if body == null:
		push_error("[NPCDirector] - A cena apontada em \"NPC Scene\" não tem o script NPC.gd")
		return

	body.name = "NPC_%s" % definition.id
	_resolve_agents_parent().add_child(body)

	# Depois do add_child: configure() usa os nós filhos, que só existem depois do _ready do corpo.
	body.configure(definition, definition.get_emotion(get_emotion_slot(definition.id)))
	body.snap_to(position)
	body.draw_path = _draw_paths
	body.appear()
	body.arrived.connect(_on_npc_arrived.bind(definition))

	_bodies[definition.id] = body


func _despawn(id: StringName, body: NPC) -> void:
	_bodies.erase(id)
	body.disappear()


# O ponto exato em que um NPC para dentro de um waypoint: o waypoint mais um deslocamento próprio
# dele.
#
# O deslocamento é DERIVADO DO ID, e não sorteado, porque a resolução acontece a cada tique do
# relógio: um valor aleatório mudaria o destino do NPC a cada dez minutos de jogo e ele passaria o
# dia dando passinhos em volta do ponto.
func _scattered_position(waypoint: Waypoint, definition: NPCDefinition) -> Vector2:
	if waypoint_scatter <= 0.0:
		return waypoint.global_position

	var angle: float = fmod(absf(float(hash(definition.id))), TAU)
	var offset: Vector2 = Vector2.from_angle(angle) * waypoint_scatter
	# Achatado em Y como todo o resto do chão: um círculo na tela seria uma elipse no chão isométrico.
	offset.y *= 0.5
	return waypoint.global_position + offset


# Diz se um caminho de cena é a cena que está rodando agora. É a comparação que decide se o NPC
# existe como nó ou só como rotina.
func _is_current_scene(scene_path: String) -> bool:
	var current: Node = get_tree().current_scene
	if current == null:
		return false
	# O caminho da rotina pode estar gravado como "uid://..." (o Inspector faz isso), e a cena em jogo
	# só conhece "res://...": comparar direto fazia o NPC sumir sem aviso.
	return current.scene_file_path == NPCRoutineEntry.to_scene_path(scene_path)


# Onde instanciar os corpos: o nó de Y-sort apontado, ou o pai deste nó como último recurso.
func _resolve_agents_parent() -> Node:
	if agents_parent != null:
		return agents_parent
	return get_parent()


# Reclama de um waypoint que a rotina aponta e a cena não tem — uma vez por nome, senão sairia um
# aviso a cada tique do relógio. É o erro mais comum de autoria de rotina (nome digitado diferente
# do nó), e o comando "Listar waypoints da cena" existe justamente pra resolvê-lo.
func _warn_missing_waypoint(definition: NPCDefinition, entry: NPCRoutineEntry) -> void:
	var key: String = "%s/%s" % [definition.id, entry.waypoint]
	if _missing_waypoints.has(key):
		return
	_missing_waypoints[key] = true
	push_warning("[NPCDirector] - AVISO: a rotina de \"%s\" (%s) aponta o waypoint \"%s\", que não existe nesta cena"
		% [definition.id, entry.format_clock(), entry.waypoint])


# Dia da semana falso que produz o tipo de dia forçado pelo menu de debug. Em vez de espalhar um
# "override" por dentro do resolver, mente-se o dia da semana na entrada dele: o resolver continua
# sendo uma função pura do que recebe, e o debug não vira um caminho paralelo de decisão.
func _weekday_for_override(definition: NPCDefinition) -> int:
	var want_workday: bool = _day_type_override == NPCDefinition.DayType.WORKDAY
	for weekday: int in GameTime.DAYS_PER_WEEK:
		if definition.is_workday(weekday) == want_workday:
			return weekday

	# O NPC não tem nenhum dia desse tipo (trabalha todos os dias, ou nenhum): não há o que forçar.
	return GameClock.time.get_weekday()


func _on_time_changed(_total_minutes: int) -> void:
	_apply_routines(false)


# Virada de dia: a emoção vigente é reescolhida e todo mundo assume a posição da rotina nova. É
# snap, e não caminhada, porque as horas de sono não foram vividas — ninguém atravessou a cidade.
func _on_day_changed(day: int) -> void:
	_refresh_emotion_slots()
	_apply_routines(true)
	print("[NPCDirector] - Dia %d: rotinas reavaliadas" % day)


func _on_dream_started(_day: int) -> void:
	_apply_routines(true)
	print("[NPCDirector] - Mundo dos sonhos: %d NPCs em posição de sonho nesta cena" % _bodies.size())


func _on_npc_arrived(definition: NPCDefinition) -> void:
	var entry: NPCRoutineEntry = _entries.get(definition.id) as NPCRoutineEntry
	if entry != null:
		print("[NPCDirector] - \"%s\" chegou em \"%s\"" % [definition.id, entry.waypoint])


# [DEBUG] Entradas da seção "NPCs". Não existem em build de release.
func _register_debug_entries() -> void:
	DebugMenu.register_input(DEBUG_SECTION, "Forçar emoção", _debug_force_emotion, [
		DebugParam.string_value("npc", "", _debug_npc_suggestions),
		DebugParam.enum_value("emocao", DEBUG_SLOT_OPTIONS)])
	DebugMenu.register_input(DEBUG_SECTION, "Forçar tipo de dia", _debug_force_day_type, [
		DebugParam.enum_value("tipo", DEBUG_DAY_TYPE_OPTIONS)])
	DebugMenu.register_input(DEBUG_SECTION, "Trazer NPC até o player", _debug_bring_to_player, [
		DebugParam.string_value("npc", "", _debug_npc_suggestions)])
	DebugMenu.register_action(DEBUG_SECTION, "Listar NPCs", _debug_list_npcs)
	DebugMenu.register_action(DEBUG_SECTION, "Listar waypoints da cena", _debug_list_waypoints)
	DebugMenu.register_action(DEBUG_SECTION, "Validar rotinas", _debug_validate_routines)
	DebugMenu.register_action(DEBUG_SECTION, "Autoteste das rotinas", _debug_run_self_test)
	DebugMenu.register_toggle(DEBUG_SECTION, "Desenhar caminho dos NPCs", _debug_set_draw_paths, _draw_paths)


# [DEBUG] Sugestões de autocomplete do console: os ids do roster.
func _debug_npc_suggestions() -> PackedStringArray:
	return roster.get_ids()


# [DEBUG] Força a emoção vigente de um NPC. É o que permite revisar as seis rotinas de um NPC em
# dois minutos, sem esperar o sistema de emoção existir.
func _debug_force_emotion(id: String, slot_index: int) -> void:
	set_emotion_slot(StringName(id), slot_index)


# [DEBUG] Força todo mundo a se comportar como dia de trabalho ou de folga, pra dar pra ver a
# rotina de folga numa terça-feira.
func _debug_force_day_type(option_index: int) -> void:
	_day_type_override = option_index - 1
	print("[NPCDirector] - Tipo de dia forçado: %s" % DEBUG_DAY_TYPE_OPTIONS[option_index])
	_apply_routines(false)


# [DEBUG] Traz um NPC até o jogador. Atalho pra não ter que atravessar a cidade pra ver um NPC de
# perto — não muda rotina nenhuma, e no próximo tique ele volta a cumprir a dele.
func _debug_bring_to_player(id: String) -> void:
	var body: NPC = _bodies.get(StringName(id)) as NPC
	if body == null:
		print("[NPCDirector] - \"%s\" não está nesta cena agora" % id)
		return

	# O Player não está em nenhum grupo hoje, então a busca é pela classe na árvore da cena.
	var player: Player = null
	for node: Node in get_tree().current_scene.find_children("*", "CharacterBody2D", true, false):
		if node is Player:
			player = node as Player
			break

	if player == null:
		print("[NPCDirector] - Não achei o Player nesta cena")
		return

	body.snap_to(player.global_position)
	print("[NPCDirector] - \"%s\" trazido até o Player" % id)


# [DEBUG] Lista, pra cada NPC do roster, a emoção vigente, a rotina que valeu e onde ele está agora.
func _debug_list_npcs() -> void:
	print("[NPCDirector] - %d NPCs no roster (dia %d, %s, %s):" % [
		roster.npcs.size(), GameClock.time.get_day(), GameClock.time.format_weekday(),
		GameClock.time.format_clock()])

	for definition: NPCDefinition in roster.npcs:
		if definition == null:
			continue

		var decision: NPCRoutineResolver.Decision = _decisions.get(definition.id) as NPCRoutineResolver.Decision
		if decision == null:
			print("  %s — ainda não resolvido" % definition.id)
			continue

		var here: String = "em cena" if _bodies.has(definition.id) else "fora de cena"
		var entry_text: String = decision.entry.describe() if decision.entry != null else "sem entrada"
		var next_text: String = "—"
		if decision.next_entry != null:
			next_text = "%s (em %d min)" % [decision.next_entry.describe(), decision.minutes_until_next]

		print("  %s — %s, %s, %s" % [
			definition.id,
			definition.describe_slot(get_emotion_slot(definition.id)),
			NPCDefinition.DAY_TYPE_NAMES[decision.day_type],
			here])
		print("      agora:   %s" % entry_text)
		print("      próxima: %s" % next_text)
		if decision.exception != null:
			print("      exceção: %s" % decision.exception.describe())
		if decision.fallback_reason != "":
			print("      fallback: %s" % decision.fallback_reason)


# [DEBUG] Lista os waypoints desta cena. São os nomes exatos que as rotinas devem escrever.
func _debug_list_waypoints() -> void:
	var ids: PackedStringArray = Waypoint.collect_ids(get_tree())
	if ids.is_empty():
		print("[NPCDirector] - Nenhum waypoint nesta cena. Adicione nós Waypoint (Marker2D) no chão.")
		return
	print("[NPCDirector] - %d waypoints nesta cena: %s" % [ids.size(), ", ".join(ids)])


# [DEBUG] Varre o roster inteiro e aponta tudo que está errado na autoria das rotinas: campo
# faltando, horário que nunca é alcançado, cena que não existe, waypoint que não existe nesta cena.
#
# Os dois últimos casos só podem ser conferidos em execução (a cena tem que estar carregada pra
# saber que waypoints ela tem), e é por isso que esta validação vive aqui e não num @tool.
func _debug_validate_routines() -> void:
	var wake_hour: int = GameClock.settings.wake_hour
	var day_length: int = GameClock.settings.day_length_minutes()
	var problems: int = 0

	print("[NPCDirector] - Validando as rotinas de %d NPCs..." % roster.npcs.size())

	for definition: NPCDefinition in roster.npcs:
		if definition == null:
			print("  - Há uma posição vazia no roster")
			problems += 1
			continue

		for issue: String in definition.collect_issues():
			print("  - %s: %s" % [definition.id, issue])
			problems += 1

		for slot: int in NPCDefinition.EmotionSlot.values():
			for day_type: int in NPCDefinition.DayType.values():
				var routine: NPCRoutine = definition.get_routine(slot, day_type)
				if routine == null:
					continue

				var label: String = "%s %s/%s" % [definition.id,
					NPCDefinition.SLOT_NAMES[slot], NPCDefinition.DAY_TYPE_NAMES[day_type]]
				for issue: String in routine.collect_issues():
					print("  - %s: %s" % [label, issue])
					problems += 1
				problems += _validate_entries(label, routine, wake_hour, day_length)
				problems += _validate_exceptions(definition, label, routine, wake_hour, day_length)

	if problems == 0:
		print("  Nenhum problema encontrado.")
	else:
		print("  %d problemas encontrados." % problems)


# [DEBUG] Confere as entradas de uma rotina contra o mundo de verdade. Devolve quantos problemas
# achou.
func _validate_entries(label: String, routine: NPCRoutine, wake_hour: int, day_length: int) -> int:
	var problems: int = 0

	for entry: NPCRoutineEntry in routine.entries:
		if entry == null or entry.scene_path == "":
			continue

		if not ResourceLoader.exists(entry.scene_path):
			print("  - %s: a cena \"%s\" (%s) não existe" % [label, entry.scene_path, entry.format_clock()])
			problems += 1

		# Horário depois do fim do dia jogável: o jogador nunca vive esse instante, então a entrada
		# só vale como "onde ele passou a noite" e nunca é vista acontecendo.
		if entry.get_minutes_into_day(wake_hour) >= day_length:
			print("  - %s: a entrada das %s cai depois do fim do dia jogável e nunca é alcançada" % [
				label, entry.format_clock()])
			problems += 1

		# Waypoint só pode ser conferido na cena em que ele deveria existir.
		if _is_current_scene(entry.scene_path) and Waypoint.find(get_tree(), entry.waypoint) == null:
			print("  - %s: o waypoint \"%s\" (%s) não existe nesta cena" % [
				label, entry.waypoint, entry.format_clock()])
			problems += 1

	return problems


# [DEBUG] Confere as exceções de uma rotina contra o mundo de verdade, do mesmo jeito que
# _validate_entries confere as entradas: faixa que o jogador nunca vive, cena que não existe, waypoint
# que não existe nesta cena. O que dá pra conferir sem o jogo rodando (ronda sem pontos, faixas que se
# sobrepõem) já saiu do NPCRoutine.collect_issues. Devolve quantos problemas achou.
func _validate_exceptions(definition: NPCDefinition, label: String, routine: NPCRoutine, wake_hour: int,
		day_length: int) -> int:
	var problems: int = 0

	for exception: NPCRoutineException in routine.exceptions:
		if exception == null:
			continue

		problems += _validate_patrol_walk(definition, label, routine, exception, wake_hour)

		# Faixa depois do fim do dia jogável: o jogador já apagou, então a exceção nunca é vista.
		if not exception.overlaps_playable_day(wake_hour, day_length):
			print("  - %s: a faixa da exceção (%s) cai depois do fim do dia jogável e nunca é alcançada" % [
				label, exception.describe_window()])
			problems += 1

		# Uma cena que não existe é um problema só, mesmo que vários pontos da exceção morem nela.
		var missing_scenes: Dictionary = {}

		for place: NPCRoutineEntry in exception.get_places():
			if place.scene_path == "":
				continue

			if not ResourceLoader.exists(place.scene_path):
				if not missing_scenes.has(place.scene_path):
					missing_scenes[place.scene_path] = true
					print("  - %s: a cena \"%s\" da exceção (%s) não existe" % [
						label, place.scene_path, exception.describe_window()])
					problems += 1
				continue

			if _is_current_scene(place.scene_path) and Waypoint.find(get_tree(), place.waypoint) == null:
				print("  - %s: o waypoint \"%s\" da exceção (%s) não existe nesta cena" % [
					label, place.waypoint, exception.describe_window()])
				problems += 1

	return problems


# [DEBUG] Confere se uma ronda dá tempo de passar por todos os pontos CONTANDO a caminhada. O
# NPCPatrol.collect_issues faz a mesma conta com a caminhada zerada (roda no editor, que não conhece o
# cenário), então só reclama aqui o que ele não pôde ver: por isso não repete o aviso quando ele já
# apontou. Só confere ronda desta cena, porque só nela os waypoints existem. Devolve 0 ou 1 problema.
func _validate_patrol_walk(definition: NPCDefinition, label: String, routine: NPCRoutine,
		exception: NPCRoutineException, wake_hour: int) -> int:
	var patrol: NPCPatrol = exception as NPCPatrol
	if patrol == null or patrol.waypoints.size() < 2 or not _is_current_scene(patrol.scene_path):
		return 0
	if patrol.count_visited_points(null) < patrol.waypoints.size():
		return 0

	var ordered: Array[NPCRoutineEntry] = NPCRoutineResolver.sorted_entries(routine, wake_hour)
	var travel: NPCRoutineException.TravelTimes = NPCRoutineResolver.window_travel(
		patrol, ordered, wake_hour, _get_travel(definition))
	var visited: int = patrol.count_visited_points(travel)
	if visited >= patrol.waypoints.size():
		return 0

	print("  - %s: contando o tempo de caminhada, a ronda (%s) só passa pelos %d primeiros pontos de %d" % [
		label, patrol.describe_window(), visited, patrol.waypoints.size()])
	return 1


# [DEBUG] Liga/desliga o desenho do caminho de todos os NPCs em cena, inclusive dos que nascerem
# depois.
func _debug_set_draw_paths(enabled: bool) -> void:
	_draw_paths = enabled
	for body: Variant in _bodies.values():
		(body as NPC).draw_path = enabled


# [DEBUG] Roda o autoteste da resolução de rotinas (as exceções incluídas) e imprime o relatório. É a
# mesma coisa que o script de linha de comando tests/run_npc_routine_self_test.gd faz, sem sair do jogo.
func _debug_run_self_test() -> void:
	var self_test: NPCRoutineSelfTest = NPCRoutineSelfTest.new()
	self_test.run()
	print(self_test.report())
