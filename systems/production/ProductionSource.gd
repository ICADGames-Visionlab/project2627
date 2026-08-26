# ProductionSource.gd — Uma fonte de produção genérica: inicia um ciclo, leva alguns dias para
# concluir e entrega um produto ao ser coletada.
# A fonte não conhece inventário, HUD nem missões: apenas anuncia o que aconteceu.
#
# Serve de molde para qualquer mecânica de produção (plantio, criação, extração, fabricação).
class_name ProductionSource
extends Node2D

enum State { IDLE, WORKING, READY }

@export var source_id: int = 0
@export var product_id: StringName = &"sample_resource"
@export var days_to_complete: int = 2
@export var base_output_amount: int = 3
@export var quality_bonus_chance: float = 0.15

var _state: State = State.IDLE
var _days_worked: int = 0
var _current_day: int = 1

@onready var _visual: Polygon2D = $Visual
@onready var _state_label: Label = $StateLabel


func _ready() -> void:
	# Estado inicial vem do dono do estado; a partir daqui, só os deltas via bus. Sem esta
	# consulta, uma fonte criada no meio da partida acharia que ainda é o dia 1.
	var clock: WorldClock = get_tree().get_first_node_in_group(&"world_clock") as WorldClock
	if clock != null:
		_current_day = clock.current_day
	EventBus.day_started.connect(_on_day_started)
	_refresh_visual()


# Inicia um ciclo de produção. Ignora o pedido se a fonte já estiver ocupada.
# Não publica nada: nenhum sistema reage ao início do ciclo nesta validação.
func start_production(new_product_id: StringName) -> bool:
	if _state != State.IDLE:
		return false
	product_id = new_product_id
	_state = State.WORKING
	_days_worked = 0
	_refresh_visual()
	print("[Production] - Fonte %d iniciou a produção de \"%s\"" % [source_id, product_id])
	return true


# Coleta o produto pronto e publica o fato para os demais sistemas.
# O payload é um snapshot: nenhum listener recebe referência à própria fonte, porque o evento
# pode ser lido depois que ela já saiu da árvore.
func collect() -> bool:
	if _state != State.READY:
		return false

	var collected: ProductionCollectedEvent = ProductionCollectedEvent.new(
		source_id, product_id, _calculate_amount(), _calculate_quality(),
		global_position, _current_day
	)
	_reset()
	EventBus.production_collected.emit(collected)
	print("[Production] - Fonte %d coletada (%s x%d)"
		% [source_id, collected.product_id, collected.amount])
	return true


func is_ready() -> bool:
	return _state == State.READY


func is_idle() -> bool:
	return _state == State.IDLE


# Avança o ciclo a cada novo dia. Roda uma vez por dia de jogo por fonte — nunca por frame.
# Com centenas de fontes, esta contagem migra para um sistema com laço único que emite um
# evento agregado por tick, em vez de N eventos.
func _on_day_started(day: int) -> void:
	_current_day = day
	if _state != State.WORKING:
		return

	_days_worked += 1
	if _days_worked >= days_to_complete:
		_state = State.READY
	_refresh_visual()


# Quantidade produzida. Isolado em função própria porque é o ponto natural de entrada para
# bônus de ferramenta, insumo e habilidade do jogador.
func _calculate_amount() -> int:
	return base_output_amount


# Qualidade do produto: 0 é padrão, 1 é a produção bonificada.
func _calculate_quality() -> int:
	return 1 if randf() < quality_bonus_chance else 0


# Devolve a fonte ao estado ocioso depois de coletar.
func _reset() -> void:
	_state = State.IDLE
	_days_worked = 0
	_refresh_visual()


# Atualiza a cor e o rótulo da fonte. O rótulo existe só para leitura na cena de validação
# manual; esta cena é placeholder e não vai para build de jogador.
func _refresh_visual() -> void:
	if _visual == null:
		return
	match _state:
		State.IDLE:
			_visual.color = Color(0.30, 0.30, 0.34)
			_state_label.text = "ocioso"
		State.WORKING:
			_visual.color = Color(0.30, 0.48, 0.62)
			_state_label.text = "produzindo %d/%d" % [_days_worked, days_to_complete]
		State.READY:
			_visual.color = Color(0.85, 0.70, 0.20)
			_state_label.text = "pronto"
