# DialogueGameState.gd — Fachada exposta aos roteiros e aos runners. Único ponto do sistema de
# diálogo que conhece o InsightJournal: se a flag D3 do PRD extrair um WorldFlags dedicado no
# futuro, muda só este arquivo (SPEC §12.2).
#
# Recebe String, não StringName: é o que a sintaxe de condição dos roteiros passa sem "&".
class_name DialogueGameState
extends RefCounted

# Modo sandbox (SPEC §15.4): flags gravadas num Dictionary local em vez do InsightJournal, e
# chosen()/visited() sempre falso. Usado pelo Passeio automático, para não sujar o save do jogador
# nem a marca "já escolhida" que o jogo de verdade usa (ver o mesmo cuidado em DialogueRunner._emit_step).
var sandbox: bool = false
var _sandbox_flags: Dictionary = {}


func has_flag(flag: String) -> bool:
	if sandbox:
		return _sandbox_flags.has(flag)
	return InsightJournal.has_flag(StringName(flag))


func grant_flag(flag: String) -> void:
	if sandbox:
		_sandbox_flags[flag] = true
		return
	InsightJournal.grant_flag(StringName(flag))


func has_head(head_id: String) -> bool:
	return HeadRegistry.has_head(StringName(head_id))


func chosen(choice_id: String) -> bool:
	if sandbox:
		return false
	return DialogueState.was_chosen(StringName(choice_id))


func visited(node_id: String) -> bool:
	if sandbox:
		return false
	return DialogueState.was_visited(StringName(node_id))


# Hash estável das flags concedidas nesta rodada de sandbox, para o Passeio automático detectar
# estado repetido (node_id, hash) sem comparar dois Dictionary campo a campo.
func sandbox_flags_hash() -> int:
	var keys: Array = _sandbox_flags.keys()
	keys.sort()
	return hash(keys)
