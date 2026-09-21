## NPCPatrol - a ronda: uma exceção de rotina em que o NPC circula por uma lista de pontos, ficando um
## tempo em cada um, durante uma faixa de horário. É o caso do policial.
##
## COMO USAR: crie o recurso na lista "Exceptions" de uma NPCRoutine (Add Element, depois "New
## NPCPatrol"), ou salve num .tres em res://resources/npcs/rondas/ pra várias rotinas usarem a mesma
## ronda — o policial faz a mesma ronda em mais de uma rotina, e copiar as paradas significaria corrigir
## duas vezes depois. Preencha:
##
##   - a faixa de horário (herdada de NPCRoutineException);
##   - a cena: uma só, a ronda acontece dentro dela;
##   - os pontos, na ordem em que ele passa — o nome de um Waypoint da cena, o mesmo campo "waypoint"
##     de uma entrada de rotina;
##   - quanto tempo ele fica em cada ponto.
##
## COMO ELE ANDA: vai ao primeiro ponto quando a faixa abre, fica PARADO o tempo combinado, segue pro
## seguinte e, ao chegar no último, volta pro primeiro — até a faixa acabar. Para ida e volta numa rua,
## repita os pontos na lista (A, B, C, B).
##
## O TEMPO PARADO CONTA A PARTIR DA CHEGADA: cada parada dura a caminhada até o ponto MAIS o tempo
## parado. A caminhada não é medida com o NPC andando, é calculada (caminho do Pathfinder ÷ velocidade do
## NPC, pela conta do movimento, feita pelo NPCDirector e entregue no TravelTimes), então o ponto em que
## ele está continua sendo uma conta do relógio e não um estado guardado: a ronda é idêntica todo dia,
## que é justamente o que o jogador aprende observando, e pular o tempo ou voltar à cena funciona sem
## simular nada. A caminhada é arredondada pra cima em blocos de 10 minutos (o passo do relógio), então
## ele nunca fica parado MENOS que o combinado, e às vezes um pouco mais (até 9 min).
##
## UMA CENA SÓ: circular pela cidade é uma ronda. Sair dela e entrar na padaria já é trabalho de uma
## entrada de rotina, que é o que a rotina padrão faz melhor.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name NPCPatrol
extends NPCRoutineException

## Espaço para constantes

# De quantos em quantos minutos de jogo o relógio anuncia a passagem do tempo (GameClock.TICK_MINUTES).
# Duplicado de propósito: este script roda no editor, onde o Autoload GameClock não existe.
const TICK_MINUTES: int = 10

## Espaço para classes internas

# Onde a ronda está num instante: o número da parada (0 é a primeira, e a conta segue pelas voltas), qual
# ponto da lista ela é, e o intervalo [start, end) da faixa em que o NPC é mandado pra lá — caminha, chega
# e fica parado. Existe pra get_stop e get_minutes_until_stop_change responderem da MESMA conta.
class PatrolStep extends RefCounted:
	var step: int = 0
	var index: int = 0
	var start: int = 0
	var end: int = 0

## Espaço para variáveis exportadas

@export_group("Ronda")

## Cena em que a ronda acontece.
@export_file("*.tscn") var scene_path: String = "":
	set(value):
		scene_path = value
		emit_changed()

## Os pontos da ronda, na ordem em que ele passa. Cada item é o nome de um Waypoint da cena (o menu de
## debug tem "Listar waypoints da cena" pra conferir o nome exato). Chegou no último, volta pro
## primeiro; repetir um ponto na lista faz ele passar por lá mais de uma vez por volta.
@export var waypoints: Array[StringName] = []:
	set(value):
		waypoints = value
		emit_changed()

## Quanto tempo ele fica PARADO em cada ponto antes de seguir pro próximo, em minutos de jogo, contado a
## partir da chegada: a caminhada até o ponto não entra nessa conta, ela é somada por fora. O passo é 10
## porque o relógio anuncia a passagem do tempo a cada 10 minutos: com 25, ele trocaria de ponto às
## 08:25 mas só ficaria sabendo às 08:30.
@export_range(10, 480, 10, "suffix:min") var dwell_minutes: int = 30:
	set(value):
		dwell_minutes = value
		emit_changed()

## Espaço para funções personalizadas

# A parada em que o NPC está `elapsed_minutes` depois do começo da faixa, dando a volta na lista de
# pontos. O horário da entrada devolvida é o de quando ele é MANDADO pra lá (o começo da caminhada), como
# o de qualquer entrada de rotina: "a partir daqui, ele deve estar lá". É o que o menu de debug mostra em
# "agora".
func get_stop(elapsed_minutes: int, travel: NPCRoutineException.TravelTimes) -> NPCRoutineEntry:
	if scene_path == "" or waypoints.is_empty() or dwell_minutes <= 0:
		return null

	var located: PatrolStep = _locate(elapsed_minutes, travel)
	var point: StringName = waypoints[located.index]
	if point == &"":
		return null

	return NPCRoutineEntry.from_clock_minutes(get_start_clock_minutes() + located.start, scene_path, point)


# Quanto falta pra ele ser mandado pro próximo ponto: o fim da parada atual, que é a chegada mais o
# tempo parado.
func get_minutes_until_stop_change(elapsed_minutes: int, travel: NPCRoutineException.TravelTimes) -> int:
	if waypoints.is_empty() or dwell_minutes <= 0:
		return 0
	return _locate(elapsed_minutes, travel).end - elapsed_minutes


# Quantos pontos DIFERENTES da lista ele chega a visitar dentro da faixa. Com travel null a caminhada
# vale zero (é a conta do collect_issues, que roda no editor e não conhece o cenário); com o TravelTimes de
# verdade é a conta do "Validar rotinas", que sabe o quanto ele anda entre um ponto e outro.
func count_visited_points(travel: NPCRoutineException.TravelTimes) -> int:
	if waypoints.is_empty() or dwell_minutes <= 0:
		return 0

	var length: int = get_length_minutes()
	var seen: Dictionary = {}
	var elapsed: int = 0
	while elapsed < length and seen.size() < waypoints.size():
		var located: PatrolStep = _locate(elapsed, travel)
		seen[located.index] = true
		elapsed = located.end
	return seen.size()


# A parada de um instante da faixa. Cada parada dura a caminhada até o ponto mais o tempo parado.
#
# A primeira parada caminha desde onde o NPC estava quando a faixa abriu (travel.origin), e todas as
# outras desde o ponto anterior da lista. Depois da primeira a ronda se repete a cada volta completa, na
# ordem 1, 2, ..., N-1, 0 (o ponto 0 volta a ser parada com a caminhada vinda do último), e é por isso
# que a busca soma as durações de uma volta uma vez só e usa divisão e resto pras voltas seguintes.
func _locate(elapsed_minutes: int, travel: NPCRoutineException.TravelTimes) -> PatrolStep:
	var count: int = waypoints.size()
	var located: PatrolStep = PatrolStep.new()

	var first_duration: int = dwell_minutes
	if travel != null:
		first_duration += travel.minutes_from_origin(scene_path, waypoints[0])
	if elapsed_minutes < first_duration:
		located.end = first_duration
		return located

	var durations: PackedInt32Array = PackedInt32Array()
	var lap_length: int = 0
	for offset: int in count:
		var index: int = (1 + offset) % count
		var duration: int = dwell_minutes
		if travel != null:
			duration += travel.minutes(waypoints[posmod(index - 1, count)], waypoints[index])
		durations.append(duration)
		lap_length += duration

	var since_first: int = elapsed_minutes - first_duration
	@warning_ignore("integer_division")
	var laps: int = since_first / lap_length
	var remaining: int = since_first % lap_length
	var start: int = first_duration + laps * lap_length
	for offset: int in count:
		if remaining < durations[offset]:
			located.step = 1 + laps * count + offset
			located.index = (1 + offset) % count
			located.start = start
			located.end = start + durations[offset]
			return located
		remaining -= durations[offset]
		start += durations[offset]

	return located


# Os pontos da ronda como entradas avulsas, sem repetir os que a lista cita mais de uma vez.
func get_places() -> Array[NPCRoutineEntry]:
	var places: Array[NPCRoutineEntry] = []
	var seen: Dictionary = {}
	for point: StringName in waypoints:
		if point == &"" or seen.has(point):
			continue
		seen[point] = true
		places.append(NPCRoutineEntry.from_clock_minutes(get_start_clock_minutes(), scene_path, point))
	return places


# Problemas da ronda, além dos da faixa: o que falta (cena, pontos), o que não faz sentido (um ponto só,
# tempo fora do passo do relógio) e o que a faixa não dá tempo de cumprir. Aparecem no resumo da rotina
# que usa a ronda e no "Validar rotinas".
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = super()

	if scene_path == "":
		issues.append("A ronda não aponta cena.")
	if waypoints.is_empty():
		issues.append("A ronda não tem nenhum ponto.")
	for index: int in waypoints.size():
		if waypoints[index] == &"":
			issues.append("O ponto %d da ronda está vazio (falta escrever o waypoint)." % index)
	if waypoints.size() == 1:
		issues.append("A ronda tem um ponto só, então ele nunca sai do lugar. "
			+ "Para ficar parado numa faixa de horário, use uma entrada da rotina.")

	if dwell_minutes <= 0:
		issues.append("O tempo em cada ponto precisa ser maior que zero.")
		return issues
	if dwell_minutes % TICK_MINUTES != 0:
		issues.append(("O tempo em cada ponto (%d min) não é múltiplo de %d: o relógio só anuncia a passagem "
			+ "do tempo a cada %d minutos, então ele trocaria de ponto fora do horário marcado.")
			% [dwell_minutes, TICK_MINUTES, TICK_MINUTES])

	# Ponto que a faixa fecha antes de dar tempo de visitar nunca é visitado — o mesmo tipo de erro que o
	# "Validar rotinas" aponta numa entrada depois do fim do dia jogável. Aqui a caminhada vale zero (o
	# editor não conhece o cenário), então é o MÍNIMO de pontos que ficam de fora; o "Validar rotinas" em
	# jogo refaz a conta com o tempo de caminhada de verdade.
	var visited: int = count_visited_points(null)
	if waypoints.size() > 1 and visited < waypoints.size():
		issues.append(("A faixa dura %d min e ele fica %d min parado em cada ponto, então só passa pelos %d "
			+ "primeiros pontos, sem nem contar a caminhada: os outros nunca são visitados.")
			% [get_length_minutes(), dwell_minutes, visited])

	return issues


# A ronda numa linha: faixa, cena, pontos na ordem e tempo em cada um. É o que o resumo da rotina e o
# "Listar NPCs" mostram.
func describe() -> String:
	var scene_name: String = NPCRoutineEntry.to_scene_path(scene_path).get_file().get_basename() if scene_path != "" else "(sem cena)"
	var route: PackedStringArray = []
	for point: StringName in waypoints:
		route.append(String(point) if point != &"" else "(vazio)")
	var route_text: String = " -> ".join(route) if not route.is_empty() else "(sem pontos)"
	return "%s  ronda em %s: %s (%d min parado em cada ponto, em ciclo)" % [
		describe_window(), scene_name, route_text, dwell_minutes]
