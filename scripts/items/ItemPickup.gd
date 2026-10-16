## ItemPickup - item largado no chão, coletado automaticamente quando o jogador encosta nele.
##
## COMO USAR: instancie ItemPickup.tscn (ou deixe Inventory.drop_item() instanciar sozinho),
## preencha "item" e "amount" e adicione à árvore. Assim que o Player entra na Area2D, o item vai
## pro Inventory dele e este nó se destrói sozinho.
##
## Se "item" ficar vazio (null) — instância mal configurada — o pickup se destrói sozinho no
## _ready() e avisa no console; é mais seguro que deixar um objeto fantasma sem efeito no mundo.
##
## CAMADAS (ItemPickup.tscn): collision_mask = 2, a camada "Agentes", onde o Player e os NPCs estão.
## Com a máscara padrão (1, "world") a Area2D não enxerga o Player e o item largado nunca mais volta
## pro inventário. collision_layer = 0 porque ninguém precisa detectar o pickup. NPC também está na
## camada 2, mas _on_body_entered filtra por Player.
##
## NO SAVE: quem grava os itens no chão é a GameSession (seção "pickups"), achando todos pelo grupo
## GROUP. Um pickup posto numa cena no editor que o jogador já pegou não volta ao recarregar; um que o
## jogador largou volta onde estava. O pickup em si não sabe de save nenhum.
class_name ItemPickup
extends Area2D

## Espaço para constantes

# Grupo em que todo ItemPickup entra (ver _enter_tree). É por ele que a GameSession acha os itens no
# chão para gravar quais foram pegos e quais o jogador largou.
const GROUP: StringName = &"item_pickup"

## Espaço para variáveis

@export var item: ItemData
@export_range(1, 99, 1) var amount: int = 1

# Tempo (em segundos) que o pickup fica "surdo" pro próprio corpo que acabou de largá-lo, antes
# de aceitar ser coletado de novo. Existe pro caso comum de a maioria dos jogos: jogador larga o
# item e continua parado ali perto (ou o offset de drop não foi longe o bastante pra separar os
# colisores) — sem esse cooldown, o mesmo corpo recolhe o item de volta assim que ele entra em
# contato de novo. Variável de balanceamento: ajuste no Inspector.
@export_range(0.0, 3.0, 0.05) var pickup_delay: float = 0.5

# Fica false até pickup_delay terminar (ver _ready()). Enquanto false, _on_body_entered ignora
# qualquer corpo que entre na área — inclusive quem acabou de largar o item.
var _collectible: bool = false

## Espaço para variáveis onready

@onready var _sprite: Sprite2D = $Sprite2D

## Espaço para funções nativas

# Entra no grupo em _enter_tree, e não em _ready: a GameSession procura os pickups no _ready dela, e
# todo _enter_tree da cena roda antes de qualquer _ready, então a ordem dos nós na árvore não importa.
func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# A GameSession pode ter removido este pickup antes do _ready dele (o jogador já o tinha pego
	# nesta partida). Sem isto ele ainda montaria o sprite e esperaria o cooldown à toa.
	if is_queued_for_deletion():
		return
	if item == null:
		push_warning("[ItemPickup] - Instanciado sem item definido; destruindo")
		queue_free()
		return

	_sprite.texture = item.icon
	body_entered.connect(_on_body_entered)

	# Cooldown antes de aceitar coleta (ver comentário de pickup_delay). await em vez de Timer +
	# connect(): mesmo padrão usado em GameManager.gd pra esperas simples, sem precisar de um nó
	# a mais na cena nem de desconectar nada depois.
	await get_tree().create_timer(pickup_delay).timeout
	_collectible = true

	# body_entered só dispara na TRANSIÇÃO de entrada. Um corpo que já estava dentro da área
	# quando o cooldown terminou — jogador parado em cima do pickup, ou que entrou durante os
	# pickup_delay segundos "surdos" — nunca dispara o sinal de novo, e o item ficava ali pra
	# sempre até o jogador sair da área e voltar a entrar (sem nenhum aviso do motivo). Revarrer os
	# corpos já sobrepostos assim que o cooldown acaba resolve.
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)

## Espaço para funções personalizadas

# Diz se este pickup foi posto numa cena no editor (true) ou criado com o jogo rodando, largado pelo
# jogador ou recriado do save (false). Nó que veio de um .tscn tem owner; nó criado por código, não.
# A GameSession grava os dois de jeitos diferentes: o primeiro pelo caminho na cena, o segundo inteiro.
func is_placed_in_scene() -> bool:
	return owner != null


# Coleta o item para o Inventory do corpo que entrou na área, se for o Player e o cooldown de
# pickup_delay já tiver terminado. Pega o inventário direto do corpo (e não pelo grupo
# Inventory.GROUP_NAME) porque aqui já sabemos exatamente de quem estamos falando — ver
# docs/Inventory.md, "Por que NÃO é um Singleton".
func _on_body_entered(body: Node2D) -> void:
	if not _collectible:
		return
	if not body is Player:
		return

	var inventory: Inventory = body.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		push_warning("[ItemPickup] - \"%s\" não tem um nó Inventory filho" % body.name)
		return

	inventory.add_item(item, amount)
	print("[ItemPickup] - \"%s\" coletado (x%d)" % [item.id, amount])
	queue_free()
