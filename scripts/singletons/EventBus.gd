# EventBus.gd — Singleton de eventos do projeto.
# Sistemas não chamam uns aos outros: quem faz algo anuncia o fato aqui, e quem se interessa
# escuta. O bus só transporta — não guarda estado e não tem lógica.
#
# Todos os eventos do jogo ficam neste arquivo, agrupados por módulo, cada um com um comentário
# acima dizendo quem emite e quem escuta. Abrir este arquivo é ver o jogo inteiro conversando.
#
# ESTADO ATUAL: os eventos de tempo (GameClock), os do sistema de insights e os do sistema de
# diálogo. Eventos nascem junto com o sistema que produz os fatos — criar antes disso seria
# adivinhar features que o conceito do jogo ainda não decidiu.
#
# Para adicionar um evento, é uma edição só: declarar o sinal abaixo, tipado e comentado.
#
#     # ------------------------------------------------------------------------------------
#     # Produção
#     # ------------------------------------------------------------------------------------
#
#     # Emitido quando o jogador termina uma receita na bancada.
#     # Emissor: CraftingStation. Ouvintes: InventorySystem, QuestSystem.
#     signal recipe_crafted(recipe_id: StringName, amount: int)
#
# Não há registro em lugar nenhum: a instrumentação varre os sinais declarados neste script e
# encontra o evento novo sozinha.
#
# Como usar:
#   EventBus.recipe_crafted.emit(&"bread", 2)              # publicar
#   EventBus.recipe_crafted.connect(_on_recipe_crafted)    # escutar
#
# O guia completo está em docs/event_bus.md.
extends Node

# Os sinais deste arquivo são emitidos e escutados por outros scripts, nunca aqui dentro — é a
# definição de um bus. Sem isto, cada evento declarado gera um warning UNUSED_SIGNAL no editor.
@warning_ignore_start("unused_signal")

# ------------------------------------------------------------------------------------
# Tempo
# ------------------------------------------------------------------------------------

# Emitido a cada degrau de GameClock.TICK_MINUTES minutos de jogo, e também quando o tempo é
# escrito de uma vez (início de sessão, carregar save, abrir o dia seguinte). Quem precisa de
# precisão de minuto lê GameClock.time.total_minutes direto, em vez de pedir um evento por minuto.
# Emissor: GameClock. Ouvintes: HUD do relógio, rotinas de NPC.
signal time_changed(total_minutes: int)

# Emitido quando a hora do relógio muda (13:59 -> 14:00).
# Emissor: GameClock. Ouvintes: rotinas de NPC, som ambiente, lojas abrindo e fechando.
signal hour_changed(hour: int)

# Emitido quando o dia de jogo muda — o que acontece ao acordar, não à meia-noite.
# Emissor: GameClock. Ouvintes: rotinas de NPC, produção, save automático.
signal day_changed(day: int)

# Emitido quando o dia fecha, por sono ou por ter batido no horário máximo. O relógio fica
# congelado a partir daqui até alguém chamar GameClock.start_next_day().
# reason é um GameClock.DayEndReason.
# Emissor: GameClock. Ouvintes: GameSession (abre o dia seguinte), tela de resumo, save.
signal day_ended(day: int, reason: int)

# ------------------------------------------------------------------------------------
# Insights
# ------------------------------------------------------------------------------------

# Emitido quando o jogador lê um insight, seja a descoberta ou uma releitura (first_time no payload
# separa as duas).
# Emissor: InsightDirector. Ouvintes: InsightJournal (marca o lido), InsightSource (reage à
# mudança de estado do próprio marcador) e InsightAudio (som da primeira leitura).
signal insight_revealed(event: InsightRevealedEvent)

# Pede a exibição de uma fala na tela de diálogo. Pedido: espera exatamente 1 ouvinte, e o logger
# acusa no console quando a contagem não é essa.
# Emissor: InsightDirector. Ouvinte: DialogueScreen.
signal dialogue_requested(head_id: StringName, text_key: String)

# ------------------------------------------------------------------------------------
# Diálogo
# ------------------------------------------------------------------------------------

# Clicou num NPC: antes de conversation_requested, trava o jogador e os orbes de insight cedo,
# enquanto o Player anda até perto do NPC e a DialogueCamera aproxima dos dois. Não passa pelo
# fluxo de debug (Iniciar conversa/Pular para nó emitem conversation_requested direto).
# Emissor: NPCInteraction. Ouvintes: Player, InsightInteractor (travam entrada), NPCDirector
# (segura o NPC parado, sem virar pra o jogador ainda — isso só acontece em conversation_started).
signal conversation_approach_started(conversation_id: StringName, npc_id: StringName)

# Pede o início de uma conversa. Pedido: espera exatamente 1 ouvinte.
# initiator_id é quem puxou a conversa (id do NPC, ou &"" para gatilho e debug); ele é repassado em
# conversation_started para quem precisa segurar aquele NPC.
# Emissor: NPCInteraction (fim da abordagem), debug. Ouvinte: DialogueScreen.
signal conversation_requested(conversation_id: StringName, initiator_id: StringName)

# Emitido quando uma conversa abre.
# Emissor: DialogueScreen. Ouvintes: Player (trava movimento, redundante se já veio de
# conversation_approach_started), NPCDirector (segura o NPC e vira ele pro jogador),
# InsightInteractor (desliga orbes, idem Player).
signal conversation_started(conversation_id: StringName, initiator_id: StringName)

# Emitido quando uma conversa fecha, com o nó onde terminou.
# Emissor: DialogueScreen. Ouvintes: os mesmos de conversation_started.
signal conversation_ended(conversation_id: StringName, end_node_id: StringName)

var _logger: EventBusLogger


func _ready() -> void:
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Instrumentação de eventos: não existe em build de release.
		_logger = EventBusLogger.new()
		_logger.name = &"EventBusLogger"
		add_child(_logger)
		_logger.attach_to_bus(self)


# Devolve a instrumentação ativa, ou null em build de release.
# Usado pelo overlay de debug e por ferramentas que inspecionam contadores de emissão.
func get_logger() -> EventBusLogger:
	return _logger
