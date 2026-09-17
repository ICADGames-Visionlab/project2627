## NightLight - Luz que acende sozinha ao anoitecer e apaga ao amanhecer (poste, lampião, janela
## acesa).
##
## COMO USAR: instancie NightLight.tscn onde a luz deve ficar e ajuste, no Inspector, a cor, o
## alcance (texture_scale) e a força (energy) — a força configurada é a que a luz terá acesa.
## As horas de acender e apagar também são campos do Inspector.
##
## Cada luz cuida de si e escuta o EventBus direto, em vez de o DayNightCycle varrer um grupo:
## acender é uma reação a uma hora, igual à cor do céu, e uma lista de luzes seria mais um lugar
## para esquecer de registrar a luz nova.
##
## Depende do CanvasModulate do DayNightCycle para fazer efeito visível: a luz clareia o que está
## em volta, então sem a noite escura não há o que clarear.
class_name NightLight
extends PointLight2D

## Espaço para variáveis exportadas

## Hora em que a luz acende.
@export_range(0, 23, 1, "suffix:h") var turn_on_hour: int = 18

## Hora em que a luz apaga. Pode ser menor que turn_on_hour — é o caso normal, de uma luz que
## atravessa a meia-noite.
@export_range(0, 23, 1, "suffix:h") var turn_off_hour: int = 6

## Quanto tempo real o acender e o apagar levam. Sem isso a cidade inteira piscaria de uma vez na
## virada da hora.
@export var fade_duration: float = 2.0

## Espaço para variáveis

# A força que a luz tem acesa: o valor que o level design deixou no Inspector. Guardado no
# _ready porque "apagada" é energy = 0, e sem essa cópia o valor original se perderia no
# primeiro amanhecer.
var _lit_energy: float = 1.0

var _tween: Tween

## Espaço para funções nativas

func _ready() -> void:
	_lit_energy = energy
	EventBus.hour_changed.connect(_on_hour_changed)

	# Estado de entrada aplicado de uma vez: quem carrega um save às 22:00 tem que encontrar a
	# rua já iluminada, não vê-la acender.
	energy = _lit_energy if _is_night(GameClock.time.get_hour()) else 0.0
	enabled = energy > 0.0

## Espaço para funções personalizadas

# Acende ou apaga na virada da hora. Chamadas que não mudam nada são descartadas, porque o sinal
# chega 24 vezes por dia e a luz só reage a duas delas.
func _on_hour_changed(hour: int) -> void:
	var target: float = _lit_energy if _is_night(hour) else 0.0
	if is_equal_approx(target, energy):
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Acender antes do fade e apagar só depois dele: enabled = false é o que tira a luz da conta
	# do render, e desligar no começo do fade cortaria a animação pela metade.
	enabled = true
	_tween = create_tween()
	_tween.tween_property(self, "energy", target, fade_duration)
	_tween.tween_callback(func() -> void: enabled = energy > 0.0)

	print("[NightLight] - \"%s\" %s às %02d:00" % [
		name, "acendendo" if target > 0.0 else "apagando", hour])


# Diz se a hora está dentro da janela de luz acesa. O ramo de cima é o caso que atravessa a
# meia-noite (18h -> 6h), em que a janela é a UNIÃO de dois pedaços do dia e não um intervalo.
func _is_night(hour: int) -> bool:
	if turn_on_hour > turn_off_hour:
		return hour >= turn_on_hour or hour < turn_off_hour
	return hour >= turn_on_hour and hour < turn_off_hour
