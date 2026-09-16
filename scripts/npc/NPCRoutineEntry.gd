## NPCRoutineEntry - uma linha da rotina de um NPC: [horário, cena, waypoint].
##
## Lê-se "a partir deste horário, este NPC deve estar nesta cena, neste ponto". A entrada não diz
## quanto tempo ele fica: ele fica até a entrada seguinte — que é o que torna a rotina uma lista
## curta em vez de uma agenda com início e fim em cada linha.
##
## COMO USAR: preencha os quatro campos no Inspector. A cena é escolhida num seletor de arquivo, e
## o waypoint é o NOME de um nó Waypoint (Marker2D) dentro daquela cena — o menu de debug tem
## "Listar waypoints da cena" pra você conferir o nome exato sem sair do jogo.
##
## SOBRE O HORÁRIO: é relógio de parede (o que o design pensa), 00:00 a 23:55. A conversão pro
## minuto interno do dia de jogo acontece num lugar só, em get_minutes_into_day(), porque no
## HopeFarm o minuto 0 do dia é a HORA DE ACORDAR e não a meia-noite (ver GameTime.gd). Duas
## consequências que valem saber:
##
##   - Uma entrada à 01:00, com wake_hour 06:00, é de madrugada no FIM do mesmo dia de jogo.
##   - Uma entrada às 04:00, com o dia acabando às 02:00, nunca é alcançada. O menu de debug
##     ("Validar rotinas") aponta esses casos.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name NPCRoutineEntry
extends Resource

## Espaço para constantes

const MINUTES_PER_HOUR: int = 60
const MINUTES_PER_DAY: int = 1440

## Espaço para variáveis exportadas

## Hora do relógio de parede em que esta entrada passa a valer.
@export_range(0, 23, 1, "suffix:h") var hour: int = 8:
	set(value):
		hour = value
		emit_changed()

## Minuto da hora. O passo é 5 porque o relógio anuncia a passagem do tempo a cada 10 minutos de
## jogo (GameClock.TICK_MINUTES): um horário em 14:03 só passa a valer no anúncio das 14:10.
@export_range(0, 55, 5, "suffix:min") var minute: int = 0:
	set(value):
		minute = value
		emit_changed()

## Cena em que o NPC deve estar. Se não for a cena onde o jogador está, o NPC simplesmente não
## existe como nó — a rotina continua valendo, e ele reaparece no lugar certo quando o jogador
## chegar naquela cena (ver docs/sistema_de_npc.md, "A posição é derivada").
@export_file("*.tscn") var scene_path: String = "":
	set(value):
		scene_path = value
		emit_changed()

## Nome do nó Waypoint dentro daquela cena.
@export var waypoint: StringName = &"":
	set(value):
		waypoint = value
		emit_changed()

## Espaço para funções personalizadas

# Minuto do relógio de parede (0 = 00:00).
func get_clock_minutes() -> int:
	return hour * MINUTES_PER_HOUR + minute


# Minuto do DIA DE JOGO em que esta entrada começa, contado da hora de acordar. É a unidade em que
# o GameClock trabalha (GameClock.time.get_minutes_into_day()), e por isso a única que serve pra
# comparar entrada com relógio.
func get_minutes_into_day(wake_hour: int) -> int:
	return posmod(get_clock_minutes() - wake_hour * MINUTES_PER_HOUR, MINUTES_PER_DAY)


# "08:30". Formato de log e de Inspector — texto de ferramenta, não de jogador, então não passa
# pelo CSV de localização.
func format_clock() -> String:
	return "%02d:%02d" % [hour, minute]


# Uma linha legível da entrada, usada no resumo do Inspector e no menu de debug.
func describe() -> String:
	var scene_name: String = scene_path.get_file().get_basename() if scene_path != "" else "(sem cena)"
	var point: String = String(waypoint) if waypoint != &"" else "(sem waypoint)"
	return "%s  %s / %s" % [format_clock(), scene_name, point]
