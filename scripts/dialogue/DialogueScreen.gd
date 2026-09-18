# DialogueScreen.gd — Máquina de estados da conversa (SPEC §7.8, §8). Layer 40: abaixo do
# PauseMenu (50), para a pausa aparecer por cima da conversa, e acima do HUD do relógio.
class_name DialogueScreen
extends CanvasLayer

enum State { CLOSED, OPENING, SHOWING_LINE, AUTO_WAIT, AWAITING_CHOICE, CONFIRMING, CLOSING }

const DEBUG_SECTION: StringName = &"Diálogo"
const FREEZE_REASON: StringName = &"dialogue"

@export var style: DialogueStyle = preload("res://resources/dialogue/dialogue_style.tres")

# Repetição do analógico/D-pad em dialogue_focus_* (SPEC §10.2, §16 Fase 5): diferente de tecla
# segurada, joypad não gera InputEventJoypad* de eco nenhum — sem isto, segurar o analógico move o
# destaque uma vez só.
@export var analog_repeat_interval: float = 0.18
@export var joypad_axis_threshold: float = 0.5   # mesmo limiar do InsightInteractor (SPEC §10.2)

@onready var _root: Control = $Root
@onready var _backdrop: TextureRect = $Root/Backdrop
@onready var _backbuffer_copy: BackBufferCopy = $Root/BackBufferCopy
@onready var _blur_rect: ColorRect = $Root/BlurRect
@onready var _panel: PanelContainer = $Root/Panel
@onready var _portrait: DialoguePortrait = $Root/Portrait
@onready var _log: DialogueLog = $Root/Panel/Margin/Column/LogArea/Log
@onready var _separator: ColorRect = $Root/Panel/Margin/Column/Separator
@onready var _options_scroll: ScrollContainer = $Root/Panel/Margin/Column/OptionsScroll
@onready var _options: DialogueOptionList = $Root/Panel/Margin/Column/OptionsScroll/Options
@onready var _scroll_indicator: DialogueScrollIndicator = $Root/Panel/Margin/Column/LogArea/ScrollIndicator

var _runner: DialogueRunner
var _resolver: DialogueSpeakerResolver
var _exchange_tracker: DialogueExchangeTracker
var _input_gate: DialogueInputGate
var _scroll_policy: DialogueScrollPolicy
var _sequencer: DialogueSequencer

var _state: State = State.CLOSED
var _pending_step: DialogueStep
var _current_entry: DialogueEntry
var _last_node_id: StringName = &""
var _initiator_id: StringName = &""
# O NPC cujo retrato está na moldura: o que abriu a conversa, ou o último NPC que falou nela.
var _portrait_npc: NPCDefinition
var _screen_time: float = 0.0
var _finalized: bool = true

# -1 (cima), 0 (solto) ou 1 (baixo): direção do analógico/D-pad segurado agora, para o repeat.
var _analog_focus_direction: int = 0
var _analog_repeat_elapsed: float = 0.0

# -INF garante que o primeiro destaque sempre toca, sem checar contra um "zero" que também é tempo
# válido de tela.
var _last_hover_sfx_time: float = -INF


func _ready() -> void:
	_input_gate = DialogueInputGate.new()
	_scroll_policy = DialogueScrollPolicy.new(style.stick_threshold)
	_sequencer = DialogueSequencer.new(self)
	_log.style = style
	_log.policy = _scroll_policy
	_log.new_lines_pending_changed.connect(_scroll_indicator.set_pending_count)
	_scroll_indicator.pressed.connect(_on_scroll_indicator_pressed)
	_options.option_confirmed.connect(_on_option_confirmed)
	_options.highlight_changed.connect(_on_option_highlighted)
	_panel.gui_input.connect(_on_panel_gui_input)
	_root.hide()
	_separator.visible = false
	get_viewport().size_changed.connect(_apply_layout)
	EventBus.conversation_requested.connect(open)
	EventBus.dialogue_requested.connect(_open_insight_line)
	EventBus.day_ended.connect(_on_day_ended)
	GameManager.dialogue_preferences_changed.connect(_apply_preferences)
	_warn_placeholder_sfx()
	if OS.has_feature("editor") or OS.is_debug_build():
		_register_debug_entries()


# PLACEHOLDER (SPEC §16 Fase 5): avisa uma vez no boot quais pistas do DialogueStyle ainda tocam o
# som sintetizado — ver DialoguePlaceholderAudio. Substituir é só preencher o campo no Inspector.
func _warn_placeholder_sfx() -> void:
	var missing: PackedStringArray = []
	for field: StringName in [&"sfx_open", &"sfx_close", &"sfx_new_line", &"sfx_confirm", &"sfx_hover"]:
		if style.get(field) == null:
			missing.append(String(field))
	if not missing.is_empty():
		print("[Dialogue] - PLACEHOLDER: som sintetizado em código para %s (vazio(s) no DialogueStyle)" % ", ".join(missing))


func _process(delta: float) -> void:
	if _state != State.CLOSED:
		_screen_time += delta
	if _analog_focus_direction != 0 and _state == State.AWAITING_CHOICE:
		_analog_repeat_elapsed += delta
		if _analog_repeat_elapsed >= analog_repeat_interval:
			_analog_repeat_elapsed = 0.0
			_options.move_highlight(_analog_focus_direction)


# Só observa (nunca consome) para saber se o analógico/D-pad de foco está segurado — o próprio
# cruzar do limiar já move o destaque uma vez pelo caminho normal da ação, em _unhandled_input.
func _input(event: InputEvent) -> void:
	var joypad_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joypad_motion != null and joypad_motion.axis == JOY_AXIS_LEFT_Y:
		var direction: int = int(signf(joypad_motion.axis_value)) if absf(joypad_motion.axis_value) >= joypad_axis_threshold else 0
		_set_analog_focus_direction(direction)
		return
	var joypad_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joypad_button != null and (joypad_button.button_index == JOY_BUTTON_DPAD_UP or joypad_button.button_index == JOY_BUTTON_DPAD_DOWN):
		if not joypad_button.pressed:
			_set_analog_focus_direction(0)
		else:
			_set_analog_focus_direction(-1 if joypad_button.button_index == JOY_BUTTON_DPAD_UP else 1)


func _set_analog_focus_direction(direction: int) -> void:
	_analog_focus_direction = direction
	_analog_repeat_elapsed = 0.0


func _exit_tree() -> void:
	if _state != State.CLOSED:
		_finalize_close()


# Ignora (com log) se já houver uma conversa aberta, ou durante uma troca de cena.
func open(conversation_id: StringName, initiator_id: StringName = &"", start_node_id: StringName = &"") -> void:
	if not _can_open(conversation_id):
		return
	var runner: DialogueRunner = DialogueCatalog.create_runner(conversation_id)
	if runner == null:
		return
	_begin(runner, conversation_id, initiator_id, start_node_id)


# Ponte dos insights de personagem (SPEC §7.8, §11.3): uma única fala de uma cabeça, via
# SingleLineRunner. Não passa pelo DialogueCatalog porque não é uma conversa navegável.
func _open_insight_line(head_id: StringName, text_key: String) -> void:
	var runner: SingleLineRunner = SingleLineRunner.new(head_id, text_key)
	if not _can_open(runner.conversation_id):
		return
	_begin(runner, runner.conversation_id, &"", &"")


func _can_open(conversation_id: StringName) -> bool:
	if _state != State.CLOSED:
		push_warning("[Dialogue] - AVISO: pedido de \"%s\" ignorado; \"%s\" já está aberta" % [
			conversation_id, String(_runner.conversation_id) if _runner != null else "?"
		])
		return false
	if GameManager.in_transition:
		push_warning("[Dialogue] - AVISO: pedido de \"%s\" ignorado; troca de cena em andamento" % conversation_id)
		return false
	return true


func _begin(runner: DialogueRunner, conversation_id: StringName, initiator_id: StringName,
		start_node_id: StringName) -> void:
	_runner = runner
	_runner.game_state = DialogueGameState.new()
	_runner.step_ready.connect(_on_step_ready)
	_runner.failed.connect(_on_runner_failed)
	_resolver = DialogueCatalog.make_default_resolver(style)
	_exchange_tracker = DialogueExchangeTracker.new()
	_pending_step = null
	_last_node_id = &""
	_initiator_id = initiator_id
	_portrait_npc = _resolver.find_npc(initiator_id) if initiator_id != &"" else null
	if _portrait_npc != null:
		_portrait.show_npc(_portrait_npc, style)
	_finalized = false

	GameClock.freeze(FREEZE_REASON)
	print("[Dialogue] - Conversa \"%s\" iniciada" % conversation_id)
	EventBus.conversation_started.emit(conversation_id, initiator_id)

	_state = State.OPENING
	_root.show()
	_apply_layout()
	_play_sfx_or_placeholder(style.sfx_open, DialoguePlaceholderAudio.open())
	_play_open_animation()
	_runner.start(conversation_id, start_node_id)


# force = true fecha seco (troca de cena, erro do runner, fim de dia).
func close(force: bool = false) -> void:
	if _state == State.CLOSED:
		return
	_state = State.CLOSING
	if force or style == null:
		_finalize_close()
		return
	var target_x: float = _panel.position.x + style.open_slide_px
	var duration: float = style.scaled(style.close_duration, GameManager.dialogue_animation_multiplier)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, duration)
	tween.tween_property(_panel, "position:x", target_x, duration)
	if _portrait.visible:
		tween.tween_property(_portrait, "modulate:a", 0.0, duration)
		tween.tween_property(_portrait, "position:x", _portrait.position.x + style.open_slide_px, duration)
	await tween.finished
	_finalize_close()


func is_open() -> bool:
	return _state != State.CLOSED


func get_state() -> State:
	return _state


# --- Layout (SPEC §7.2) ---

func _apply_layout() -> void:
	var text_scale: float = GameManager.dialogue_text_scale
	var width: float = style.effective_panel_width(text_scale)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_right = -style.panel_margin_right
	_panel.offset_left = _panel.offset_right - width
	_panel.offset_top = style.panel_margin_top
	_panel.offset_bottom = -style.panel_margin_bottom
	style.apply_to_theme(_root.theme, text_scale, GameManager.dialogue_use_alt_font)
	_update_panel_style()
	_update_backdrop()
	_update_portrait_layout()
	_apply_options_height_cap()


# Aplica as preferências de diálogo (SPEC §14.3): pode rodar com a conversa aberta.
func _apply_preferences() -> void:
	_apply_layout()
	_log.refresh_all()


func _update_panel_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(style.panel_color, GameManager.dialogue_panel_opacity)
	box.content_margin_left = style.panel_padding_h
	box.content_margin_right = style.panel_padding_h
	box.content_margin_top = style.panel_padding_v
	box.content_margin_bottom = style.panel_padding_v
	_panel.add_theme_stylebox_override("panel", box)


# Sem shader (Compatibility): um GradientTexture2D com 3 paradas reproduz o mesmo degradê
# ancorado na coluna (V6) — 0% em panel_left - backdrop_fade_width, 45% de panel_left em diante.
func _update_backdrop() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_left: float = _panel.offset_left + viewport_size.x
	var start_x: float = maxf(0.0, panel_left - style.backdrop_fade_width)
	var total_width: float = maxf(1.0, viewport_size.x - start_x)
	var fade_fraction: float = clampf(style.backdrop_fade_width / total_width, 0.0, 1.0)

	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.0, 0.0, 0.0, style.backdrop_dim_alpha))
	gradient.add_point(fade_fraction, Color(0.0, 0.0, 0.0, style.backdrop_dim_alpha))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.width = maxi(2, int(total_width))
	texture.height = 2

	_backdrop.texture = texture
	_backdrop.position = Vector2(start_x, 0.0)
	_backdrop.size = Vector2(total_width, viewport_size.y)

	# Desligado por padrão (SPEC §7.2, §16 Fase 5): ligar exige medir o custo do BackBufferCopy no
	# Compatibility antes — por isso os dois só saem do repouso quando backdrop_blur_enabled é true.
	_backbuffer_copy.visible = style.backdrop_blur_enabled
	_blur_rect.visible = style.backdrop_blur_enabled
	if style.backdrop_blur_enabled:
		_blur_rect.position = _panel.position
		_blur_rect.size = _panel.size


# O retrato fica na moldura à esquerda da coluna (slot reservado em DialogueStyle.portrait_slot_size).
# Some quando a conversa ainda não tem um NPC conhecido, ou quando a tela é estreita demais para ele.
func _update_portrait_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_left: float = _panel.offset_left + viewport_size.x
	var rect: Rect2 = DialoguePortraitLayout.compute_rect(panel_left, _panel.offset_top, viewport_size, style)
	_portrait.visible = _portrait_npc != null and rect.has_area()
	if rect.has_area():
		_portrait.position = rect.position
		_portrait.size = rect.size


# A conversa pode ter mais de um NPC falando: o retrato acompanha o último que falou. Jogador,
# narração e cabeças de insight não têm retrato, então a moldura fica como estava.
func _show_portrait_npc(npc: NPCDefinition) -> void:
	if npc == _portrait_npc:
		return
	var was_visible: bool = _portrait.visible
	_portrait_npc = npc
	_portrait.show_npc(npc, style)
	_update_portrait_layout()
	if _portrait.visible:
		_fade_in_portrait(not was_visible)


# Entra junto com o painel (mesma duração e deslize) na abertura, ou só com um fade curto quando o
# retrato troca de NPC no meio da conversa.
func _fade_in_portrait(slide: bool) -> void:
	var duration: float = style.scaled(style.open_duration if slide else style.entry_fade_in,
		GameManager.dialogue_animation_multiplier)
	var target_x: float = _portrait.position.x
	_portrait.modulate.a = 0.0
	if slide:
		_portrait.position.x = target_x + style.open_slide_px
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_portrait, "modulate:a", 1.0, duration)
	if slide:
		tween.tween_property(_portrait, "position:x", target_x, duration)


# A lista de opções não pode empurrar o log pra fora da coluna (SPEC §7.1): acima de 50% da altura
# da coluna — escala 200% + várias opções longas —, ela ganha rolagem própria (custom_minimum_size
# trava a altura) e o log (único filho com EXPAND_FILL) fica com o resto, sempre acima de 30%.
func _apply_options_height_cap() -> void:
	var column_height: float = _panel.size.y - style.panel_padding_v * 2.0
	if column_height <= 0.0:
		return
	var natural_height: float = _options.get_combined_minimum_size().y
	_options_scroll.custom_minimum_size.y = minf(natural_height, column_height * 0.5)


func _play_open_animation() -> void:
	_panel.modulate.a = 0.0
	var target_x: float = _panel.position.x
	_panel.position.x = target_x + style.open_slide_px
	var duration: float = style.scaled(style.open_duration, GameManager.dialogue_animation_multiplier)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, duration)
	tween.tween_property(_panel, "position:x", target_x, duration)
	if _portrait.visible:
		_fade_in_portrait(true)
	await tween.finished
	if _state == State.OPENING:
		_resolve_pending_step()


# --- Máquina de estados (SPEC §8.1) ---

func _on_step_ready(step: DialogueStep) -> void:
	if _state == State.OPENING or _state == State.CONFIRMING:
		_pending_step = step
		return
	_process_step(step)


func _resolve_pending_step() -> void:
	if _pending_step != null:
		var step: DialogueStep = _pending_step
		_pending_step = null
		_process_step(step)
	else:
		_state = State.SHOWING_LINE


func _process_step(step: DialogueStep) -> void:
	_last_node_id = step.node_id
	_current_entry = null
	if step.lines.is_empty():
		_show_choices_or_advance(step)
		return
	var line: DialogueLine = step.lines[0]
	var resolved: DialogueSpeakerResolver.Resolved = _resolver.resolve(line.speaker_id)
	if resolved.npc != null:
		_show_portrait_npc(resolved.npc)
	_current_entry = _log.append_line(line, resolved, _exchange_tracker.current_exchange)
	_state = State.SHOWING_LINE
	_play_sfx_or_placeholder(style.sfx_new_line, DialoguePlaceholderAudio.new_line())
	_await_entry_then_continue(step)


# Revelação progressiva (SPEC §9.6): espera o typewriter (ou o jogador pular, via _unhandled_input
# em SHOWING_LINE) antes de mostrar escolhas/avançar. No instantâneo, só a mesma espera de sempre.
# O "if _state == SHOWING_LINE" depois do await é a guarda contra a tela ter fechado (fim de dia,
# troca de cena) enquanto a revelação — agora potencialmente longa — ainda rodava.
func _await_entry_then_continue(step: DialogueStep) -> void:
	if GameManager.dialogue_text_reveal == GameManager.TextReveal.PROGRESSIVE and _current_entry != null:
		_current_entry.start_reveal()
		await _current_entry.reveal_finished
	else:
		var wait: float = style.scaled(style.entry_fade_in, GameManager.dialogue_animation_multiplier)
		await get_tree().create_timer(wait, false, false, false).timeout
	if _state == State.SHOWING_LINE:
		_show_choices_or_advance(step)


func _show_choices_or_advance(step: DialogueStep) -> void:
	if step.advance_mode == DialogueStep.AdvanceMode.AUTO:
		_state = State.AUTO_WAIT
		var plain: String = ""
		if not step.lines.is_empty():
			plain = DialogueRevealTimer.strip_bbcode(tr(step.lines[0].text_key))
		# Tempo já gasto revelando conta como leitura: sem isto, o AUTO somaria a animação inteira
		# à espera de leitura de novo, dobrando o tempo parado na tela depois do texto aparecer.
		var already_elapsed: float = _current_entry.get_reveal_duration() if _current_entry != null else 0.0
		var delay: float = maxf(0.0, DialogueRevealTimer.auto_delay(plain, style) - already_elapsed)
		await get_tree().create_timer(delay, false, false, false).timeout
		if _state == State.AUTO_WAIT:
			_runner.advance()
		return

	_state = State.AWAITING_CHOICE
	var visible_choices: Array[DialogueChoiceLayout.VisibleChoice] = DialogueChoiceLayout.build(step.choices)
	_separator.visible = true
	_options.show_choices(visible_choices, style, true)
	_apply_options_height_cap()
	_log.scroll_to_end(true)
	_input_gate.arm(_screen_time, style.effective_input_lock(GameManager.dialogue_animation_multiplier))


func _on_option_confirmed(choice: DialogueChoice) -> void:
	if _state != State.AWAITING_CHOICE or _input_gate.is_locked(_screen_time):
		return
	_confirm_choice(choice)


# Toca a cada troca de destaque (mouse, teclado ou controle — highlight_changed não distingue a
# origem, e o "blip" faz sentido nos três). Trava por hover_sfx_min_interval para o mouse passeando
# rápido pela lista não virar uma metralhadora de bipes.
func _on_option_highlighted(_choice: DialogueChoice) -> void:
	if _screen_time - _last_hover_sfx_time < style.hover_sfx_min_interval:
		return
	_last_hover_sfx_time = _screen_time
	_play_sfx_or_placeholder(style.sfx_hover, DialoguePlaceholderAudio.hover())


# Sequência de confirmação (SPEC §8.2): brilho -> chamada ao runner -> recolhimento -> fala do
# jogador (se logs_as_player_line) -> beat -> processa o passo pendente.
func _confirm_choice(choice: DialogueChoice) -> void:
	_state = State.CONFIRMING
	_input_gate.disarm()
	_play_sfx_or_placeholder(style.sfx_confirm, DialoguePlaceholderAudio.confirm())
	_options.play_confirm(choice, _sequencer)

	if choice.is_system and choice.text_key == "DIALOGUE_END":
		_sequencer.add_call_stage(func() -> void: close(false))
		_sequencer.run()
		return

	_sequencer.add_call_stage(_apply_choice_step2.bind(choice))
	_sequencer.add_wait_stage(style.scaled(style.list_collapse, GameManager.dialogue_animation_multiplier), false)
	if choice.logs_as_player_line:
		_sequencer.add_call_stage(_log_player_line.bind(choice))
		_sequencer.add_wait_stage(style.effective_beat(GameManager.dialogue_animation_multiplier), true)
	_sequencer.add_call_stage(_resolve_pending_step)
	_sequencer.run()


func _apply_choice_step2(choice: DialogueChoice) -> void:
	if choice.is_system:
		_runner.advance()
	else:
		DialogueState.mark_chosen(choice.choice_id)
		_runner.choose(choice.choice_id)


func _log_player_line(choice: DialogueChoice) -> void:
	var line: DialogueLine = DialogueLine.new(
		StringName("player:" + String(choice.choice_id)), &"player", choice.text_key
	)
	_log.append_line(line, _resolver.resolve(&"player"), _exchange_tracker.current_exchange)
	_exchange_tracker.end_exchange()
	_log.set_current_exchange(_exchange_tracker.current_exchange)


func _on_runner_failed(reason: String) -> void:
	push_error("[Dialogue] - Runner falhou: %s" % reason)
	close(true)


func _on_day_ended(_day: int, _reason: int) -> void:
	if is_open():
		close(true)


# unfreeze + conversation_ended num único método, com guarda para rodar uma vez só (SPEC §8.4).
func _finalize_close() -> void:
	if _finalized:
		return
	_finalized = true
	var conversation_id: StringName = _runner.conversation_id if _runner != null else &""
	GameClock.unfreeze(FREEZE_REASON)
	print("[Dialogue] - Conversa \"%s\" encerrada no nó %s" % [conversation_id, _last_node_id])
	EventBus.conversation_ended.emit(conversation_id, _last_node_id)
	_play_sfx_or_placeholder(style.sfx_close, DialoguePlaceholderAudio.close())
	_log.clear_entries()
	_options.clear()
	_separator.visible = false
	_scroll_indicator.set_pending_count(0)
	_root.hide()
	_portrait.modulate.a = 1.0
	_portrait_npc = null
	_state = State.CLOSED
	_runner = null
	_pending_step = null
	_initiator_id = &""


func _play_sfx(stream: AudioStream) -> void:
	if stream != null:
		AudioManager.play_sfx(stream, style.sfx_volume_db)


# PLACEHOLDER (SPEC §16 Fase 5): toca a pista do estilo, ou o som sintetizado quando o campo ainda
# está vazio — ver DialoguePlaceholderAudio e _warn_placeholder_sfx().
func _play_sfx_or_placeholder(assigned: AudioStream, placeholder: AudioStreamWAV) -> void:
	_play_sfx(assigned if assigned != null else placeholder)


# --- Entrada (SPEC §10) ---

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.CLOSED:
		return
	if _handle_scroll_action(event):
		get_viewport().set_input_as_handled()
		return
	if _state == State.SHOWING_LINE:
		_handle_reveal_skip(event)
		return
	if _state == State.CONFIRMING:
		if not event.is_echo() and (event.is_action_pressed(&"dialogue_confirm") or _is_left_click(event)):
			_sequencer.skip_current()
			get_viewport().set_input_as_handled()
		return
	if _state == State.AWAITING_CHOICE:
		_handle_choice_input(event)


func _handle_scroll_action(event: InputEvent) -> bool:
	var line_height: float = style.effective_body_size(1.0) * style.line_spacing
	if event.is_action_pressed(&"dialogue_scroll_up"):
		_log.scroll_vertical -= int(style.wheel_lines * line_height)
		return true
	if event.is_action_pressed(&"dialogue_scroll_down"):
		_log.scroll_vertical += int(style.wheel_lines * line_height)
		return true
	if event.is_action_pressed(&"dialogue_jump_to_end"):
		_log.scroll_to_end(true)
		return true
	if event.is_action_pressed(&"dialogue_jump_to_start"):
		_log.scroll_vertical = 0
		return true
	return false


# Ecoado (tecla segurada) é ignorado só para opção/confirmar (SPEC §10.2): escolher não pode
# repetir sozinho. Focus_up/down passam batido, de propósito — é o que dá repetição ao segurar
# teclado; o analógico e o D-pad não geram eco nenhum, e por isso têm o próprio relógio abaixo.
func _handle_choice_input(event: InputEvent) -> void:
	if not event.is_echo():
		for i: int in range(1, 10):
			if event.is_action_pressed(StringName("dialogue_option_%d" % i)):
				_try_confirm_shortcut(i)
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed(&"dialogue_confirm"):
			_try_confirm_highlighted_or_system()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"dialogue_focus_up"):
		_options.move_highlight(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"dialogue_focus_down"):
		_options.move_highlight(1)
		get_viewport().set_input_as_handled()


# NUMBER_KEY grudado no fim: a escolha segue. Lendo o histórico: rola e cancela (SPEC §9.5, §10.3).
func _try_confirm_shortcut(number: int) -> void:
	if _input_gate.is_locked(_screen_time):
		return
	var action: DialogueScrollPolicy.Action = _scroll_policy.decide(
		DialogueScrollPolicy.Reason.NUMBER_KEY, _log.scroll_vertical, _log.get_max_scroll()
	)
	if action == DialogueScrollPolicy.Action.SCROLL_TO_END:
		_log.scroll_to_end(true)
		return
	_options.confirm_shortcut(number)


func _try_confirm_highlighted_or_system() -> void:
	if _input_gate.is_locked(_screen_time):
		return
	if _options.has_highlight():
		_options.confirm_highlighted()
		return
	var system_choice: DialogueChoice = _options.only_system_choice()
	if system_choice != null:
		_confirm_choice(system_choice)


# Clique ou dialogue_confirm durante o typewriter pulam direto para o texto inteiro, sem avançar a
# conversa — o clique que "acorda" a fala não pode ser o mesmo que confirma a próxima escolha
# (SPEC §9.6).
func _handle_reveal_skip(event: InputEvent) -> void:
	if event.is_echo() or _current_entry == null or not _current_entry.is_revealing():
		return
	if event.is_action_pressed(&"dialogue_confirm") or _is_left_click(event):
		_current_entry.complete_reveal()
		get_viewport().set_input_as_handled()


func _on_panel_gui_input(event: InputEvent) -> void:
	if _state != State.AWAITING_CHOICE or _input_gate.is_locked(_screen_time):
		return
	if not _is_left_click(event):
		return
	var system_choice: DialogueChoice = _options.only_system_choice()
	if system_choice != null:
		_confirm_choice(system_choice)
		get_viewport().set_input_as_handled()


func _on_scroll_indicator_pressed() -> void:
	_log.scroll_to_end(true)


func _is_left_click(event: InputEvent) -> bool:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT


# --- Debug (SPEC §15.1) ---

func _register_debug_entries() -> void:
	DebugMenu.register_input(DEBUG_SECTION, "Iniciar conversa", _debug_start_conversation, [
		DebugParam.string_value("conversation_id", "", _debug_conversation_suggestions),
	])
	DebugMenu.register_input(DEBUG_SECTION, "Pular para nó", _debug_jump_to_node, [
		DebugParam.string_value("conversation_id", "", _debug_conversation_suggestions),
		DebugParam.string_value("node_id", ""),
	])
	DebugMenu.register_action(DEBUG_SECTION, "Validar conversas", _debug_validate_conversations)
	DebugMenu.register_action(DEBUG_SECTION, "Validar estilo", _debug_validate_style)
	DebugMenu.register_toggle(DEBUG_SECTION, "Mostrar IDs", _debug_set_show_ids, DialogueEntry.show_ids)
	DebugMenu.register_toggle(DEBUG_SECTION, "Ignorar condições", _debug_set_ignore_conditions, DialogueRunner.ignore_conditions)
	DebugMenu.register_action(DEBUG_SECTION, "Teste de estresse de texto", _debug_stress_test)
	DebugMenu.register_input(DEBUG_SECTION, "Passeio automático", _debug_auto_walk, [
		DebugParam.string_value("conversation_id", "", _debug_conversation_suggestions),
		DebugParam.int_value("runs", 50, 1, 500),
	])
	DebugMenu.register_action(DEBUG_SECTION, "Resetar escolhas", _debug_reset_choices, true)
	DebugMenu.register_action(DEBUG_SECTION, "Autoteste do diálogo", _debug_run_self_test)


func _debug_conversation_suggestions() -> PackedStringArray:
	var suggestions: PackedStringArray = PackedStringArray(["__stress_text"])
	suggestions.append_array(DialogueCatalog.list_script_ids())
	return suggestions


func _debug_start_conversation(conversation_id: String) -> void:
	EventBus.conversation_requested.emit(StringName(conversation_id), &"")


func _debug_jump_to_node(conversation_id: String, node_id: String) -> void:
	open(StringName(conversation_id), &"", StringName(node_id))


func _debug_validate_conversations() -> void:
	print(DialogueValidator.report())


func _debug_validate_style() -> void:
	print(DialogueStyleValidator.report(style))


func _debug_set_show_ids(enabled: bool) -> void:
	DialogueEntry.show_ids = enabled
	_log.refresh_all()


func _debug_set_ignore_conditions(enabled: bool) -> void:
	DialogueRunner.ignore_conditions = enabled


# Força escala 2.0 temporariamente e abre __stress_text (SPEC §15.6); devolve a escala anterior ao
# fechar.
func _debug_stress_test() -> void:
	var previous_scale: float = GameManager.dialogue_text_scale
	GameManager.dialogue_text_scale = 2.0
	_apply_preferences()
	open(&"__stress_text")
	var restore_scale: Callable = func(_id: StringName, _node: StringName) -> void:
		GameManager.dialogue_text_scale = previous_scale
		_apply_preferences()
	EventBus.conversation_ended.connect(restore_scale, CONNECT_ONE_SHOT)


func _debug_auto_walk(conversation_id: String, runs: int) -> void:
	var finished: int = 0
	var looped: int = 0
	var errors: int = 0
	for i: int in runs:
		var walker := DialogueAutoWalker.new()
		await walker.run(StringName(conversation_id), i + 1)
		if walker.finished:
			finished += 1
		elif walker.looped:
			looped += 1
			print(walker.report())
		else:
			errors += 1
			print(walker.report())
	print("[Dialogue] - Passeio automático: %d rodada(s) de \"%s\" — %d terminaram, %d loop(s), %d erro(s)" % [
		runs, conversation_id, finished, looped, errors
	])


func _debug_reset_choices() -> void:
	DialogueState.reset_choices()
	print("[Dialogue] - Escolhas e nós visitados resetados")


func _debug_run_self_test() -> void:
	var test := DialogueSelfTest.new()
	await test.run()
	print(test.report())
