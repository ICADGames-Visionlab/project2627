# EventBus.gd — Singleton de eventos do projeto.
# Sistemas não chamam uns aos outros: quem faz algo anuncia o fato aqui, e quem se interessa
# escuta. O bus só transporta — não guarda estado e não tem lógica.
#
# Todos os eventos do jogo ficam neste arquivo, com um comentário acima dizendo quem emite e
# quem escuta. Abrir este arquivo é ver o jogo inteiro conversando.
#
# Como usar:
#   EventBus.day_started.emit(3)                    # publicar
#   EventBus.day_started.connect(_on_day_started)    # escutar
#
# O guia completo está em docs/event_bus.md.
extends Node

# ---------------------------------------------------------------------------------------------
# Produção
# ---------------------------------------------------------------------------------------------

# Emitido quando o jogador coleta o produto de uma fonte de produção.
# Emissor: ProductionSource. Ouvintes: InventorySystem, QuestSystem.
signal production_collected(event: ProductionCollectedEvent)

# ---------------------------------------------------------------------------------------------
# Mundo
# ---------------------------------------------------------------------------------------------

# Emitido no instante em que um novo dia de jogo começa, com o número do dia já atualizado.
# Emissor: WorldClock. Ouvintes: ProductionSource, QuestSystem, HUDController.
signal day_started(day: int)

# Emitido quando o dia passa do limiar de anoitecer. Não repete dentro do mesmo dia.
# Emissor: WorldClock. Ouvinte: AudioDirector.
signal night_started()

# ---------------------------------------------------------------------------------------------
# Inventário
# ---------------------------------------------------------------------------------------------

# Emitido após um item entrar no inventário, com o total resultante já consolidado.
# Emissor: InventorySystem. Ouvinte: HUDController.
signal item_added(event: ItemTransactionEvent)

# ---------------------------------------------------------------------------------------------
# Economia
# ---------------------------------------------------------------------------------------------

# Emitido a cada mudança no ouro do jogador, com o valor novo e o delta aplicado.
# Emissor: Wallet. Ouvinte: HUDController.
signal gold_changed(new_value: int, delta: int)

# ---------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------

# Pedido de gravação do jogo. Diferente dos demais, não é um fato: é um pedido, e espera
# exatamente um sistema atendendo.
# Emissor: menus. Ouvinte esperado: SaveManager — que ainda não existe, de propósito: é o
# contra-exemplo da cena de validação, e o logger acusa o pedido sem dono.
signal save_requested()


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
