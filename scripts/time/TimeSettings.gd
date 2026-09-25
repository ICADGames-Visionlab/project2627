## TimeSettings - Balanceamento do relógio do jogo: quando o dia começa, quanto ele dura em
## horas de jogo, e quanto tempo REAL isso leva. É o arquivo que o design abre.
##
## COMO USAR: abra res://resources/TimeSettings.tres no Inspector e mexa nos três campos. O
## campo "resumo" (cinza, só leitura) se reescreve sozinho a cada mudança e diz por extenso o
## que a combinação produz — não é preciso fazer conta nenhuma pra saber quanto dura um dia.
##
## Duplicar o .tres cria um preset ("playtest rápido", "ritmo final") sem tocar em código: basta
## apontar GameClock.SETTINGS_PATH para o novo arquivo.
##
## O guia completo está em docs/sistema_de_tempo.md.
@tool
class_name TimeSettings
extends Resource

## Espaço para constantes

# Duplicados de propósito em vez de importados do GameTime: o GameTime já depende deste arquivo,
# e depender de volta criaria referência circular entre dois class_name.
const MINUTES_PER_HOUR: int = 60
const MINUTES_PER_DAY: int = 1440

## Espaço para variáveis exportadas

@export_group("Janela do dia")

## Hora em que o jogador acorda. É o minuto 0 do dia de jogo — e é por isso que o dia da semana
## só vira aqui, e não à meia-noite.
@export_range(0, 23, 1, "suffix:h") var wake_hour: int = 6:
	set(value):
		wake_hour = value
		_refresh_summary()

## Quanto tempo de jogo o jogador tem antes de apagar. 20 h a partir das 06:00 = limite às 02:00.
## O horário do limite é derivado destes dois campos; não existe um terceiro campo pra ele.
@export_range(1.0, 24.0, 0.5, "suffix:h de jogo") var playable_hours: float = 20.0:
	set(value):
		playable_hours = value
		_refresh_summary()

@export_group("Ritmo")

## Quanto tempo REAL dura um dia jogável inteiro, de acordar até o limite.
## Esta é a única variável de ritmo do jogo: a velocidade do relógio é derivada dela.
@export_range(1.0, 60.0, 0.5, "suffix:min reais") var real_minutes_per_day: float = 15.0:
	set(value):
		real_minutes_per_day = maxf(value, 0.1)
		_refresh_summary()

@export_group("")

## Só leitura: o que as opções acima produzem, escrito por extenso. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

# Deixa o campo "resumo" cinza no Inspector. Ele é saída, não entrada.
func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

# Quantos minutos de jogo o dia jogável tem. Com 20 h, 1200 minutos.
func day_length_minutes() -> int:
	return int(playable_hours * float(MINUTES_PER_HOUR))

# Quantos segundos reais vale um minuto de jogo. É o número que o relógio consome, e o único
# motivo de ele não estar exposto no Inspector: ninguém deveria precisar pensar nesta unidade.
func seconds_per_game_minute() -> float:
	return (real_minutes_per_day * 60.0) / float(day_length_minutes())

# Em que hora do relógio de parede o dia acaba, já dando a volta na meia-noite.
func end_clock_minutes() -> int:
	return (wake_hour * MINUTES_PER_HOUR + day_length_minutes()) % MINUTES_PER_DAY

# Reescreve o resumo depois de qualquer mudança. notify_property_list_changed() é o que faz o
# Inspector redesenhar na hora, em vez de só na próxima vez que o recurso for selecionado.
func _refresh_summary() -> void:
	var ending: int = end_clock_minutes()
	var per_minute: float = seconds_per_game_minute()
	@warning_ignore("integer_division")
	var ending_hour: int = ending / MINUTES_PER_HOUR
	@warning_ignore("integer_division")
	resumo = "Dia jogável: %02d:00 -> %02d:%02d (%.1f h de jogo)\n" % [
		wake_hour, ending_hour, ending % MINUTES_PER_HOUR, playable_hours]
	resumo += "Duração real: %.1f min reais por dia\n" % real_minutes_per_day
	resumo += "1 h de jogo = %.0f s reais  ·  1 min de jogo = %.2f s reais" % [
		per_minute * 60.0, per_minute]
	notify_property_list_changed()
