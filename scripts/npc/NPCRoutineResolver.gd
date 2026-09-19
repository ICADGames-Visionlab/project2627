## NPCRoutineResolver - a calculadora do sistema de NPC: dado um NPC, a emoção vigente e o
## relógio, diz ONDE ele deveria estar agora.
##
## Não é um Node, não emite nada e não consome delta — são funções estáticas puras. Existe separado
## do NPCDirector pela mesma razão que o GameTime existe separado do GameClock: a parte que dá bug
## num sistema de rotina é a aritmética de horário, e aqui ela pode ser conferida sem rodar o jogo
## (ver docs/sistema_de_npc.md, "Como testar").
##
## COMO USAR:
##
##     var decision: NPCRoutineResolver.Decision = NPCRoutineResolver.resolve(
##         definition, slot, GameClock.time.get_weekday(),
##         GameClock.time.get_minutes_into_day(), GameClock.settings.wake_hour)
##     print(decision.entry.waypoint)
##
## A IDEIA CENTRAL: a posição do NPC não é um estado guardado em paralelo ao relógio — é uma função
## do relógio. "Entrada vigente" é a última entrada cujo horário já passou. Como isso é recalculado
## a qualquer momento, pular o tempo (advance no menu de debug, dormir, carregar um save) e entrar
## numa cena horas depois funcionam todos pelo mesmo caminho, sem simulação em background e sem
## nada pra dessincronizar.
##
## EXCEÇÕES: se a rotina tem uma exceção valendo neste instante (ver NPCRoutineException — a ronda do
## policial, por exemplo), é ela que diz onde o NPC está, e a entrada vigente vira a parada dela. O
## resto do sistema não percebe: a exceção fala a mesma língua das entradas. Rotina sem exceção
## resolve exatamente como resolvia antes de elas existirem.
class_name NPCRoutineResolver
extends RefCounted

## Espaço para constantes

const MINUTES_PER_HOUR: int = 60

## Espaço para classes internas

# O resultado de uma resolução. Existe como classe, e não como Dictionary, pra o chamador ter
# tipagem e autocomplete — e porque o menu de debug mostra estes mesmos campos na listagem.
class Decision extends RefCounted:
	# Se hoje é dia de trabalho ou de folga para este NPC (um NPCDefinition.DayType).
	var day_type: int = NPCDefinition.DayType.WORKDAY

	# A rotina que valeu, já depois da cadeia de fallback. null = o NPC não tem nem rotina neutra.
	var routine: NPCRoutine

	# Qual slot a rotina veio, depois do fallback. Diferente do slot pedido significa que o design
	# não preencheu aquele campo (ver fallback_reason).
	var slot_used: int = NPCDefinition.EmotionSlot.NEUTRAL

	# Vazio quando a rotina pedida existia; senão, explica em uma linha o que foi usado no lugar.
	var fallback_reason: String = ""

	# Onde ele deveria estar agora. null = rotina vazia; nesse caso o NPC fica onde está. Quando uma
	# exceção está valendo, é a parada dela (uma entrada avulsa), e não uma linha da rotina.
	var entry: NPCRoutineEntry

	# A exceção que assumiu o NPC neste instante (a ronda, por exemplo), ou null quando quem manda é a
	# rotina padrão.
	var exception: NPCRoutineException

	# A próxima mudança de lugar e em quantos minutos de jogo ela chega. Só o menu de debug usa — o
	# sistema em si não precisa saber o futuro, ele só resolve de novo quando o relógio anda.
	var next_entry: NPCRoutineEntry
	var minutes_until_next: int = 0

## Espaço para funções personalizadas

# O ponto de entrada: cruza NPC + emoção vigente + relógio e devolve a decisão completa.
static func resolve(definition: NPCDefinition, slot: int, weekday: int, minutes_into_day: int,
		wake_hour: int) -> Decision:
	var decision: Decision = Decision.new()
	if definition == null:
		return decision

	decision.day_type = resolve_day_type(definition, weekday)
	decision.routine = resolve_routine(definition, slot, decision.day_type, decision)
	if decision.routine == null:
		return decision

	var ordered: Array[NPCRoutineEntry] = sorted_entries(decision.routine, wake_hour)
	decision.entry = entry_at(decision.routine, ordered, minutes_into_day, wake_hour, decision)
	if decision.entry == null:
		return decision

	# A próxima entrada é o que estará valendo quando a decisão mudar, e não "a linha seguinte da
	# rotina": com uma ronda em andamento, a próxima mudança é a próxima parada dela.
	decision.minutes_until_next = minutes_until_change(
		decision.routine, ordered, minutes_into_day, wake_hour, decision.exception)
	var change_minute: int = minutes_into_day + decision.minutes_until_next
	decision.next_entry = _starting_at(
		entry_at(decision.routine, ordered, change_minute, wake_hour), change_minute, wake_hour)

	return decision


# Dia de trabalho ou de folga, segundo os dias marcados no próprio NPC.
static func resolve_day_type(definition: NPCDefinition, weekday: int) -> int:
	if definition.is_workday(weekday):
		return NPCDefinition.DayType.WORKDAY
	return NPCDefinition.DayType.DAY_OFF


# A rotina que vale, com a cadeia de fallback:
#
#     (slot pedido, tipo de dia)  ->  (neutro, tipo de dia)  ->  (neutro, trabalho)  ->  null
#
# É o mesmo princípio das chaves de agenda do Stardew Valley: sempre existe um degrau abaixo, e o
# último degrau é o neutro de dia de trabalho. Assim uma emoção que o design ainda não detalhou faz
# o NPC se comportar como sempre, em vez de ele parar no lugar sem rotina nenhuma.
#
# O parâmetro decision é opcional e serve pra registrar O QUE foi usado, pro log e pro menu de
# debug poderem dizer "caiu no fallback" em vez de fingir que estava tudo preenchido.
static func resolve_routine(definition: NPCDefinition, slot: int, day_type: int,
		decision: Decision = null) -> NPCRoutine:
	var requested: NPCRoutine = definition.get_routine(slot, day_type)
	if requested != null:
		if decision != null:
			decision.slot_used = slot
		return requested

	var neutral_same_day: NPCRoutine = definition.get_routine(NPCDefinition.EmotionSlot.NEUTRAL, day_type)
	if neutral_same_day != null:
		if decision != null:
			decision.slot_used = NPCDefinition.EmotionSlot.NEUTRAL
			decision.fallback_reason = "sem rotina %s/%s, usando neutro/%s" % [
				NPCDefinition.SLOT_NAMES[slot], NPCDefinition.DAY_TYPE_NAMES[day_type],
				NPCDefinition.DAY_TYPE_NAMES[day_type]]
		return neutral_same_day

	var last_resort: NPCRoutine = definition.get_routine(
		NPCDefinition.EmotionSlot.NEUTRAL, NPCDefinition.DayType.WORKDAY)
	if decision != null:
		decision.slot_used = NPCDefinition.EmotionSlot.NEUTRAL
		if last_resort != null:
			decision.fallback_reason = "sem rotina %s/%s nem neutro/%s, usando neutro/trabalho" % [
				NPCDefinition.SLOT_NAMES[slot], NPCDefinition.DAY_TYPE_NAMES[day_type],
				NPCDefinition.DAY_TYPE_NAMES[day_type]]
		else:
			decision.fallback_reason = "nenhuma rotina preenchida"
	return last_resort


# A entrada em vigor num instante: a parada da exceção que estiver valendo ou, sem nenhuma, a última
# entrada da rotina padrão cujo horário já passou. Devolve null quando não há de onde tirar (rotina sem
# entrada executável e sem exceção valendo).
#
# Serve também pra olhar pro FUTURO, e é por isso que é pública: o menu de debug pergunta "onde ele
# estará quando isto mudar?" com o mesmo código que decide onde ele está agora, em vez de uma segunda
# implementação que poderia divergir da primeira.
#
# O parâmetro decision é opcional e serve pra registrar QUAL exceção mandou, pro log e pro menu de
# debug poderem dizer "em ronda" — o mesmo esquema do resolve_routine.
static func entry_at(routine: NPCRoutine, ordered: Array[NPCRoutineEntry], minutes_into_day: int,
		wake_hour: int, decision: Decision = null) -> NPCRoutineEntry:
	# O instante pode passar de um dia quando é o futuro (agora + minutos até a próxima mudança).
	var minute: int = posmod(minutes_into_day, NPCRoutineEntry.MINUTES_PER_DAY)

	# Exceção que está com a faixa aberta mas não sabe dizer onde o NPC está (ronda sem ponto, por
	# exemplo) é ignorada: a rotina padrão vale, em vez de o NPC ficar sem lugar nenhum.
	for exception: NPCRoutineException in routine.exceptions:
		if exception == null or not exception.is_active_at(minute, wake_hour):
			continue
		var stop: NPCRoutineEntry = exception.get_stop(exception.get_elapsed_minutes(minute, wake_hour))
		if stop != null:
			if decision != null:
				decision.exception = exception
			return stop

	if ordered.is_empty():
		return null
	return ordered[current_index(ordered, minute, wake_hour)]


# Em quantos minutos a decisão de um NPC muda, contados do instante dado.
#
# Com uma exceção valendo (o parâmetro active), quem manda é ela: a próxima parada ou o fim da faixa.
# As entradas da rotina padrão que caírem no meio da faixa não mudam nada visível, então não contam.
# Sem exceção valendo, é o que vier antes entre a próxima entrada da rotina e o começo da faixa de
# alguma exceção.
#
# Só o menu de debug usa (o sistema em si resolve de novo quando o relógio anda), mas precisa ser
# verdade: uma "próxima mudança" que ignorasse a ronda mentiria justamente na ferramenta que o design
# usa pra conferir a rotina.
static func minutes_until_change(routine: NPCRoutine, ordered: Array[NPCRoutineEntry],
		minutes_into_day: int, wake_hour: int, active: NPCRoutineException = null) -> int:
	if active != null:
		return active.get_minutes_until_change(minutes_into_day, wake_hour)

	var soonest: int = 0
	if not ordered.is_empty():
		var next_index: int = (current_index(ordered, minutes_into_day, wake_hour) + 1) % ordered.size()
		soonest = _minutes_until(ordered[next_index], minutes_into_day, wake_hour)

	for exception: NPCRoutineException in routine.exceptions:
		if exception == null or not exception.is_executable():
			continue
		var until_change: int = exception.get_minutes_until_change(minutes_into_day, wake_hour)
		# Zero não é uma mudança: é o "próxima entrada = a mesma" de uma rotina de entrada única.
		if until_change > 0 and (soonest <= 0 or until_change < soonest):
			soonest = until_change

	return soonest


# As entradas ordenadas pelo minuto do DIA DE JOGO (não pelo relógio de parede): com wake_hour 6,
# uma entrada à 01:00 vem DEPOIS de uma das 22:00, porque ela é de madrugada, no fim do mesmo dia.
# Entradas vazias ou sem cena/waypoint são descartadas aqui — o resto do sistema pode confiar que
# toda entrada que sai daqui é executável.
static func sorted_entries(routine: NPCRoutine, wake_hour: int) -> Array[NPCRoutineEntry]:
	var ordered: Array[NPCRoutineEntry] = []
	for entry: NPCRoutineEntry in routine.entries:
		if entry != null and entry.scene_path != "" and entry.waypoint != &"":
			ordered.append(entry)

	ordered.sort_custom(func(a: NPCRoutineEntry, b: NPCRoutineEntry) -> bool:
		return a.get_minutes_into_day(wake_hour) < b.get_minutes_into_day(wake_hour))
	return ordered


# Índice da entrada vigente: a última cujo horário já passou.
#
# Se nenhuma passou ainda (é de manhã e a primeira entrada é às 08:00), a vigente é a ÚLTIMA do dia
# — é onde ele passou a noite. Daí a convenção de autoria: a última entrada do dia é a casa dele.
static func current_index(ordered: Array[NPCRoutineEntry], minutes_into_day: int, wake_hour: int) -> int:
	var index: int = ordered.size() - 1
	for i: int in ordered.size():
		if ordered[i].get_minutes_into_day(wake_hour) <= minutes_into_day:
			index = i
		else:
			break
	return index


# A mesma entrada, mas datada no instante em que o NPC chega nela. Quase sempre é a própria entrada:
# a mudança acontece no horário dela. A exceção é quando uma faixa acaba e a rotina padrão reassume —
# a entrada que volta a valer começou horas ANTES de a ronda abrir, e o debug precisa dizer "às 17:00",
# não "às 07:30". Devolve null se a entrada for null.
static func _starting_at(entry: NPCRoutineEntry, minutes_into_day: int, wake_hour: int) -> NPCRoutineEntry:
	if entry == null:
		return null

	var minute: int = posmod(minutes_into_day, NPCRoutineEntry.MINUTES_PER_DAY)
	if entry.get_minutes_into_day(wake_hour) == minute:
		return entry

	var clock_minutes: int = minute + wake_hour * MINUTES_PER_HOUR
	return NPCRoutineEntry.from_clock_minutes(clock_minutes, entry.scene_path, entry.waypoint)


# Quantos minutos de jogo faltam pra uma entrada, dando a volta no dia quando ela já passou.
static func _minutes_until(entry: NPCRoutineEntry, minutes_into_day: int, wake_hour: int) -> int:
	var target: int = entry.get_minutes_into_day(wake_hour)
	if target >= minutes_into_day:
		return target - minutes_into_day
	return target + NPCRoutineEntry.MINUTES_PER_DAY - minutes_into_day
