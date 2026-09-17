# DialogueSelfTest.gd — Autoteste da lógica pura do diálogo (SPEC §15.5), no mesmo formato do
# InsightSelfTest: run()/report(), casos hardcoded em português (texto de ferramenta, nunca chega
# ao jogador — ver docs/debug_menu.md).
#
# Cobre as classes de scripts/dialogue/logic/*.gd e scripts/dialogue/runners/MemoryRunner.gd, que
# são RefCounted puros (SPEC §9) — sem cena, sem Autoload de jogo além do estritamente necessário
# (DialogueState, para o grupo "Estado"). Ids de teste prefixados por "__selftest_" para nunca
# colidir com conteúdo real.
#
# run() é uma coroutine (usa await para esperar o step_ready, sempre emitido com call_deferred pela
# base DialogueRunner — SPEC §5.1): quem chama precisa dar await nele, tanto a ação de debug quanto
# tests/run_dialogue_self_test.gd.
class_name DialogueSelfTest
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()


func run() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()

	var state_snapshot: Dictionary = DialogueState.to_dict()
	var was_autosaving: bool = DialogueState.autosave_enabled
	DialogueState.autosave_enabled = false

	_test_resolver()
	_test_choice_layout()
	_test_exchange_tracker()
	_test_input_gate()
	_test_scroll_policy()
	_test_reveal_timer()
	_test_contrast()
	await _test_memory_runner()
	_test_state()
	_test_style()
	_test_placeholder_audio()

	DialogueState.from_dict(state_snapshot)
	DialogueState.autosave_enabled = was_autosaving


func report() -> String:
	var lines: PackedStringArray = []
	lines.append("[Dialogue] - Autoteste: %d ok, %d falha(s)" % [passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# --- Resolver (SPEC §9.1) ---

func _test_resolver() -> void:
	var style := DialogueStyle.new()
	var npc_definition := NPCDefinition.new()
	npc_definition.id = &"__selftest_npc"
	npc_definition.dialogue_color = Color(0.2, 0.4, 0.6)
	var roster := NPCRoster.new()
	roster.npcs = [npc_definition]

	var npc_head := HeadData.new()
	npc_head.id = &"__selftest_npc"
	npc_head.color = Color.BLUE
	var player_head := HeadData.new()
	player_head.id = &"player"
	player_head.color = Color.RED
	var heads: Dictionary = { &"__selftest_npc": npc_head, &"player": player_head }
	var unlocked: Dictionary = { &"__selftest_npc": true }  # "player" fica de fora de propósito

	var speaker := DialogueSpeaker.new()
	speaker.id = &"__selftest_speaker"
	speaker.name_color = Color.YELLOW
	var speakers: Dictionary = { &"__selftest_speaker": speaker }

	var get_head := func(id: StringName) -> HeadData:
		return heads.get(id, null) as HeadData
	var has_head := func(id: StringName) -> bool:
		return unlocked.has(id)
	var resolver := DialogueSpeakerResolver.new(roster, get_head, has_head, speakers, style)

	_expect_true("Falante vazio resolve como narração",
		resolver.resolve(&"").kind == DialogueSpeakerResolver.Kind.NARRATION)

	var player_resolved: DialogueSpeakerResolver.Resolved = resolver.resolve(&"player")
	_expect_true("\"player\" é sempre VOCÊ, com a cor de jogador do estilo",
		player_resolved.kind == DialogueSpeakerResolver.Kind.PLAYER
		and player_resolved.color == style.player_name_color)

	var forced_head: DialogueSpeakerResolver.Resolved = resolver.resolve(&"head:player")
	_expect_true("\"head:player\" força a busca na cabeça, não em VOCÊ",
		forced_head.kind == DialogueSpeakerResolver.Kind.HEAD and forced_head.color == player_head.color)
	_expect_true("Cabeça ainda não desbloqueada marca is_blocked", forced_head.is_blocked)

	var npc_resolved: DialogueSpeakerResolver.Resolved = resolver.resolve(&"__selftest_npc")
	_expect_true("NPC do roster resolve com dialogue_color, e ganha de uma cabeça com o mesmo id",
		npc_resolved.kind == DialogueSpeakerResolver.Kind.NPC
		and npc_resolved.color == npc_definition.dialogue_color)

	var speaker_resolved: DialogueSpeakerResolver.Resolved = resolver.resolve(&"__selftest_speaker")
	_expect_true("DialogueSpeaker resolve como último recurso conhecido",
		speaker_resolved.kind == DialogueSpeakerResolver.Kind.SPEAKER
		and speaker_resolved.color == speaker.name_color)

	var unknown_resolved: DialogueSpeakerResolver.Resolved = resolver.resolve(&"__selftest_ninguem")
	_expect_true("Falante desconhecido cai na cor de erro do estilo",
		unknown_resolved.kind == DialogueSpeakerResolver.Kind.UNKNOWN
		and unknown_resolved.color == style.fallback_speaker_color)


# --- Numeração (SPEC §9.2) ---

func _test_choice_layout() -> void:
	var hidden := _choice(&"__selftest_hidden", false, false)
	var a := _choice(&"__selftest_a", true, false)
	var b := _choice(&"__selftest_b", true, false)
	var visible: Array[DialogueChoiceLayout.VisibleChoice] = DialogueChoiceLayout.build([hidden, a, b])
	_expect_true("Indisponível escondida some da lista e a numeração não deixa buraco",
		visible.size() == 2 and visible[0].shortcut == 1 and visible[1].shortcut == 2)

	var shown_disabled := _choice(&"__selftest_disabled", false, true)
	var after := _choice(&"__selftest_after", true, false)
	var visible2: Array[DialogueChoiceLayout.VisibleChoice] = DialogueChoiceLayout.build([shown_disabled, after])
	_expect_true("SHOW_DISABLED não recebe número e não empurra o número da seguinte",
		visible2[0].shortcut == 0 and visible2[1].shortcut == 1)

	var many: Array[DialogueChoice] = []
	for i: int in range(10):
		many.append(_choice(StringName("__selftest_c%d" % i), true, false))
	var visible3: Array[DialogueChoiceLayout.VisibleChoice] = DialogueChoiceLayout.build(many)
	_expect_true("A 10ª opção disponível fica sem atalho, e a 9ª continua numerada",
		visible3[9].shortcut == 0 and visible3[8].shortcut == 9)


func _choice(id: StringName, is_available: bool, show_when_unavailable: bool) -> DialogueChoice:
	return DialogueChoice.new(id, "T", "", is_available, show_when_unavailable, "T_REASON", false, false, true)


# --- Atual x passado (SPEC §9.3) ---

func _test_exchange_tracker() -> void:
	var tracker := DialogueExchangeTracker.new()
	_expect_true("Antes de qualquer escolha, a abertura não é passado", not tracker.is_past(0))
	tracker.end_exchange()
	_expect_true("Depois da 1ª escolha, a abertura (troca 0) ainda não é passado", not tracker.is_past(0))
	tracker.end_exchange()
	_expect_true("Depois da 2ª escolha, a troca 0 (abertura + VOCÊ₁) já é passado", tracker.is_past(0))
	_expect_true("A troca 1 (réplica + VOCÊ₂) continua acesa", not tracker.is_past(1))


# --- Trava (SPEC §9.4) ---

func _test_input_gate() -> void:
	var gate := DialogueInputGate.new()
	gate.arm(10.0, 0.25)
	_expect_true("Trava bloqueia antes do tempo de destravar", gate.is_locked(10.1))
	_expect_true("Trava libera depois do tempo de destravar", not gate.is_locked(10.26))

	var style := DialogueStyle.new()
	_expect_true("No multiplicador instantâneo (0.0), a trava cai para input_lock_instant",
		is_equal_approx(style.effective_input_lock(0.0), style.input_lock_instant))

	gate.arm(20.0, style.effective_input_lock(1.0))
	_expect_true("A trava é pura: o mesmo tempo consultado de novo dá a mesma resposta (tempo parado não libera sozinho)",
		gate.is_locked(20.1) == gate.is_locked(20.1))


# --- Rolagem (SPEC §9.5) ---

func _test_scroll_policy() -> void:
	var policy := DialogueScrollPolicy.new(24.0)
	_expect_true("NEW_LINE grudado no fim rola ao fim",
		policy.decide(DialogueScrollPolicy.Reason.NEW_LINE, 180.0, 200.0) == DialogueScrollPolicy.Action.SCROLL_TO_END)
	_expect_true("NEW_LINE lendo o histórico só acende o indicador",
		policy.decide(DialogueScrollPolicy.Reason.NEW_LINE, 0.0, 200.0) == DialogueScrollPolicy.Action.SHOW_INDICATOR)
	_expect_true("CHOICES_SHOWN sempre rola ao fim, mesmo lendo o histórico",
		policy.decide(DialogueScrollPolicy.Reason.CHOICES_SHOWN, 0.0, 200.0) == DialogueScrollPolicy.Action.SCROLL_TO_END)
	_expect_true("NUMBER_KEY grudado no fim deixa a escolha seguir (NONE)",
		policy.decide(DialogueScrollPolicy.Reason.NUMBER_KEY, 180.0, 200.0) == DialogueScrollPolicy.Action.NONE)
	_expect_true("NUMBER_KEY lendo o histórico rola ao fim (a tela cancela a escolha ao ver isso)",
		policy.decide(DialogueScrollPolicy.Reason.NUMBER_KEY, 0.0, 200.0) == DialogueScrollPolicy.Action.SCROLL_TO_END)
	_expect_true("JUMP_TO_END sempre rola ao fim",
		policy.decide(DialogueScrollPolicy.Reason.JUMP_TO_END, 0.0, 200.0) == DialogueScrollPolicy.Action.SCROLL_TO_END)


# --- Revelação (SPEC §9.6) ---

func _test_reveal_timer() -> void:
	var style := DialogueStyle.new()
	_expect_true("auto_delay respeita o teto (auto_max_delay)",
		is_equal_approx(DialogueRevealTimer.auto_delay("x".repeat(1000), style), style.auto_max_delay))
	_expect_true("strip_bbcode remove as tags",
		DialogueRevealTimer.strip_bbcode("[b]Oi[/b], [i]tudo bem?[/i]") == "Oi, tudo bem?")

	var text: String = "a, b. c... d?"
	var schedule: PackedFloat32Array = DialogueRevealTimer.build_schedule(text, style)
	_expect_true("O cronograma tem um instante por caractere visível", schedule.size() == text.length())
	var char_duration: float = 1.0 / style.reveal_chars_per_second
	_expect_true("Pausa depois da vírgula soma reveal_pause_comma ao intervalo até o próximo caractere",
		is_equal_approx(schedule[2] - schedule[1], char_duration + style.reveal_pause_comma))
	_expect_true("\"...\" conta como uma pausa só (reveal_pause_stop), não três",
		is_equal_approx(schedule[10] - schedule[9], char_duration + style.reveal_pause_stop))


# --- Contraste (SPEC §9.7) ---

func _test_contrast() -> void:
	_expect_true("Contraste entre branco e preto é 21:1",
		absf(DialogueContrast.ratio(Color.WHITE, Color.BLACK) - 21.0) < 0.05)
	var mid_gray := Color8(0x77, 0x77, 0x77)
	_expect_true("Contraste de #777777 contra branco fica perto de 4,48:1",
		absf(DialogueContrast.ratio(mid_gray, Color.WHITE) - 4.48) < 0.05)


# --- Runner (MemoryRunner, SPEC §5.3) ---

func _test_memory_runner() -> void:
	var content: Dictionary = {
		"start": &"n1",
		"nodes": {
			&"n1": { "line": [&"__selftest_L1", &"__selftest_npc", "T1"], "next": &"n2" },
			&"n2": {
				"line": [&"__selftest_L2", &"__selftest_npc", "T2"],
				"choices": [
					{ "id": &"__selftest_c_gated", "text": "T_GATED", "if_flag": &"__selftest_flag", "next": &"n3" },
					{ "id": &"__selftest_c_grant", "text": "T_GRANT", "grant": &"__selftest_flag", "next": &"n3" },
				],
			},
			&"n3": { "line": [&"__selftest_L3", &"__selftest_npc", "T3"] },
		},
	}
	var game_state := DialogueGameState.new()
	game_state.sandbox = true
	var runner := MemoryRunner.new(content)
	runner.game_state = game_state

	runner.start(&"__selftest_memory")
	var step1: DialogueStep = await runner.step_ready
	_expect_true("Fala sem escolhas recebe \"Continuar\" gerado pelo sistema",
		step1.choices.size() == 1 and step1.choices[0].is_system and step1.choices[0].text_key == "DIALOGUE_CONTINUE")

	runner.advance()
	var step2: DialogueStep = await runner.step_ready
	var gated: DialogueChoice = _find_choice(step2, &"__selftest_c_gated")
	_expect_true("Opção com if_flag ainda não concedida fica indisponível",
		gated != null and not gated.is_available)

	runner.choose(&"__selftest_c_grant")
	var step3: DialogueStep = await runner.step_ready
	_expect_true("\"grant\" aplica a flag no game_state", game_state.has_flag("__selftest_flag"))
	_expect_true("Nó final sem next/choices recebe \"Encerrar\" gerado pelo sistema",
		step3.is_end and step3.choices.size() == 1 and step3.choices[0].text_key == "DIALOGUE_END")


func _find_choice(step: DialogueStep, choice_id: StringName) -> DialogueChoice:
	for choice: DialogueChoice in step.choices:
		if choice.choice_id == choice_id:
			return choice
	return null


# --- Estado (SPEC §12.1) ---

func _test_state() -> void:
	DialogueState.reset_choices()
	DialogueState.mark_chosen(&"__selftest_choice")
	DialogueState.mark_visited(&"__selftest_node")
	var dict: Dictionary = DialogueState.to_dict()
	DialogueState.reset_choices()
	_expect_true("reset_choices apaga o que foi marcado", not DialogueState.was_chosen(&"__selftest_choice"))
	DialogueState.from_dict(dict)
	_expect_true("from_dict devolve StringName mesmo vindo de String (armadilha do JSON)",
		DialogueState.was_chosen(&"__selftest_choice") and DialogueState.was_visited(&"__selftest_node"))


# --- Estilo (SPEC §6.1) ---

func _test_style() -> void:
	var style := DialogueStyle.new()
	_expect_true("effective_panel_width respeita o mínimo",
		is_equal_approx(style.effective_panel_width(0.1), style.panel_width_min))
	_expect_true("effective_panel_width respeita o máximo",
		is_equal_approx(style.effective_panel_width(10.0), style.panel_width_max))
	_expect_true("O beat não zera no instantâneo (multiplicador 0.0)",
		is_equal_approx(style.effective_beat(0.0), style.response_beat))


# --- Sons placeholder (SPEC §16 Fase 5) ---

func _test_placeholder_audio() -> void:
	var streams: Dictionary = {
		"open": DialoguePlaceholderAudio.open(), "close": DialoguePlaceholderAudio.close(),
		"new_line": DialoguePlaceholderAudio.new_line(), "confirm": DialoguePlaceholderAudio.confirm(),
		"hover": DialoguePlaceholderAudio.hover(),
	}
	for cue: String in streams:
		var stream: AudioStreamWAV = streams[cue]
		_expect_true("Placeholder de áudio \"%s\" gera dados" % cue, stream != null and stream.data.size() > 0)
	_expect_true("Placeholder de áudio é cacheado (mesma instância na segunda chamada)",
		DialoguePlaceholderAudio.open() == DialoguePlaceholderAudio.open())


func _expect_true(label: String, condition: bool) -> void:
	if condition:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
		return
	failed_count += 1
	_lines.append("  %s %s" % [CROSS, label])
