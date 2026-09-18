## GameClock - Autoload: o relógio da partida. Converte tempo real em minutos de jogo, respeita
## o horário máximo do dia e anuncia tudo no EventBus.
##
## É Autoload porque o horário precisa sobreviver à troca de cena — um nó dentro da cena de jogo
## perderia a hora toda vez que o jogador entrasse numa casa. Ser Autoload NÃO significa que o
## tempo corre sempre: o relógio nasce parado e só anda quando as três portas abrem.
##
##   1. Árvore ativa - process_mode = PAUSABLE, então get_tree().paused (menu de pausa, F4) já
##                     para o relógio sem código nenhum.
##   2. Sessão ativa - _is_running só fica true entre start_session() e stop_session(). É o que
##                     impede o tempo de correr no menu principal e na tela de loading, que são
##                     cenas e não pausa.
##   3. Sem freeze   - pilha de motivos (diálogo, cutscene, transição de cena, fim do dia).
##                     Pilha e não bool: diálogo dentro de cutscene é normal, e com um bool o
##                     primeiro a terminar descongelaria o relógio no meio do outro.
##
## COMO USAR:
##
##     GameClock.time.get_hour()          # ler a hora
##     GameClock.freeze(&"dialogo")       # segurar o tempo
##     GameClock.unfreeze(&"dialogo")     # soltar
##     GameClock.advance(60)              # adiantar uma hora (respeita o limite do dia)
##     GameClock.end_day()                # dormir
##
## Para reagir ao tempo, escute o EventBus — não leia o relógio em _process.
##
## O guia completo está em docs/sistema_de_tempo.md.
extends Node

## Espaço para enums

# Por que o dia acabou. Vai junto no EventBus.day_ended para quem quiser tratar diferente
# (dormir na cama x apagar de pé no meio da rua).
enum DayEndReason { SLEPT, COLLAPSED }

## Espaço para constantes

const SETTINGS_PATH: String = "res://resources/TimeSettings.tres"

# De quantos em quantos minutos de jogo o EventBus.time_changed é emitido. Por dentro o relógio
# anda de minuto em minuto (é o que torna a conta exata); anunciar todo minuto seriam 1440
# notificações por dia para a cidade inteira, sem nenhuma diferença visível no HUD.
const TICK_MINUTES: int = 10

# Chave do tempo no dicionário de save.
const SAVE_KEY: String = "total_minutes"

# Motivo de freeze usado pela sequência de fim de dia. Fica numa constante porque quem congela
# (este arquivo) e quem descongela (start_next_day) precisam usar exatamente o mesmo nome.
const FREEZE_DAY_END: StringName = &"fim_do_dia"

const DEBUG_SECTION: StringName = &"Tempo"

## Espaço para variáveis

# Multiplicador de velocidade do relógio. NÃO use Engine.time_scale para isso: ela acelera
# animação, física e áudio junto, ou seja, o jogo inteiro em avanço rápido.
var speed_multiplier: float = 1.0

# Balanceamento, carregado de SETTINGS_PATH.
var settings: TimeSettings

# O calendário. Leitura pública (GameClock.time.get_hour()); escrita só por este arquivo.
var time: GameTime

# Porta 2: fica true entre start_session() e stop_session().
var _is_running: bool = false

# Porta 3: Dictionary usado como conjunto de motivos. Vazio = relógio solto.
var _freeze_reasons: Dictionary = {}

# true entre enter_dream() e start_next_day(). Mora aqui, e não na cena, porque o mundo dos sonhos
# pode virar uma cena própria — e aí o estado precisa sobreviver à troca de cena, que é
# exatamente o que um Autoload já garante.
var _is_dreaming: bool = false

# Sobra de tempo real que ainda não completou um minuto de jogo.
var _accumulator: float = 0.0

# Último total_minutes anunciado em time_changed, usado para medir o degrau de TICK_MINUTES.
var _last_tick_minutes: int = 0

## Espaço para funções nativas

func _ready() -> void:
	# Explícito em vez de herdado: o padrão já seria este, mas deixar escrito evita que alguém
	# marque ALWAYS "pra garantir" e faça o tempo correr durante a pausa.
	process_mode = Node.PROCESS_MODE_PAUSABLE

	settings = _load_settings()
	time = GameTime.new(settings)

	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Tempo" do menu de debug (F4) e do console (F1).
		_register_debug_entries()

	print("[GameClock] - Relógio pronto e parado. %s" % settings.resumo.replace("\n", " | "))


# Converte tempo real em minutos de jogo.
#
# Roda em _physics_process, e não em _process, por três motivos: a engine já limita quantos
# passos de física roda por frame (physics/common/max_physics_steps_per_frame), então uma travada
# de 3 s não vira um salto de 3 minutos de jogo; o passo é fixo, então a conta é igual em
# qualquer máquina; e é o mesmo passo em que o Player e os NPCs se movem.
func _physics_process(delta: float) -> void:
	if not _is_running or not _freeze_reasons.is_empty():
		return

	var seconds_per_minute: float = settings.seconds_per_game_minute()
	_accumulator += delta * speed_multiplier

	# while, e não if: com o multiplicador alto um único passo de física pode valer mais de um
	# minuto de jogo, e com if o excedente seria descartado em silêncio.
	var minutes: int = 0
	while _accumulator >= seconds_per_minute:
		_accumulator -= seconds_per_minute
		minutes += 1

	if minutes > 0:
		advance(minutes)

## Espaço para funções personalizadas

# Liga o relógio. Quem chama é a cena de jogo (ver GameSession.gd), não o menu.
# Passe total_minutes para retomar um save; omita para continuar de onde o relógio já está
# (0 numa partida nova).
func start_session(p_total_minutes: int = -1) -> void:
	if p_total_minutes >= 0:
		time.total_minutes = p_total_minutes

	_accumulator = 0.0
	_freeze_reasons.clear()
	_last_tick_minutes = time.total_minutes
	_is_running = true

	print("[GameClock] - Sessão iniciada no dia %d às %s" % [time.get_day(), time.format_clock()])
	EventBus.time_changed.emit(time.total_minutes)


# Desliga o relógio. Chamado quando a cena de jogo sai da árvore (voltar ao menu, fechar o jogo).
func stop_session() -> void:
	if not _is_running:
		return
	_is_running = false
	print("[GameClock] - Sessão encerrada no dia %d às %s" % [time.get_day(), time.format_clock()])


# Faz o tempo ser VIVIDO: adianta o relógio e anuncia o que mudou no caminho.
#
# O corte do horário máximo mora aqui, e não no _physics_process, de propósito: assim todo
# caminho que adianta o tempo (o tick, o menu de debug, um evento de roteiro) respeita o limite
# sem precisar lembrar disso.
func advance(minutes: int) -> void:
	if minutes <= 0 or not _freeze_reasons.is_empty():
		return

	var limit: int = settings.day_length_minutes()
	var into_day: int = time.get_minutes_into_day()

	if into_day + minutes >= limit:
		# Para exatamente no limite em vez de atravessá-lo, e fecha o dia.
		_set_total_minutes(time.total_minutes + (limit - into_day))
		end_day(DayEndReason.COLLAPSED)
		return

	_set_total_minutes(time.total_minutes + minutes)


# Fecha o dia: congela o relógio e anuncia. O que acontece depois (fade, tela de resumo, save) é
# de quem escuta EventBus.day_ended — o relógio não conhece tela. Enquanto ninguém chamar
# start_next_day(), o tempo fica parado, que é justamente o que se quer durante essa sequência.
func end_day(reason: DayEndReason = DayEndReason.SLEPT) -> void:
	if _freeze_reasons.has(FREEZE_DAY_END):
		return

	freeze(FREEZE_DAY_END)
	print("[GameClock] - Fim do dia %d (%s) às %s" % [
		time.get_day(), DayEndReason.keys()[reason], time.format_clock()])
	EventBus.day_ended.emit(time.get_day(), reason)


# Abre o dia seguinte, na hora de acordar.
#
# As horas dormidas são PULADAS, não vividas: por isso isto é uma escrita direta no minuto 0 do
# próximo dia, e não um advance(). Com advance(), o jogo dispararia viradas de hora que ninguém
# viveu e bateria no horário máximo de novo no meio do caminho.
func start_next_day() -> void:
	_is_dreaming = false
	_set_total_minutes((time.get_day_index() + 1) * GameTime.MINUTES_PER_DAY, false)
	_accumulator = 0.0
	unfreeze(FREEZE_DAY_END)

	print("[GameClock] - Dia %d começou às %s" % [time.get_day(), time.format_clock()])
	EventBus.day_changed.emit(time.get_day())
	EventBus.time_changed.emit(time.total_minutes)


# Adormece o jogador: fecha o dia (se o horário máximo ainda não tinha fechado) e trava o relógio
# na hora do sonho (TimeSettings.dream_hour, 03:00 por padrão) até o start_next_day().
#
# A hora do sonho é ESCRITA, não vivida — igual às horas dormidas do start_next_day(): quem deita
# às 22:00 não atravessa cinco horas de NPC andando e de hour_changed. E o relógio já fica parado
# pelo freeze do end_day(), então nada mais precisa segurá-lo aqui.
#
# O dia de jogo continua o mesmo (o minuto 0 é a hora de acordar, ver GameTime): 03:00 é só mais
# um minuto do fim do dia, mesmo quando cai depois do horário máximo.
func enter_dream() -> void:
	if _is_dreaming:
		return

	end_day(DayEndReason.SLEPT)
	_is_dreaming = true

	var dream_minute: int = posmod((settings.dream_hour - settings.wake_hour) * GameTime.MINUTES_PER_HOUR,
		GameTime.MINUTES_PER_DAY)
	_set_total_minutes(time.get_day_index() * GameTime.MINUTES_PER_DAY + dream_minute, false)

	print("[GameClock] - Jogador sonhando no dia %d, relógio travado em %s" % [
		time.get_day(), time.format_clock()])
	EventBus.time_changed.emit(time.total_minutes)
	EventBus.dream_started.emit(time.get_day())


func is_dreaming() -> bool:
	return _is_dreaming


# Segura o relógio por um motivo. Registrar o mesmo motivo duas vezes não empilha duas vezes.
func freeze(reason: StringName) -> void:
	if _freeze_reasons.has(reason):
		return
	_freeze_reasons[reason] = true
	print("[GameClock] - Relógio congelado por \"%s\"" % reason)


# Solta o relógio de um motivo. Se outro motivo ainda estiver de pé, o tempo continua parado.
func unfreeze(reason: StringName) -> void:
	if not _freeze_reasons.erase(reason):
		return
	if _freeze_reasons.is_empty():
		print("[GameClock] - Relógio solto (\"%s\" liberado)" % reason)
	else:
		print("[GameClock] - \"%s\" liberado, mas ainda congelado por %s" % [
			reason, _freeze_reasons.keys()])


func is_running() -> bool:
	return _is_running


func is_frozen() -> bool:
	return not _freeze_reasons.is_empty()


# Quantos minutos de jogo faltam para o horário máximo.
func get_minutes_left() -> int:
	return time.get_minutes_left()


# Escreve o tempo no dicionário que vai para o SaveManager.
func write_to_save(data: Dictionary) -> void:
	data[SAVE_KEY] = time.total_minutes


# Lê o tempo de um dicionário vindo do SaveManager.
#
# O int() não é decoração: o JSON não tem tipo inteiro, então todo número que o SaveManager grava
# volta como float. Sem a conversão, as divisões do calendário viram divisões de ponto flutuante
# e a data sai errada sem nenhum erro no console.
func read_from_save(data: Dictionary) -> void:
	_set_total_minutes(int(data.get(SAVE_KEY, 0)), false)


# Único ponto do projeto que escreve no inteiro do calendário. As viradas de hora e de dia saem
# daqui, por comparação entre antes e depois — é isso que faz um advance(600) se comportar como
# um advance(1): uma virada de dia, com o valor final, em vez de dez eventos seguidos.
func _set_total_minutes(value: int, emit_crossings: bool = true) -> void:
	var previous_hour: int = time.get_hour()
	var previous_day: int = time.get_day()

	time.total_minutes = value

	if not emit_crossings:
		_last_tick_minutes = value
		return

	if time.get_hour() != previous_hour:
		EventBus.hour_changed.emit(time.get_hour())
	if time.get_day() != previous_day:
		EventBus.day_changed.emit(time.get_day())

	if absi(time.total_minutes - _last_tick_minutes) >= TICK_MINUTES:
		_last_tick_minutes = time.total_minutes
		EventBus.time_changed.emit(time.total_minutes)


# Carrega o recurso de balanceamento. Se o arquivo sumir ou estiver quebrado, o relógio cai nos
# valores padrão em vez de derrubar a partida inteira.
func _load_settings() -> TimeSettings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded: Resource = load(SETTINGS_PATH)
		if loaded is TimeSettings:
			return loaded
	push_warning("[GameClock] - AVISO: \"%s\" não encontrado ou inválido, usando os valores padrão" % SETTINGS_PATH)
	return TimeSettings.new()


# [DEBUG] Entradas da seção "Tempo". Não existem em build de release.
func _register_debug_entries() -> void:
	DebugMenu.register_input(DEBUG_SECTION, "Avançar minutos", advance,
		[DebugParam.int_value("minutos", 60, 1, 1440)])
	DebugMenu.register_action(DEBUG_SECTION, "Dormir (ir para o dia seguinte)", _debug_sleep)
	DebugMenu.register_action(DEBUG_SECTION, "Sonhar (entrar no mundo dos sonhos)", enter_dream)
	DebugMenu.register_action(DEBUG_SECTION, "Mostrar data e hora", _debug_print_time)
	DebugMenu.register_toggle(DEBUG_SECTION, "Congelar relógio", _debug_set_frozen)
	DebugMenu.register_value(DEBUG_SECTION, "Minutos reais por dia", _debug_set_real_minutes,
		DebugParam.float_value("", settings.real_minutes_per_day, 1.0, 60.0, 0.5),
		func() -> float: return settings.real_minutes_per_day)


# [DEBUG] Pula direto para o dia seguinte, sem passar pelo mundo dos sonhos. As duas chamadas
# são necessárias: o dia não vira sozinho depois do end_day() (quem abre o dia é a cama).
func _debug_sleep() -> void:
	end_day(DayEndReason.SLEPT)
	start_next_day()


# [DEBUG] Imprime a data completa no console de debug.
func _debug_print_time() -> void:
	print("[GameClock] - Dia %d (%s), semana %d, %s — faltam %d min para o fim do dia" % [
		time.get_day(), time.format_weekday(), time.get_week(),
		time.format_clock(), get_minutes_left()])


# [DEBUG] Liga/desliga um freeze próprio do menu, sem atropelar os motivos de gameplay.
func _debug_set_frozen(enabled: bool) -> void:
	if enabled:
		freeze(&"debug")
	else:
		unfreeze(&"debug")


# [DEBUG] Ajusta o ritmo com o jogo rodando. A unidade é a mesma do Inspector de propósito: o
# número que o design achou aqui é o número que ele digita no .tres.
func _debug_set_real_minutes(value: float) -> void:
	settings.real_minutes_per_day = value
	print("[GameClock] - Ritmo ajustado: %s" % settings.resumo.replace("\n", " | "))
