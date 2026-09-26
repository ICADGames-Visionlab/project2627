# EventBus.gd — Singleton de eventos do projeto.
# Sistemas não chamam uns aos outros: quem faz algo anuncia o fato aqui, e quem se interessa
# escuta. O bus só transporta — não guarda estado e não tem lógica.
#
# Todos os eventos do jogo ficam neste arquivo, agrupados por módulo, cada um com um comentário
# acima dizendo quem emite e quem escuta. Abrir este arquivo é ver o jogo inteiro conversando.
#
# ESTADO ATUAL: os eventos de tempo (GameClock), os do sistema de insights, os do profiling e os
# do sistema de diálogo. Eventos nascem junto com o sistema que produz os fatos — criar antes
# disso seria adivinhar features que o conceito do jogo ainda não decidiu.
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
# congelado a partir daqui até alguém chamar GameClock.start_next_day() — hoje, a cama.
# reason é um GameClock.DayEndReason.
# Emissor: GameClock. Ouvintes: tela de resumo, save (quando existirem).
signal day_ended(day: int, reason: int)

# Emitido quando o jogador adormece e entra no mundo dos sonhos. A partir daqui o relógio fica
# travado na hora do sonho (TimeSettings.dream_hour) e GameClock.is_dreaming() é true até ele
# acordar — e acordar é o day_changed de sempre, por isso não existe um "dream_ended".
# Emissor: GameClock. Ouvintes: NPCDirector (põe cada NPC na posição de sonho).
signal dream_started(day: int)

# ------------------------------------------------------------------------------------
# Interação
# ------------------------------------------------------------------------------------

# Pede o aviso de ação no rodapé da tela ("Aperte ESPAÇO para dormir"). text_key é uma chave de
# localização; a string VAZIA é o pedido de esconder o aviso.
# Um pedido substitui o anterior: o aviso é um só, e quem chega por último é quem o jogador está
# olhando. Por isso quem mostrou também precisa esconder ao sair de alcance.
# Emissor: objetos interativos do mundo (Bed). Ouvinte: ActionPrompt.
signal action_prompt_changed(text_key: String)

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
# Profiling
# ------------------------------------------------------------------------------------

# Pede a abertura da tela de profiling do espírito de um NPC. Pedido: espera exatamente 1 ouvinte, e
# o logger acusa no console quando a contagem não é essa.
# Emissor: SpiritInteraction (e o menu de debug). Ouvinte: ProfilingScreen.
signal profiling_requested(npc_id: StringName)

# Emitido quando a tela de profiling abre.
# Emissor: ProfilingScreen. Ouvintes: DreamHud (esconde o botão de acordar enquanto a tela está na
# frente).
signal profiling_opened(npc_id: StringName)

# Emitido quando a tela de profiling fecha, pelo botão "Sair" ou por o jogador ter acordado.
# Emissor: ProfilingScreen. Ouvintes: DreamHud.
signal profiling_closed(npc_id: StringName)

# Emitido quando uma palavra nova entra no glossário de um NPC. Releitura não emite: quem já tinha a
# palavra não recebe o aviso de novo.
# Emissor: ProfilingJournal. Ouvintes: WordDiscoveryToast (o aviso na tela) e, no futuro, o diário.
signal glossary_word_discovered(npc_id: StringName, word_id: StringName)

# Emitido quando TODAS as histórias de um NPC estão resolvidas — o jogador entendeu por que aquele
# NPC está na cidade.
# Emissor: ProfilingJournal. Ouvintes: ProfilingScreen (o jogador acorda) e, no futuro, o diálogo
# que convence o NPC a sair da cidade.
signal npc_profiling_completed(npc_id: StringName)

# O QUE NÃO ESTÁ AQUI, de propósito: "história de emoção resolvida" e "emoção do NPC agendada". Os
# dois são fatos de jogo, mas hoje ninguém escutaria nenhum dos dois — o diário, a música e o
# diálogo, que são os interessados, ainda não existem. Evento sem ouvinte é o erro comum que
# docs/event_bus.md manda evitar, e o logger acusa em tempo de execução. Quando o primeiro ouvinte
# existir, declarar o sinal aqui e emitir em ProfilingJournal.mark_story_solved (ou em
# schedule_emotion_slot) é uma linha em cada lugar; ver docs/sistema_de_profiling.md.

# ------------------------------------------------------------------------------------
# Diálogo
# ------------------------------------------------------------------------------------

# Clicou num NPC: antes de conversation_requested, trava o jogador e os orbes de insight cedo,
# enquanto o Player anda até perto do NPC e a DialogueCamera aproxima de todo mundo. Não passa pelo
# fluxo de debug (Iniciar conversa/Pular para nó emitem conversation_requested direto).
# npc_id é o NPC clicado. Quem mais está na conversa (uma conversa pode ter dois NPCs junto com o
# jogador) sai do roteiro, pelo DialogueCatalog — o evento carrega o fato, não o elenco derivado.
# Emissor: NPCInteraction. Ouvintes: Player, InsightInteractor (travam entrada), NPCDirector
# (segura os NPCs parados, sem virar pro jogador ainda — isso só acontece em conversation_started).
signal conversation_approach_started(conversation_id: StringName, npc_id: StringName)

# Pede o início de uma conversa. Pedido: espera exatamente 1 ouvinte.
# initiator_id é quem puxou a conversa (id do NPC, ou &"" para gatilho e debug); ele é repassado em
# conversation_started para quem precisa segurar aquele NPC.
# Emissor: NPCInteraction (fim da abordagem), debug. Ouvinte: DialogueScreen.
signal conversation_requested(conversation_id: StringName, initiator_id: StringName)

# Emitido quando uma conversa abre.
# Emissor: DialogueScreen. Ouvintes: Player (trava movimento, redundante se já veio de
# conversation_approach_started), NPCDirector (segura os NPCs da conversa e vira eles pro jogador),
# InsightInteractor (desliga orbes, idem Player), ProfilingJournal (marca o NPC abordado como
# encontrado no mundo real, o que faz ele aparecer no sonho).
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
