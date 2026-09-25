## InventoryUI - painel que lista as "evidências" (itens) do inventário do jogador e permite
## largar ou destruir cada uma.
##
## COMO USAR: já vem instanciada em main.tscn, uma vez só. Ela se vira sozinha: encontra o
## Inventory do jogador pelo grupo (ver Inventory.GROUP_NAME) e abre/fecha com a ação de input
## "toggle_inventory" (tecla I). Não pausa o jogo — diferente do PauseMenu, o jogador pode
## consultar as evidências sem interromper a cena.
##
## Por que "Evidências" e não "Inventário": é assim que a issue #29 pediu que a UI chamasse os
## itens do jogador. O código continua em inglês (ItemData, Inventory, item_id) — só o TEXTO
## exibido ao jogador reflete o tema do jogo (ver INVENTORY_TITLE em translations.csv).
extends CanvasLayer

## Espaço para variáveis

const TOGGLE_ACTION: StringName = &"toggle_inventory"

var _inventory: Inventory

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _slots_grid: GridContainer = $Root/Center/Panel/Margin/Layout/Slots
@onready var _empty_label: Label = $Root/Center/Panel/Margin/Layout/EmptyLabel
@onready var _close_button: Button = $Root/Center/Panel/Margin/Layout/Header/Close

## Espaço para funções nativas

func _ready() -> void:
	_root.hide()
	_close_button.pressed.connect(_on_close_pressed)

	_inventory = get_tree().get_first_node_in_group(Inventory.GROUP_NAME) as Inventory
	if _inventory == null:
		push_warning("[InventoryUI] - Nenhum Inventory encontrado no grupo \"%s\"; painel ficará vazio" % Inventory.GROUP_NAME)
		return

	_inventory.item_added.connect(_on_inventory_changed)
	_inventory.item_dropped.connect(_on_inventory_changed)
	_inventory.item_destroyed.connect(_on_inventory_changed)
	_rebuild_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		_toggle()

## Espaço para funções personalizadas

# Abre/fecha o painel. Reconstrói a lista ao abrir para garantir que ela reflita o estado atual
# mesmo que o inventário tenha mudado enquanto o painel estava fechado (sinais só chegam aqui
# quando o nó existe, e existe desde o _ready() — então isso é redundante hoje, mas barato e à
# prova de futuras mudanças em quando o painel é instanciado).
func _toggle() -> void:
	if _root.visible:
		_root.hide()
	else:
		_rebuild_slots()
		_root.show()
	print("[InventoryUI] - Painel %s" % ("aberto" if _root.visible else "fechado"))


func _on_close_pressed() -> void:
	_root.hide()


func _on_inventory_changed(_item: ItemData, _amount: int) -> void:
	if _root.visible:
		_rebuild_slots()


# Reconstrói a lista de slots do zero a partir do estado atual do inventário. Simples e barato o
# bastante para o tamanho esperado do inventário do jogo — ver docs/Inventory.md, "Limitações
# atuais", se isso um dia precisar de diffing em vez de reconstrução total.
#
# remove_child() antes do queue_free(): queue_free() só remove o nó no FIM do frame, então sem o
# remove_child() os slots antigos continuam filhos de _slots_grid no mesmo frame em que os novos
# são adicionados abaixo — um frame com as duas versões visíveis (flicker) e os botões antigos
# ainda com pressed conectado.
func _rebuild_slots() -> void:
	for child: Node in _slots_grid.get_children():
		_slots_grid.remove_child(child)
		child.queue_free()

	var stacks: Array[ItemStack] = _inventory.get_stacks() if _inventory != null else []
	_empty_label.visible = stacks.is_empty()

	for stack: ItemStack in stacks:
		_slots_grid.add_child(_build_slot(stack))


# Monta um slot (ícone, nome, quantidade e os botões Largar/Destruir) para uma pilha. Construído
# em código, e não como cena separada, porque o conteúdo muda por completo a cada mudança no
# inventário — não há estado de UI (foco, scroll) por slot que valha a pena preservar entre nós.
func _build_slot(stack: ItemStack) -> Control:
	var item: ItemData = stack.item

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 0)

	# description_key vira o tooltip do slot — é o único lugar em que ela é exibida hoje (ver
	# ItemData.gd). Sem isso, description_key era só um campo preenchido e traduzido à toa.
	if item.description_key != &"":
		panel.tooltip_text = tr(item.description_key)

	var layout: VBoxContainer = VBoxContainer.new()
	panel.add_child(layout)

	if item.icon != null:
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = item.icon
		icon_rect.custom_minimum_size = Vector2(48, 48)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layout.add_child(icon_rect)

	var name_label: Label = Label.new()
	# Placeholder nomeado (ver docs/localizacao_Godot.md, "Placeholders / textos dinâmicos") em vez
	# de string hardcoded: "5x" em inglês costuma virar "(5)" ou "x5" em pt_BR, então a ordem/forma
	# não pode ficar fixa no código.
	name_label.text = tr(&"INVENTORY_SLOT_LABEL").format({
		"name": tr(item.display_name_key),
		"amount": stack.amount,
	})
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(name_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	layout.add_child(buttons)

	var drop_button: Button = Button.new()
	drop_button.text = tr(&"INVENTORY_DROP")
	drop_button.pressed.connect(_on_drop_pressed.bind(item.id))
	buttons.add_child(drop_button)

	if item.destructible:
		var destroy_button: Button = Button.new()
		destroy_button.text = tr(&"INVENTORY_DESTROY")
		destroy_button.pressed.connect(_on_destroy_pressed.bind(item.id))
		buttons.add_child(destroy_button)

	return panel


func _on_drop_pressed(item_id: StringName) -> void:
	_inventory.drop_item(item_id)


func _on_destroy_pressed(item_id: StringName) -> void:
	_inventory.destroy_item(item_id)
