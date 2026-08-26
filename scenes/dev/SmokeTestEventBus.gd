# SmokeTestEventBus.gd — Verificação ponta a ponta do fluxo de produção e do ciclo dia/noite,
# executável em headless e sem depender de nenhum addon.
# Motivação: sem framework de testes, esta é a única verificação automática do caminho
# crítico do bus. Confere efeitos que só podem ter acontecido através dele.
#
# Como usar (na raiz do projeto):
#   godot --headless --path . res://scenes/dev/SmokeTestEventBus.tscn
#
# Sai com código 1 se qualquer verificação falhar.
#
# É uma CENA, e não um script rodado com --script, porque scripts de MainLoop são compilados
# antes do registro dos Autoloads: naquele modo o identificador global EventBus não existe e
# nenhum script de gameplay que o use chega a compilar.
extends Node

const SOURCE_SCENE: String = "res://systems/production/ProductionSource.tscn"
const SOURCE_COUNT: int = 3
const PRODUCT_ID: StringName = &"sample_resource"
const RESOURCE_PRICE: int = 12

var _step: int = 0
var _finished: bool = false
var _failures: PackedStringArray = PackedStringArray()

var _clock: WorldClock
var _wallet: Wallet
var _inventory: InventorySystem
var _quests: QuestSystem
var _sources: Array[ProductionSource] = []


func _process(_delta: float) -> void:
	if _finished:
		return
	_step += 1
	match _step:
		1:
			_build_world()
		2:
			_start_all()
		3, 4:
			_clock.advance_day()
		5:
			_collect_all()
		6:
			_sell_one()
		7:
			_verify()


# Monta a fatia vertical em memória: os mesmos sistemas da cena de validação manual,
# adicionados na ordem em que a cena os declara.
func _build_world() -> void:
	_clock = WorldClock.new()
	_clock.name = &"WorldClock"
	add_child(_clock)

	_wallet = Wallet.new()
	_wallet.name = &"Wallet"
	add_child(_wallet)

	_inventory = InventorySystem.new()
	_inventory.name = &"InventorySystem"
	add_child(_inventory)

	_quests = QuestSystem.new()
	_quests.name = &"QuestSystem"
	add_child(_quests)

	var audio: AudioDirector = AudioDirector.new()
	audio.name = &"AudioDirector"
	add_child(audio)

	var source_scene: PackedScene = load(SOURCE_SCENE) as PackedScene
	for index: int in SOURCE_COUNT:
		var source: ProductionSource = source_scene.instantiate() as ProductionSource
		source.source_id = index + 1
		add_child(source)
		_sources.append(source)

	_quests.start_quest(&"collect_ten_units")
	_quests.start_quest(&"reach_day_three")
	print("[SmokeTest] - Mundo montado com %d fontes de produção" % _sources.size())


func _start_all() -> void:
	for source: ProductionSource in _sources:
		_expect(source.start_production(PRODUCT_ID),
			"fonte %d iniciou a produção" % source.source_id)


func _collect_all() -> void:
	for source: ProductionSource in _sources:
		_expect(source.is_ready(), "fonte %d ficou pronta em 2 dias" % source.source_id)
		_expect(source.collect(), "fonte %d foi coletada" % source.source_id)


func _sell_one() -> void:
	_expect(_inventory.remove_item(PRODUCT_ID, 1), "venda removeu 1 item do inventário")
	_wallet.add_gold(RESOURCE_PRICE)


# Confere os efeitos que só podem ter acontecido através do bus: nenhum destes sistemas
# tem referência aos outros.
func _verify() -> void:
	var expected_output: int = SOURCE_COUNT * 3

	_expect(_inventory.get_amount(PRODUCT_ID) == expected_output - 1,
		"inventário recebeu a produção pelo bus e descontou a venda (esperado %d, obtido %d)"
			% [expected_output - 1, _inventory.get_amount(PRODUCT_ID)])

	_expect(_quests.get_progress(&"collect_ten_units") == expected_output,
		"missão de coleta avançou pelo mesmo evento (esperado %d, obtido %d)"
			% [expected_output, _quests.get_progress(&"collect_ten_units")])

	_expect(_quests.get_progress(&"reach_day_three") == 2,
		"missão de dias avançou apenas nas viradas de dia (esperado 2, obtido %d)"
			% _quests.get_progress(&"reach_day_three"))

	_expect(_wallet.current_gold == _wallet.starting_gold + RESOURCE_PRICE,
		"carteira creditou a venda (esperado %d, obtido %d)"
			% [_wallet.starting_gold + RESOURCE_PRICE, _wallet.current_gold])

	_verify_cascade_depth()
	_report()


# Uma coleta pode gerar no máximo um evento novo. Se item_added aparecer
# mais vezes que production_collected, alguma cadeia cresceu além do permitido.
func _verify_cascade_depth() -> void:
	var logger: EventBusLogger = EventBus.get_logger()
	if logger == null:
		_failures.append("instrumentação ausente: rodar em build de debug")
		return

	var totals: Dictionary = logger.get_total_by_event()
	var collections: int = int(totals.get(&"production_collected", 0))
	var additions: int = int(totals.get(&"item_added", 0))
	_expect(collections == SOURCE_COUNT,
		"production_collected emitido %d vezes" % collections)
	_expect(additions == collections,
		"cada coleta gerou exatamente um item_added: %d coletas, %d entradas"
			% [collections, additions])


# Registra o resultado de uma verificação, no formato de log exigido pelo Guideline.
func _expect(condition: bool, description: String) -> void:
	if condition:
		print("[SmokeTest] - OK: %s" % description)
		return
	_failures.append(description)
	printerr("[SmokeTest] - FALHA: %s" % description)


# Fecha a execução com o código de saída correspondente ao resultado.
func _report() -> void:
	_finished = true
	if _failures.is_empty():
		print("[SmokeTest] - Fluxo validado sem falhas")
		get_tree().quit(0)
		return
	printerr("[SmokeTest] - %d verificações falharam" % _failures.size())
	get_tree().quit(1)
