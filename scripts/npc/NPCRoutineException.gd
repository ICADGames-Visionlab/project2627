## NPCRoutineException - uma exceção à rotina padrão: uma FAIXA DE HORÁRIO em que um comportamento
## especial assume o NPC no lugar das entradas [horário, cena, waypoint].
##
## POR QUE EXISTE: a rotina padrão responde "onde ele está?" com UM ponto, que vale até a entrada
## seguinte. Algumas figuras não cabem nesse molde — o policial não FICA em lugar nenhum entre 08:00 e
## 17:00, ele CIRCULA. Esta classe é o espaço da rotina para essas especificidades.
##
## É OPCIONAL: NPCRoutine.exceptions vazio é o normal, e é o que todo NPC comum tem. Uma rotina sem
## exceção se comporta exatamente como se esta classe não existisse.
##
## COMO FUNCIONA: dentro da faixa a exceção manda, e fora dela a rotina padrão volta a valer sozinha
## (o policial termina a ronda e retoma a entrada em que estava). Se duas faixas da mesma rotina se
## sobrepõem, vale a primeira da lista. A exceção continua sendo uma FUNÇÃO DO RELÓGIO, como o resto
## do sistema (ver NPCRoutineResolver): dado o minuto do dia, ela diz onde o NPC está, sem guardar
## estado — então pular o tempo, dormir e carregar um save funcionam sem código nenhum.
##
## ESTA É A CLASSE BASE, e por isso é abstrata: só sabe da faixa de horário. O QUE o NPC faz dentro
## dela é de cada tipo de exceção, e o primeiro é o NPCPatrol (a ronda). Tipo novo (vagar por uma
## área, sumir do mapa, o que o design inventar) é um script novo que estende esta classe e implementa
## get_stop() e get_minutes_until_stop_change() — o resolver, o diretor e as rotinas que já existem não
## mudam.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
@abstract
class_name NPCRoutineException
extends Resource

## Espaço para constantes

# Reaproveitadas do NPCRoutineEntry: a conta de horário existe em uma fonte só.
const MINUTES_PER_HOUR: int = NPCRoutineEntry.MINUTES_PER_HOUR
const MINUTES_PER_DAY: int = NPCRoutineEntry.MINUTES_PER_DAY

## Espaço para variáveis exportadas

@export_group("Faixa de horário")

## Hora do relógio de parede em que a exceção passa a valer.
@export_range(0, 23, 1, "suffix:h") var start_hour: int = 8:
	set(value):
		start_hour = value
		emit_changed()

## Minuto da hora. O passo é 5 pelo mesmo motivo do NPCRoutineEntry: o relógio só anuncia a passagem
## do tempo a cada 10 minutos de jogo.
@export_range(0, 55, 5, "suffix:min") var start_minute: int = 0:
	set(value):
		start_minute = value
		emit_changed()

## Hora do relógio de parede em que a exceção deixa de valer: é o instante em que a rotina padrão
## volta, e ele não faz parte da faixa. Fim menor que o começo atravessa a meia-noite (22:00 até
## 02:00). Fim igual ao começo vale como "o dia inteiro".
@export_range(0, 23, 1, "suffix:h") var end_hour: int = 17:
	set(value):
		end_hour = value
		emit_changed()

## Minuto da hora do fim da faixa.
@export_range(0, 55, 5, "suffix:min") var end_minute: int = 0:
	set(value):
		end_minute = value
		emit_changed()

# Fecha o grupo pra que os campos do tipo de exceção (declarados na subclasse) não caiam dentro dele
# no Inspector.
@export_group("")

## Espaço para funções personalizadas

# [CONTRATO] Onde o NPC está `elapsed_minutes` depois do começo da faixa, escrito como uma entrada de
# rotina cujo horário é o de QUANDO ele chegou ali (ver NPCRoutineEntry.from_clock_minutes). Devolve
# null quando a exceção não sabe dizer (configuração incompleta): nesse caso a rotina padrão vale.
@abstract func get_stop(elapsed_minutes: int) -> NPCRoutineEntry


# [CONTRATO] Daqui a quantos minutos, contados de `elapsed_minutes`, o NPC muda de lugar sem que a
# faixa tenha acabado. Devolve 0 quando ele fica onde está até o fim da faixa.
@abstract func get_minutes_until_stop_change(elapsed_minutes: int) -> int


# Todos os lugares aonde esta exceção pode mandar o NPC, como entradas avulsas, sem repetição. Só o
# "Validar rotinas" usa, pra conferir se cada cena e cada waypoint existem. A base não conhece
# nenhum; cada tipo de exceção devolve os seus.
func get_places() -> Array[NPCRoutineEntry]:
	return []


# Problemas de configuração, uma frase por problema. Mesma ideia do collect_issues das outras classes
# do sistema: o resumo da rotina no Inspector e o "Validar rotinas" mostram a mesma lista. A base não
# tem o que reclamar (toda faixa é válida); cada tipo de exceção acrescenta os seus.
func collect_issues() -> PackedStringArray:
	return PackedStringArray()


# A exceção numa linha, pro resumo do Inspector e pro menu de debug. Cada tipo de exceção acrescenta o
# que faz; a base só diz quando.
func describe() -> String:
	return describe_window()


# "08:00-17:00", ou "o dia inteiro".
func describe_window() -> String:
	if _get_raw_length() == 0:
		return "o dia inteiro"
	return "%02d:%02d-%02d:%02d" % [start_hour, start_minute, end_hour, end_minute]


# Diz se a exceção é executável: se ela consegue dizer onde o NPC está no começo da faixa. Exceção
# que não consegue (ronda sem cena, sem pontos...) é ignorada pelo resolver, e a rotina padrão vale.
func is_executable() -> bool:
	return get_stop(0) != null


# Minuto do relógio de parede (0 = 00:00) em que a faixa começa.
func get_start_clock_minutes() -> int:
	return start_hour * MINUTES_PER_HOUR + start_minute


# Minuto do relógio de parede em que a faixa termina.
func get_end_clock_minutes() -> int:
	return end_hour * MINUTES_PER_HOUR + end_minute


# Minuto do DIA DE JOGO em que a faixa começa, contado da hora de acordar. É a mesma conversão do
# NPCRoutineEntry.get_minutes_into_day, e pelo mesmo motivo: o minuto 0 do dia é a hora de acordar.
func get_start_minutes_into_day(wake_hour: int) -> int:
	return posmod(get_start_clock_minutes() - wake_hour * MINUTES_PER_HOUR, MINUTES_PER_DAY)


# Quanto a faixa dura, em minutos. Fim menor que o começo dá a volta na meia-noite. Começo igual ao
# fim é o dia inteiro (24 h), e não zero minutos: uma faixa que nunca vale não escreve nada de útil, e
# "vale o dia todo" é justamente o jeito de escrever o NPC que não tem rotina padrão de verdade (um
# guarda que só circula).
func get_length_minutes() -> int:
	var length: int = _get_raw_length()
	return length if length > 0 else MINUTES_PER_DAY


# Quantos minutos se passaram desde o começo da faixa, no instante dado (unidade do GameClock: 0 =
# hora de acordar). Dá a volta no dia, então serve igual para uma faixa que atravessa a meia-noite ou
# a hora de acordar. Fora da faixa, o resultado é maior ou igual à duração dela.
func get_elapsed_minutes(minutes_into_day: int, wake_hour: int) -> int:
	return posmod(minutes_into_day - get_start_minutes_into_day(wake_hour), MINUTES_PER_DAY)


# Diz se a faixa está valendo no instante dado. O fim é exclusivo: às 17:00 a ronda das 08:00 às 17:00
# já acabou.
func is_active_at(minutes_into_day: int, wake_hour: int) -> bool:
	return get_elapsed_minutes(minutes_into_day, wake_hour) < get_length_minutes()


# Em quantos minutos esta exceção muda algo na decisão do NPC, contados do instante dado. Com a faixa
# valendo: a próxima parada ou o fim da faixa, o que vier antes. Fora dela: o começo da faixa. É o que
# deixa o menu de debug dizer "próxima mudança em N min" sem conhecer nenhum tipo de exceção.
func get_minutes_until_change(minutes_into_day: int, wake_hour: int) -> int:
	var elapsed: int = get_elapsed_minutes(minutes_into_day, wake_hour)
	var length: int = get_length_minutes()
	if elapsed >= length:
		return MINUTES_PER_DAY - elapsed

	var until_end: int = length - elapsed
	var until_stop: int = get_minutes_until_stop_change(elapsed)
	if until_stop > 0:
		return mini(until_stop, until_end)
	return until_end


# Diz se duas faixas têm algum minuto em comum. Conta em relógio de parede, então não depende da hora
# de acordar. Faixas coladas (uma acaba às 17:00, a outra começa às 17:00) não se sobrepõem.
func overlaps(other: NPCRoutineException) -> bool:
	var other_after_start: int = posmod(
		other.get_start_clock_minutes() - get_start_clock_minutes(), MINUTES_PER_DAY)
	var start_after_other: int = posmod(
		get_start_clock_minutes() - other.get_start_clock_minutes(), MINUTES_PER_DAY)
	return other_after_start < get_length_minutes() or start_after_other < other.get_length_minutes()


# Diz se alguma parte da faixa cai dentro do dia jogável (da hora de acordar até day_length minutos
# depois). Uma faixa que começa depois do fim do dia nunca é vivida: o jogador já apagou.
func overlaps_playable_day(wake_hour: int, day_length: int) -> bool:
	var start: int = get_start_minutes_into_day(wake_hour)
	# A faixa ocupa [start, start + duração) do dia de jogo, dando a volta em 1440: ou ela começa antes
	# do fim do dia jogável, ou ela dá a volta e volta a cobrir os primeiros minutos do dia.
	return start < day_length or start + get_length_minutes() > MINUTES_PER_DAY


# A duração como a conta sai, sem o tratamento de "dia inteiro": zero quando começo e fim são iguais.
# Separada do get_length_minutes porque o resumo precisa saber quando esse caso aconteceu.
func _get_raw_length() -> int:
	return posmod(get_end_clock_minutes() - get_start_clock_minutes(), MINUTES_PER_DAY)
