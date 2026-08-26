# HUDController.gd — Único nó de UI conectado ao EventBus.
# Motivação: se cada widget escutasse o bus, um gold_changed teria doze listeners e o catálogo
# ficaria ilegível. O controlador escuta uma vez e distribui internamente por chamada direta.
class_name HUDController
extends CanvasLayer

var _last_item_id: StringName = &""

@onready var _gold_label: Label = $Stats/GoldLabel
@onready var _day_label: Label = $Stats/DayLabel
@onready var _last_item_label: Label = $Stats/LastItemLabel


func _ready() -> void:
	# Os valores iniciais vêm dos donos do estado; o bus entrega apenas as mudanças.
	# Sem isso o HUD ficaria vazio até a primeira emissão.
	var wallet: Wallet = get_tree().get_first_node_in_group(&"wallet") as Wallet
	_set_gold(wallet.current_gold if wallet != null else 0)

	var clock: WorldClock = get_tree().get_first_node_in_group(&"world_clock") as WorldClock
	_set_day(clock.current_day if clock != null else 1)
	_last_item_label.text = ""

	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.item_added.connect(_on_item_added)


# O delta chega no evento, mas o HUD só precisa do valor novo: ignorá-lo é intencional.
func _on_gold_changed(new_value: int, _delta: int) -> void:
	_set_gold(new_value)


func _on_day_started(day: int) -> void:
	_set_day(day)


func _on_item_added(event: ItemTransactionEvent) -> void:
	_last_item_id = event.item_id
	_last_item_label.text = tr("hud_last_item").format({
		"item": String(event.item_id), "amount": event.amount
	})


# Atualiza o rótulo de ouro. Texto sempre por chave de localização (Guideline: tr()).
func _set_gold(value: int) -> void:
	_gold_label.text = tr("hud_gold").format({"gold": value})


# Atualiza o rótulo de dia, na mesma base de localização do restante do HUD.
func _set_day(day: int) -> void:
	_day_label.text = tr("hud_day").format({"day": day})
