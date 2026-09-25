# DialogueAutoWalker.gd — "Passeio automático" (SPEC §15.4): roda um runner sem a DialogueScreen,
# escolhendo aleatoriamente entre as opções disponíveis, para achar becos sem saída e loops sem
# precisar jogar. Usa DialogueGameState em modo sandbox (flags num Dictionary local) e nunca chama
# DialogueState, para não sujar o save do jogador nem a marca "já escolhida" de verdade.
class_name DialogueAutoWalker
extends RefCounted

const MAX_STEPS: int = 500

var seed_used: int = 0
var steps_taken: int = 0
var path: PackedStringArray = PackedStringArray()
var looped: bool = false
var loop_at: String = ""
var finished: bool = false
var error: String = ""


# Roda uma rodada até a conversa terminar, travar (limite de passos) ou repetir um estado
# (node_id, hash das flags do sandbox) já visto nesta mesma rodada.
func run(conversation_id: StringName, p_seed: int = 0) -> void:
	seed_used = p_seed if p_seed != 0 else int(randi())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_used

	var runner: DialogueRunner = DialogueCatalog.create_runner(conversation_id)
	if runner == null:
		error = "runner não encontrado para \"%s\"" % conversation_id
		return
	var game_state := DialogueGameState.new()
	game_state.sandbox = true
	runner.game_state = game_state

	var seen_states: Dictionary = {}
	runner.start(conversation_id)
	var result: Dictionary = await _wait_for_step(runner)

	while result["step"] != null and steps_taken < MAX_STEPS:
		var step: DialogueStep = result["step"]
		steps_taken += 1
		path.append(String(step.node_id))

		var state_key: String = "%s:%d" % [step.node_id, game_state.sandbox_flags_hash()]
		if seen_states.has(state_key):
			looped = true
			loop_at = String(step.node_id)
			return
		seen_states[state_key] = true

		if step.is_end:
			finished = true
			return

		var choice: DialogueChoice = _pick_choice(step.choices, rng)
		if choice == null:
			error = "nó \"%s\" sem escolha disponível" % step.node_id
			return
		if choice.is_system:
			runner.advance()
		else:
			runner.choose(choice.choice_id)
		result = await _wait_for_step(runner)

	if result["reason"] != "":
		error = result["reason"]
	elif steps_taken >= MAX_STEPS:
		error = "limite de %d passos atingido" % MAX_STEPS


func report() -> String:
	var lines: PackedStringArray = []
	lines.append("[Dialogue] - Passeio automático (seed %d): %d passo(s)" % [seed_used, steps_taken])
	if error != "":
		lines.append("  ✗ %s" % error)
	elif looped:
		lines.append("  ✗ Loop detectado, repetiu o nó \"%s\"" % loop_at)
	elif finished:
		lines.append("  ✓ Conversa terminou normalmente")
	lines.append("  Caminho: %s" % " -> ".join(path))
	return "\n".join(lines)


func _pick_choice(choices: Array[DialogueChoice], rng: RandomNumberGenerator) -> DialogueChoice:
	var available: Array[DialogueChoice] = []
	for choice: DialogueChoice in choices:
		if choice.is_available:
			available.append(choice)
	if available.is_empty():
		return null
	return available[rng.randi() % available.size()]


# Espera o próximo step_ready (ou failed) do runner sem depender de uma DialogueScreen. Devolve um
# Dictionary (não a assinatura do sinal) porque um valor local reatribuído dentro de uma lambda não
# escreve de volta na variável de fora em GDScript — só o conteúdo de um objeto mutável escreve.
func _wait_for_step(runner: DialogueRunner) -> Dictionary:
	var result: Dictionary = {"step": null, "reason": "", "done": false}
	var on_step := func(step: DialogueStep) -> void:
		result["step"] = step
		result["done"] = true
	var on_failed := func(reason: String) -> void:
		result["reason"] = reason
		result["done"] = true
	runner.step_ready.connect(on_step, CONNECT_ONE_SHOT)
	runner.failed.connect(on_failed, CONNECT_ONE_SHOT)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while not result["done"]:
		await tree.process_frame
	if runner.step_ready.is_connected(on_step):
		runner.step_ready.disconnect(on_step)
	if runner.failed.is_connected(on_failed):
		runner.failed.disconnect(on_failed)
	return result
