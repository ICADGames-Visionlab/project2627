# DialogueState.gd — Escolhas e nós já visitados, sobrevivendo à troca de cena sem Autoload
# (V9 do SPEC): tudo "static". Se o Lead preferir Autoload no futuro, a API muda só de forma
# (static -> instância), não de assinatura.
#
# SAVE: participante "dialogue" do SaveManager. Sem _ready(), o registro acontece na primeira consulta
# (ensure_registered); com partida aberta, o registro tardio do SaveManager já entrega a seção salva
# nessa hora. Toda mudança pede gravação (request_save); carregar (from_dict) não pede.
class_name DialogueState
extends RefCounted

const SAVE_KEY: String = "dialogue"
const CHOSEN_KEY: String = "chosen"
const VISITED_KEY: String = "visited"

static var _chosen: Dictionary = {}
static var _visited: Dictionary = {}
static var _registered: bool = false


# Entra no save na primeira consulta, porque script static não tem _ready(). Os Callables são sobre o
# próprio script (métodos static), então valem pelo jogo inteiro e nunca precisam de unregister.
static func ensure_registered() -> void:
	if _registered:
		return
	_registered = true
	SaveManager.register_participant(SAVE_KEY, Callable(DialogueState, "to_dict"),
		Callable(DialogueState, "from_dict"))


# A escolha já foi feita alguma vez nesta partida?
static func was_chosen(choice_id: StringName) -> bool:
	ensure_registered()
	return _chosen.has(choice_id)


# Marca a escolha e pede gravação. Idempotente: repetir não gera pedido à toa.
static func mark_chosen(choice_id: StringName) -> void:
	ensure_registered()
	if _chosen.has(choice_id):
		return
	_chosen[choice_id] = true
	SaveManager.request_save()


# O nó da conversa já foi visitado alguma vez nesta partida?
static func was_visited(node_id: StringName) -> bool:
	ensure_registered()
	return _visited.has(node_id)


# Marca o nó como visitado e pede gravação. Idempotente, como mark_chosen().
static func mark_visited(node_id: StringName) -> void:
	ensure_registered()
	if _visited.has(node_id):
		return
	_visited[node_id] = true
	SaveManager.request_save()


# [DEBUG] Esquece escolhas e nós visitados da partida ativa (e grava). O novo jogo não passa por aqui:
# ele chega como from_dict({}).
static func reset_choices() -> void:
	ensure_registered()
	_chosen.clear()
	_visited.clear()
	SaveManager.request_save()


# Seção "dialogue" do save: só String, que é o que o JSON devolve igual.
static func to_dict() -> Dictionary:
	var chosen_ids: Array[String] = []
	for id: StringName in _chosen:
		chosen_ids.append(String(id))
	chosen_ids.sort()
	var visited_ids: Array[String] = []
	for id: StringName in _visited:
		visited_ids.append(String(id))
	visited_ids.sort()
	return { CHOSEN_KEY: chosen_ids, VISITED_KEY: visited_ids }


# Recebe a seção "dialogue"; {} é o novo jogo. StringName(str(x)): o save serializa por JSON, que
# devolve String, nunca StringName de volta.
static func from_dict(data: Dictionary) -> void:
	_chosen.clear()
	_visited.clear()
	for raw_id: Variant in data.get(CHOSEN_KEY, []):
		_chosen[StringName(str(raw_id))] = true
	for raw_id: Variant in data.get(VISITED_KEY, []):
		_visited[StringName(str(raw_id))] = true
	print("[Dialogue] - Estado de diálogo carregado do save (%d escolhas, %d nós visitados)" % [
		_chosen.size(), _visited.size()])
