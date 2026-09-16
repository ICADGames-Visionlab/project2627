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

	# Onde ele deveria estar agora. null = rotina vazia; nesse caso o NPC fica onde está.
	var entry: NPCRoutineEntry

	# A próxima entrada e em quantos minutos de jogo ela chega. Só o menu de debug usa — o sistema
	# em si não precisa saber o futuro, ele só resolve de novo quando o relógio anda.
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
	if ordered.is_empty():
		return decision

	var index: int = current_index(ordered, minutes_into_day, wake_hour)
	decision.entry = ordered[index]

	var next_index: int = (index + 1) % ordered.size()
	decision.next_entry = ordered[next_index]
	decision.minutes_until_next = _minutes_until(ordered[next_index], minutes_into_day, wake_hour)

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


# Quantos minutos de jogo faltam pra uma entrada, dando a volta no dia quando ela já passou.
static func _minutes_until(entry: NPCRoutineEntry, minutes_into_day: int, wake_hour: int) -> int:
	var target: int = entry.get_minutes_into_day(wake_hour)
	if target >= minutes_into_day:
		return target - minutes_into_day
	return target + NPCRoutineEntry.MINUTES_PER_DAY - minutes_into_day
