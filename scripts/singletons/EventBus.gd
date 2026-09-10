# EventBus.gd — Singleton de eventos do projeto.
# Sistemas não chamam uns aos outros: quem faz algo anuncia o fato aqui, e quem se interessa
# escuta. O bus só transporta — não guarda estado e não tem lógica.
#
# Todos os eventos do jogo ficam neste arquivo, agrupados por módulo, cada um com um comentário
# acima dizendo quem emite e quem escuta. Abrir este arquivo é ver o jogo inteiro conversando.
#
# ESTADO ATUAL: os eventos do sistema de insights. Eventos nascem junto com o sistema que produz
# os fatos — criar antes disso seria adivinhar features que o conceito do jogo ainda não decidiu.
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

# ----------------------------------------------------------------------------------------
# Insights
# ----------------------------------------------------------------------------------------

# Emitido quando o jogador lê um insight, seja a descoberta ou uma releitura (first_time no payload
# separa as duas).
# Emissor: InsightDirector. Ouvintes: InsightJournal (marca o lido e concede a flag) e
# InsightSource (reage à mudança de estado do próprio marcador).
signal insight_revealed(event: InsightRevealedEvent)

# Pede a exibição de uma fala na tela de diálogo. Pedido: espera exatamente 1 ouvinte, e o logger
# acusa no console quando a contagem não é essa — é assim que esquecer de desligar o placeholder no
# dia em que a tela real entrar vira erro visível em vez de duas telas abrindo juntas.
# Emissor: InsightDirector. Ouvinte: a tela de diálogo (PlaceholderDialogueScreen por enquanto).
signal dialogue_requested(head_id: StringName, text_key: String)

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
