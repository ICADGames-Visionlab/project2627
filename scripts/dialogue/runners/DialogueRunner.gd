# DialogueRunner.gd — Interface base dos adaptadores de conteúdo (SPEC §5.1). As regras comuns
# (was_chosen_before, nó visitado, emissão sempre adiada, corte de fala de cabeça bloqueada) vivem
# aqui, não em cada adaptador, para não divergirem entre MemoryRunner e os demais.
class_name DialogueRunner
extends RefCounted

signal step_ready(step: DialogueStep)
# Só o MemoryRunner emite hoje (nó inexistente); a base declara porque é parte do contrato de
# qualquer DialogueRunner, não só de quem já usa.
@warning_ignore("unused_signal")
signal failed(reason: String)

# Debug "Ignorar condições" (SPEC §15.1): força toda escolha a ficar disponível.
static var ignore_conditions: bool = false

var conversation_id: StringName
var game_state: DialogueGameState

var _current_step: DialogueStep


func start(p_conversation_id: StringName, start_node_id: StringName = &"") -> void:
	conversation_id = p_conversation_id
	_start(start_node_id)


func advance() -> void:
	_advance()


func choose(choice_id: StringName) -> void:
	if _current_step == null or not _step_has_choice(_current_step, choice_id):
		push_warning("[Dialogue] - AVISO: escolha \"%s\" ignorada; não está na etapa atual" % choice_id)
		return
	_choose(choice_id)


func get_node_ids() -> PackedStringArray:
	return PackedStringArray()


func _start(_start_node_id: StringName) -> void:
	push_error("[Dialogue] - DialogueRunner._start() não implementado por %s" % get_script().resource_path)


func _advance() -> void:
	push_error("[Dialogue] - DialogueRunner._advance() não implementado por %s" % get_script().resource_path)


func _choose(_choice_id: StringName) -> void:
	push_error("[Dialogue] - DialogueRunner._choose() não implementado por %s" % get_script().resource_path)


func _step_has_choice(step: DialogueStep, choice_id: StringName) -> bool:
	for choice: DialogueChoice in step.choices:
		if choice.choice_id == choice_id:
			return true
	return false


# Aplica was_chosen_before/ignore_conditions, marca o nó como visitado e emite com call_deferred
# (nunca no meio da própria chamada, para não reentrar na máquina de estados da tela). Fala de
# cabeça ainda bloqueada é pulada silenciosamente para o jogo, com log, avançando sozinho.
func _emit_step(step: DialogueStep) -> void:
	if step.lines.size() == 1 and _is_blocked_head_line(step.lines[0]):
		var line: DialogueLine = step.lines[0]
		print("[Dialogue] - Fala \"%s\" pulada: cabeça \"%s\" bloqueada" % [line.line_id, line.speaker_id])
		advance()
		return
	# Sandbox do Passeio automático (SPEC §15.4): não suja "já visitado"/"já escolhida" do save real.
	var is_sandbox: bool = game_state != null and game_state.sandbox
	for choice: DialogueChoice in step.choices:
		choice.was_chosen_before = false if is_sandbox else DialogueState.was_chosen(choice.choice_id)
		if ignore_conditions:
			choice.is_available = true
	if not is_sandbox:
		DialogueState.mark_visited(step.node_id)
	_current_step = step
	call_deferred("_deferred_emit_step", step)


func _deferred_emit_step(step: DialogueStep) -> void:
	step_ready.emit(step)


func _is_blocked_head_line(line: DialogueLine) -> bool:
	var speaker: String = String(line.speaker_id)
	if not speaker.begins_with("head:"):
		return false
	return not HeadRegistry.has_head(StringName(speaker.substr(5)))
