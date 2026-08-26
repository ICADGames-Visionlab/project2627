# QuestSystem.gd — Dono do progresso das missões.
# Na validação ele é o exemplo de ouvinte puro: escuta os mesmos fatos que o inventário, sem
# que os dois se conheçam e sem depender da ordem em que foram conectados ao bus.
class_name QuestSystem
extends Node

# Catálogo de missões da validação. Em produção isto vira recurso de dados; aqui é um
# placeholder deliberado, com objetivos neutros, só para exercitar o fluxo de eventos.
const DEMO_QUESTS: Dictionary = {
	&"collect_ten_units": {"kind": &"collect", "subject": &"sample_resource", "target": 10},
	&"reach_day_three": {"kind": &"day", "subject": &"", "target": 3},
}

var _active: Dictionary = {}


# Estado de uma missão ativa. Só o QuestSystem escreve nele.
class QuestProgress:
	var kind: StringName = &""
	var subject: StringName = &""
	var target: int = 0
	var progress: int = 0
	var completed: bool = false


func _ready() -> void:
	EventBus.production_collected.connect(_on_production_collected)
	EventBus.day_started.connect(_on_day_started)


# Ativa uma missão do catálogo.
func start_quest(quest_id: StringName) -> bool:
	if _active.has(quest_id) or not DEMO_QUESTS.has(quest_id):
		return false

	var definition: Dictionary = DEMO_QUESTS[quest_id]
	var quest: QuestProgress = QuestProgress.new()
	quest.kind = definition["kind"]
	quest.subject = definition["subject"]
	quest.target = int(definition["target"])
	_active[quest_id] = quest
	print("[Quest] - Missão \"%s\" iniciada (meta %d)" % [quest_id, quest.target])
	return true


func get_progress(quest_id: StringName) -> int:
	if not _active.has(quest_id):
		return 0
	return (_active[quest_id] as QuestProgress).progress


func is_completed(quest_id: StringName) -> bool:
	if not _active.has(quest_id):
		return false
	return (_active[quest_id] as QuestProgress).completed


# Avança as missões de coleta com a quantidade coletada do produto correspondente.
func _on_production_collected(event: ProductionCollectedEvent) -> void:
	_advance_objectives(&"collect", event.product_id, event.amount)


# Avança as missões contadas em dias. O dia inicial não conta como progresso.
func _on_day_started(day: int) -> void:
	if day <= 1:
		return
	_advance_objectives(&"day", &"", 1)


# Aplica o avanço a todas as missões ativas do tipo informado.
func _advance_objectives(kind: StringName, subject: StringName, amount: int) -> void:
	for quest_id: StringName in _active:
		var quest: QuestProgress = _active[quest_id]
		if quest.completed or quest.kind != kind:
			continue
		if not quest.subject.is_empty() and quest.subject != subject:
			continue

		quest.progress = mini(quest.progress + amount, quest.target)
		if quest.progress >= quest.target:
			quest.completed = true
			print("[Quest] - Missão \"%s\" concluída" % quest_id)
