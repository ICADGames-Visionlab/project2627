## ItemPickup - item largado no chão, coletado automaticamente quando o jogador encosta nele.
##
## COMO USAR: instancie ItemPickup.tscn (ou deixe Inventory.drop_item() instanciar sozinho),
## preencha "item" e "amount" e adicione à árvore. Assim que o Player entra na Area2D, o item vai
## pro Inventory dele e este nó se destrói sozinho.
##
## Se "item" ficar vazio (null) — instância mal configurada — o pickup se destrói sozinho no
## _ready() e avisa no console; é mais seguro que deixar um objeto fantasma sem efeito no mundo.
class_name ItemPickup
extends Area2D

## Espaço para variáveis

@export var item: ItemData
@export_range(1, 99, 1) var amount: int = 1

## Espaço para variáveis onready

@onready var _sprite: Sprite2D = $Sprite2D

## Espaço para funções nativas

func _ready() -> void:
	if item == null:
		push_warning("[ItemPickup] - Instanciado sem item definido; destruindo")
		queue_free()
		return

	_sprite.texture = item.icon
	body_entered.connect(_on_body_entered)

## Espaço para funções personalizadas

# Coleta o item para o Inventory do corpo que entrou na área, se for o Player. Pega o inventário
# direto do corpo (e não pelo grupo Inventory.GROUP_NAME) porque aqui já sabemos exatamente de
# quem estamos falando — ver docs/Inventory.md, "Por que NÃO é um Singleton".
func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return

	var inventory: Inventory = body.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		push_warning("[ItemPickup] - \"%s\" não tem um nó Inventory filho" % body.name)
		return

	inventory.add_item(item, amount)
	print("[ItemPickup] - \"%s\" coletado (x%d)" % [item.id, amount])
	queue_free()
