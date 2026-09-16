## GameTime - O calendário do jogo. Converte um único inteiro de minutos em minuto, hora, dia,
## dia da semana e semana.
##
## Não é um Node, não emite nada e não consome delta: é uma calculadora. Existe separada do
## GameClock porque a parte que dá bug num sistema de tempo é a aritmética de calendário, e
## assim ela pode ser conferida sem rodar o jogo (ver docs/sistema_de_tempo.md, "Como testar").
##
## COMO USAR (leitura, de qualquer lugar do projeto):
##
##     GameClock.time.get_hour()        # 14
##     GameClock.time.get_day()         # 3
##     GameClock.time.get_weekday()     # 0 = segunda
##     GameClock.time.format_clock()    # "14:05"
##
## O MINUTO ZERO É A HORA DE ACORDAR, NÃO A MEIA-NOITE. É a única sutileza do arquivo, e ela
## existe porque o jogo tem horário máximo: se a data virasse à meia-noite, o HUD trocaria de
## "Dia 3" para "Dia 4" com o jogador ainda acordado, e os NPCs receberiam day_changed horas
## antes do dia realmente acabar. Com o minuto 0 sendo o despertar, get_day() fica estável até
## o jogador dormir.
class_name GameTime
extends RefCounted

## Espaço para constantes

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY
const DAYS_PER_WEEK: int = 7

# Chaves de tradução dos dias da semana, na ordem do get_weekday(). Nome de dia é texto exibido
# ao jogador, então mora no CSV de localização e não aqui.
const WEEKDAY_KEYS: Array[StringName] = [
	&"WEEKDAY_MON", &"WEEKDAY_TUE", &"WEEKDAY_WED", &"WEEKDAY_THU",
	&"WEEKDAY_FRI", &"WEEKDAY_SAT", &"WEEKDAY_SUN"]

## Espaço para variáveis

# Balanceamento (hora de acordar, duração do dia). Usado só para leitura daqui de dentro.
var settings: TimeSettings

# Minutos de jogo desde o começo da partida. É o estado inteiro do sistema: todo o resto deste
# arquivo é divisão deste número. Guardar hora e dia em variáveis próprias seria quatro lugares
# pra dessincronizar e quatro campos no save.
var total_minutes: int = 0

## Espaço para funções nativas

func _init(p_settings: TimeSettings = null) -> void:
	settings = p_settings if p_settings != null else TimeSettings.new()

## Espaço para funções personalizadas

# Índice do dia começando em 0. É o que entra nas contas de semana; para exibir, use get_day().
func get_day_index() -> int:
	@warning_ignore("integer_division")
	return total_minutes / MINUTES_PER_DAY


# Dia como o jogador vê: o primeiro dia é o dia 1.
func get_day() -> int:
	return get_day_index() + 1


# 0 = segunda, 6 = domingo. Derivado, nunca guardado.
func get_weekday() -> int:
	return get_day_index() % DAYS_PER_WEEK


# Semana começando em 1.
func get_week() -> int:
	@warning_ignore("integer_division")
	return get_day_index() / DAYS_PER_WEEK + 1


# Minutos desde que o jogador acordou. 0 = acabou de acordar.
func get_minutes_into_day() -> int:
	return total_minutes % MINUTES_PER_DAY


# Minuto do relógio de parede (0 = 00:00). Soma o deslocamento do despertar e dá a volta em 24 h:
# com wake_hour = 6, o minuto 1080 do dia (18 h depois de acordar) é 00:00 — e continua sendo o
# MESMO dia de jogo.
func get_clock_minutes() -> int:
	return (settings.wake_hour * MINUTES_PER_HOUR + get_minutes_into_day()) % MINUTES_PER_DAY


func get_hour() -> int:
	@warning_ignore("integer_division")
	return get_clock_minutes() / MINUTES_PER_HOUR


func get_minute() -> int:
	return get_clock_minutes() % MINUTES_PER_HOUR


# Quantos minutos de jogo faltam para o horário máximo. Nunca negativo: ao bater no limite o
# relógio para exatamente nele.
func get_minutes_left() -> int:
	return maxi(settings.day_length_minutes() - get_minutes_into_day(), 0)


# "14:05". O formato vem do CSV de localização porque 12 h/24 h muda por idioma.
func format_clock() -> String:
	return tr("TIME_FORMAT") % [get_hour(), get_minute()]


# "Segunda", "Terça"... traduzido.
func format_weekday() -> String:
	return tr(WEEKDAY_KEYS[get_weekday()])
