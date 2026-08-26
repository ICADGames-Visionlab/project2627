# EventBusPlayground.gd — Cena de validação manual do Event Bus.
# Motivação: a arquitetura só se valida rodando; esta cena existe para o time exercitar um fluxo
# real de fan-out e observar o overlay de debug (F3) sem depender do jogo final.
#
# É deliberadamente neutra quanto ao conceito do jogo: fontes de produção genéricas, um recurso
# de exemplo e uma venda. Se o conceito mudar, esta cena continua válida — ela testa o bus,
# não a mecânica.
#
# Placeholder: os visuais e os rótulos dos botões desta cena são temporários e não vão para
# build de jogador — por isso não passam por tr().
extends Node2D

@export var resource_price: int = 12
@export var product_id: StringName = &"sample_resource"

@onready var _clock: WorldClock = $WorldClock
@onready var _wallet: Wallet = $Wallet
@onready var _inventory: InventorySystem = $InventorySystem
@onready var _quests: QuestSystem = $QuestSystem
@onready var _sources: Node2D = $ProductionSources


func _ready() -> void:
	_connect_buttons()
	_quests.start_quest(&"collect_ten_units")
	_quests.start_quest(&"reach_day_three")
	print("[Playground] - Cena de validação pronta (F3 abre o overlay do EventBus)")


# Liga os botões do painel de teste. Métodos nomeados, nunca lambdas: conexões anônimas
# não aparecem legíveis nas ferramentas de inspeção de sinais.
func _connect_buttons() -> void:
	var start_button: Button = $Controls/Buttons/StartButton
	var collect_button: Button = $Controls/Buttons/CollectButton
	var skip_day_button: Button = $Controls/Buttons/SkipDayButton
	var sell_button: Button = $Controls/Buttons/SellButton
	var save_button: Button = $Controls/Buttons/SaveButton

	start_button.pressed.connect(_on_start_pressed)
	collect_button.pressed.connect(_on_collect_pressed)
	skip_day_button.pressed.connect(_on_skip_day_pressed)
	sell_button.pressed.connect(_on_sell_pressed)
	save_button.pressed.connect(_on_save_pressed)


# Inicia a produção na primeira fonte ociosa disponível.
func _on_start_pressed() -> void:
	for source: ProductionSource in _sources.get_children():
		if source.is_idle():
			source.start_production(product_id)
			return
	print("[Playground] - Nenhuma fonte ociosa disponível")


# Coleta todas as fontes prontas de uma vez, para exercitar o fan-out do bus.
func _on_collect_pressed() -> void:
	var collected: int = 0
	for source: ProductionSource in _sources.get_children():
		if source.collect():
			collected += 1
	print("[Playground] - %d fontes coletadas" % collected)


func _on_skip_day_pressed() -> void:
	_clock.advance_day()


# Vende um item do inventário: remove do dono do inventário e credita no dono do ouro.
# São dois fatos independentes, cada um emitido pelo seu dono — nenhuma cadeia entre eles.
func _on_sell_pressed() -> void:
	if _inventory.remove_item(product_id, 1):
		_wallet.add_gold(resource_price)
		return
	print("[Playground] - Nada para vender")


# Demonstra deliberadamente o alerta de comando sem dono: não existe SaveManager nesta cena,
# então o logger deve acusar "comando ui.save_requested tem 0 listeners".
func _on_save_pressed() -> void:
	EventBus.save_requested.emit()
