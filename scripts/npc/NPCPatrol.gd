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
## COMO ELE ANDA: começa no primeiro ponto quando a faixa abre, fica o tempo combinado, segue pro
## seguinte e, ao chegar no último, volta pro primeiro — até a faixa acabar. Para ida e volta numa rua,
## repita os pontos na lista (A, B, C, B). O ponto em que ele está é uma conta do relógio (minutos
## desde o começo da faixa ÷ tempo por ponto), e não um estado guardado: a ronda é idêntica todo dia,
## que é justamente o que o jogador aprende observando.
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

## Quanto tempo ele fica em cada ponto antes de seguir pro próximo, em minutos de jogo. O passo é 10
## porque o relógio anuncia a passagem do tempo a cada 10 minutos: com 25, ele trocaria de ponto às
## 08:25 mas só ficaria sabendo às 08:30.
@export_range(10, 480, 10, "suffix:min") var dwell_minutes: int = 30:
	set(value):
		dwell_minutes = value
		emit_changed()

## Espaço para funções personalizadas

# A parada em que o NPC está `elapsed_minutes` depois do começo da faixa: o ponto de número
# (elapsed ÷ tempo por ponto), dando a volta na lista. O horário da entrada devolvida é o de quando ele
# CHEGOU nesse ponto, que é o que o menu de debug mostra em "agora".
func get_stop(elapsed_minutes: int) -> NPCRoutineEntry:
	if scene_path == "" or waypoints.is_empty() or dwell_minutes <= 0:
		return null

	@warning_ignore("integer_division")
	var step: int = elapsed_minutes / dwell_minutes
	var point: StringName = waypoints[step % waypoints.size()]
	if point == &"":
		return null

	return NPCRoutineEntry.from_clock_minutes(
		get_start_clock_minutes() + step * dwell_minutes, scene_path, point)


# Quanto falta pra ele seguir pro próximo ponto: o resto do tempo que ele deve ficar no atual.
func get_minutes_until_stop_change(elapsed_minutes: int) -> int:
	if dwell_minutes <= 0:
		return 0
	return dwell_minutes - (elapsed_minutes % dwell_minutes)


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

	# O ponto de número k só começa k × tempo por ponto depois da abertura da faixa. Quando a faixa
	# fecha antes disso, o ponto nunca é visitado — o mesmo tipo de erro que o "Validar rotinas" aponta
	# numa entrada depois do fim do dia jogável.
	var length: int = get_length_minutes()
	var reachable: int = ceili(float(length) / float(dwell_minutes))
	if waypoints.size() > 1 and reachable < waypoints.size():
		issues.append(("A faixa dura %d min e ele fica %d min em cada ponto, então só passa pelos %d "
			+ "primeiros pontos: os outros nunca são visitados.") % [length, dwell_minutes, reachable])

	return issues


# A ronda numa linha: faixa, cena, pontos na ordem e tempo em cada um. É o que o resumo da rotina e o
# "Listar NPCs" mostram.
func describe() -> String:
	var scene_name: String = scene_path.get_file().get_basename() if scene_path != "" else "(sem cena)"
	var route: PackedStringArray = []
	for point: StringName in waypoints:
		route.append(String(point) if point != &"" else "(vazio)")
	var route_text: String = " -> ".join(route) if not route.is_empty() else "(sem pontos)"
	return "%s  ronda em %s: %s (%d min em cada, em ciclo)" % [
		describe_window(), scene_name, route_text, dwell_minutes]
