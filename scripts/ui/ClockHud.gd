## ClockHud - Mostra a data e a hora do jogo no canto da tela.
##
## PROVISÓRIO: é um Label num canto, sem arte nenhuma — existe para o relógio ser visível
## enquanto o HUD de verdade não existe. Quando ele existir, o que importa é copiar daqui o
## jeito de ler o tempo, não o visual:
##
##   - escuta EventBus.time_changed e redesenha; NUNCA lê o relógio em _process(). Polling de HUD
##     é custo por frame num sistema que foi desenhado justamente pra não ter nenhum.
##   - todo texto sai de tr(), porque formato de hora e nome de dia mudam por idioma.
extends CanvasLayer

## Espaço para variáveis onready

@onready var _label: Label = $Panel/Label

## Espaço para funções nativas

func _ready() -> void:
	EventBus.time_changed.connect(_on_time_changed)
	EventBus.day_changed.connect(_on_day_changed)
	_refresh()

## Espaço para funções personalizadas

func _on_time_changed(_total_minutes: int) -> void:
	_refresh()


func _on_day_changed(_day: int) -> void:
	_refresh()


# Redesenha o texto a partir do estado atual do relógio.
func _refresh() -> void:
	var time: GameTime = GameClock.time
	_label.text = "%s (%s)\n%s" % [
		tr("DAY_LABEL") % time.get_day(), time.format_weekday(), time.format_clock()]
