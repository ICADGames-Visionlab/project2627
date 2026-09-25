## DayNightCycle - Tinge o mundo 2D inteiro conforme a hora do relógio: amanhecer alaranjado,
## meio-dia branco, noite azul escura.
##
## COMO USAR: instancie DayNightCycle.tscn na cena de mundo (ver City.tscn) e pronto. As cores
## ficam no Gradient exportado, editável no Inspector — a posição 0 do gradiente é 00:00 e a
## posição 1 é 24:00, então arrastar um ponto para a direita é atrasar a hora daquela cor.
##
## Interiores iluminados (BakeryInterior.tscn) simplesmente NÃO recebem este nó. O CanvasModulate
## age sobre o canvas em que está, não sobre o jogo inteiro, então cada cena decide se escurece.
##
## POR QUE UM CanvasModulate E NÃO UM SHADER: um único nó multiplica a cor de tudo que é desenhado
## no mundo 2D, sem custo por sprite e sem código de render. O que está dentro de um CanvasLayer
## (HUD do relógio, menu de pausa, diálogo) fica de fora automaticamente — que é exatamente o que
## se quer: texto de interface não deve escurecer junto com a rua.
##
## POR QUE NÃO LER O RELÓGIO EM _process: o EventBus já anuncia o tempo a cada
## GameClock.TICK_MINUTES minutos de jogo. Entre um anúncio e o outro, um tween cobre a diferença,
## e o resultado na tela é contínuo do mesmo jeito — só que sem rodar conta nenhuma por frame.
class_name DayNightCycle
extends CanvasModulate

## Espaço para constantes

const DEBUG_SECTION: StringName = &"Tempo"

## Espaço para variáveis exportadas

## As cores do dia. A posição no gradiente é a hora do relógio de parede dividida por 24:
## 0.0 = 00:00, 0.25 = 06:00, 0.5 = 12:00, 0.75 = 18:00, 1.0 = 00:00 de novo.
## Deixe o primeiro e o último ponto com a MESMA cor, senão a virada da meia-noite pisca.
@export var gradient: Gradient

## Cor do mundo enquanto o jogador sonha, no lugar do gradiente. O padrão é um vinho escuro de
## sangue velho: multiplicado pela arte, o verde vira lama e o céu some — a cidade de sempre, só
## que errada. Branco desliga o efeito (o sonho fica com a cor da arte original).
@export var dream_color: Color = Color(0.42, 0.13, 0.22)

## Espaço para variáveis

# Tween da transição atual. Guardado para ser morto antes de começar o próximo — sem isso, dois
# tweens empurram a mesma propriedade quando o tempo é adiantado no meio de uma transição.
var _tween: Tween

# Último total_minutes anunciado, usado só para medir o tamanho do salto (ver _on_time_changed).
var _last_minutes: int = 0

# [DEBUG] Desligado pelo menu de debug, o ciclo para de escrever a cor e o mundo fica no branco.
var _enabled: bool = true

## Espaço para funções nativas

func _ready() -> void:
	if gradient == null:
		push_error("[DayNightCycle] - Sem Gradient configurado; o ciclo de dia e noite não vai rodar")
		return

	EventBus.time_changed.connect(_on_time_changed)

	# A cor de entrada é aplicada de uma vez, sem tween: a cena acabou de aparecer e ninguém
	# precisa ver a tela clarear do nada até a hora certa.
	_last_minutes = GameClock.time.total_minutes
	color = _color_at_clock()

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Entrada na seção "Tempo" do menu de debug (F4). O DebugMenu limpa sozinho as
		# entradas de nós que saíram da árvore, então não tem nada pra desregistrar na saída.
		DebugMenu.register_toggle(DEBUG_SECTION, "Ciclo de dia e noite", _debug_set_enabled, _enabled)

	print("[DayNightCycle] - Ciclo ligado em %s" % GameClock.time.format_clock())

## Espaço para funções personalizadas

# Anima a cor do mundo até a cor da hora recém-anunciada.
#
# A duração é o tempo REAL que aquele degrau de relógio leva, e não um valor fixo: assim a
# transição termina exatamente quando o próximo anúncio chega, sem sobrepor nem parar no meio.
# Quando o salto é maior que um degrau — dormir, carregar save, adiantar horas pelo debug — a cor
# é aplicada de imediato, porque ali o tempo foi PULADO e não vivido.
func _on_time_changed(total_minutes: int) -> void:
	var elapsed: int = absi(total_minutes - _last_minutes)
	_last_minutes = total_minutes

	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _enabled:
		return

	var target: Color = _color_at_clock()
	if elapsed <= 0 or elapsed > GameClock.TICK_MINUTES:
		color = target
		return

	var duration: float = (float(elapsed) * GameClock.settings.seconds_per_game_minute()
		/ maxf(GameClock.speed_multiplier, 0.01))
	_tween = create_tween()
	_tween.tween_property(self, "color", target, duration)


# Cor correspondente ao momento: a do sonho enquanto o jogador sonha, a da hora do relógio de
# parede no resto do tempo. Entrar e sair do sonho sempre chegam como salto de tempo, então a
# troca é aplicada seca — no escuro da transição, onde ninguém vê.
func _color_at_clock() -> Color:
	if GameClock.is_dreaming():
		return dream_color
	return gradient.sample(float(GameClock.time.get_clock_minutes()) / float(GameTime.MINUTES_PER_DAY))


# [DEBUG] Desliga o escurecimento sem tirar o nó da cena, para conferir a arte na cor original.
func _debug_set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _tween != null and _tween.is_valid():
		_tween.kill()
	color = _color_at_clock() if enabled else Color.WHITE
