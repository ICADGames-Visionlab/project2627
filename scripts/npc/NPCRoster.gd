## NPCRoster - a lista dos NPCs que existem no jogo.
##
## COMO USAR: res://resources/npcs/npc_roster.tres, apontado no NPCDirector da cena de gameplay.
## Para colocar um NPC novo no mundo, arraste o .tres dele pra cá. Para tirá-lo do jogo sem perder
## o trabalho feito, remova daqui — o arquivo continua existindo.
##
## POR QUE O DIRETOR PRECISA DE TODOS, E NÃO SÓ DOS QUE ESTÃO NESTA CENA: a rotina de qualquer NPC
## pode trazê-lo pra cena atual às 14:00. Se a cena só conhecesse os NPCs colocados nela à mão, um
## NPC nunca chegaria de fora — e é justamente a cidade se movendo que o sistema existe pra fazer.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name NPCRoster
extends Resource

## Espaço para variáveis exportadas

## Os NPCs do jogo.
@export var npcs: Array[NPCDefinition] = []:
	set(value):
		npcs = value
		_refresh_summary()

## Só leitura: quem está no roster e o que está faltando. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

func _init() -> void:
	_refresh_summary()


func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

# O NPC de um id, ou null se não estiver no roster. Usado pelos comandos do menu de debug, que
# recebem o id digitado.
func find(id: StringName) -> NPCDefinition:
	for definition: NPCDefinition in npcs:
		if definition != null and definition.id == id:
			return definition
	return null


# Os ids do roster, na ordem. Serve de sugestão de autocomplete no console de debug.
func get_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for definition: NPCDefinition in npcs:
		if definition != null:
			ids.append(String(definition.id))
	return ids


func _refresh_summary() -> void:
	var lines: PackedStringArray = ["%d NPCs no roster:" % npcs.size()]
	var seen: Dictionary = {}
	var issues: PackedStringArray = []

	for index: int in npcs.size():
		var definition: NPCDefinition = npcs[index]
		if definition == null:
			issues.append("A posição %d está vazia." % index)
			continue

		lines.append("  %s — %d/6 rotinas preenchidas" % [definition.id, _count_routines(definition)])

		# Id repetido é o erro silencioso mais chato possível aqui: o segundo NPC nunca seria
		# encontrado pelo menu de debug, e os dois disputariam o mesmo corpo em cena.
		if seen.has(definition.id):
			issues.append("Id repetido: \"%s\"." % definition.id)
		seen[definition.id] = true

	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()


# Quantos dos seis slots de rotina o NPC tem preenchidos.
func _count_routines(definition: NPCDefinition) -> int:
	var filled: int = 0
	for slot: int in NPCDefinition.EmotionSlot.values():
		for day_type: int in NPCDefinition.DayType.values():
			if definition.get_routine(slot, day_type) != null:
				filled += 1
	return filled
