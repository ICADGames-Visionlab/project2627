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

@export_group("Hora de dormir")

## Quantas horas de jogo antes do fim do dia a cama passa a aceitar o jogador. 2 h num dia que
## acaba às 00:00 = pode dormir a partir das 22:00.
##
## É uma DURAÇÃO e não um horário de propósito: assim mexer em playable_hours arrasta a hora de
## dormir junto, e não existe a combinação quebrada de uma janela que cai fora do dia jogável.
## O horário que sai daqui aparece por extenso no resumo.
@export_range(0.5, 12.0, 0.5, "suffix:h de jogo") var sleep_window_hours: float = 2.0:
	set(value):
		sleep_window_hours = value
		_refresh_summary()

@export_group("Mundo dos sonhos")

## Hora em que o relógio fica travado enquanto o jogador sonha.
@export_range(0, 23, 1, "suffix:h") var dream_hour: int = 3:
	set(value):
		dream_hour = value
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
##
## É CALCULADO NA HORA, não guardado. O texto também vai parar no .tres (todo @export vai), e se
## ele fosse um campo comum o valor gravado seria aplicado por último no carregamento e passaria
## por cima do resumo recém-calculado: bastava mexer no código do resumo para o Inspector
## continuar mostrando a versão antiga até alguém tocar em algum campo.
@export_multiline var resumo: String:
	get:
		return _build_summary()
	set(_value):
		pass

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

# Quantos minutos de jogo dura a janela de dormir.
func sleep_window_minutes() -> int:
	return int(sleep_window_hours * float(MINUTES_PER_HOUR))

# Diz se a cama aceita o jogador, a partir de quanto falta para o fim do dia (GameClock.get_minutes_left()).
#
# A conta é feita no que FALTA, e não na hora do relógio de parede, porque é isso que a janela
# significa: o fim do dia. Sai de graça o que seria o caso chato na outra conta — a virada da
# meia-noite no meio da janela — e o próprio horário máximo, com 0 minutos restantes, entra na
# janela por definição, em vez de precisar de uma exceção para a partida não travar lá.
func is_sleep_time(minutes_left: int) -> bool:
	return minutes_left <= sleep_window_minutes()

# Em que minuto do relógio de parede a janela de dormir abre. Só para exibição (resumo, HUD).
func sleep_start_clock_minutes() -> int:
	return (end_clock_minutes() - sleep_window_minutes() + MINUTES_PER_DAY) % MINUTES_PER_DAY

# Em que hora do relógio de parede o dia acaba, já dando a volta na meia-noite.
func end_clock_minutes() -> int:
	return (wake_hour * MINUTES_PER_HOUR + day_length_minutes()) % MINUTES_PER_DAY

# Manda o Inspector redesenhar depois de qualquer mudança — é o que faz o resumo se reescrever na
# hora, em vez de só na próxima vez que o recurso for selecionado.
func _refresh_summary() -> void:
	notify_property_list_changed()


# Monta o texto do resumo a partir do estado atual. Chamado pelo getter de "resumo".
func _build_summary() -> String:
	var ending: int = end_clock_minutes()
	var sleep_start: int = sleep_start_clock_minutes()
	var per_minute: float = seconds_per_game_minute()
	@warning_ignore("integer_division")
	var ending_hour: int = ending / MINUTES_PER_HOUR
	@warning_ignore("integer_division")
	var sleep_start_hour: int = sleep_start / MINUTES_PER_HOUR

	var text: String = "Dia jogável: %02d:00 -> %02d:%02d (%.1f h de jogo)\n" % [
		wake_hour, ending_hour, ending % MINUTES_PER_HOUR, playable_hours]
	text += "Pode começar a dormir em %02d:%02d (%.1f h antes do fim)\n" % [
		sleep_start_hour, sleep_start % MINUTES_PER_HOUR, sleep_window_hours]
	text += "Sonho travado em %02d:00\n" % dream_hour
	text += "Duração real: %.1f min reais por dia\n" % real_minutes_per_day
	text += "1 h de jogo = %.0f s reais  ·  1 min de jogo = %.2f s reais" % [
		per_minute * 60.0, per_minute]
	return text
