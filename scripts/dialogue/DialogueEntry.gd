# DialogueEntry.gd — Uma fala dentro do log (SPEC §7.4). Nome e fala moram no mesmo RichTextLabel,
# em fluxo contínuo: o nome é só o começo do parágrafo, então a margem esquerda do texto é a da
# coluna inteira, não a largura do nome — nome longo não empurra a fala nem abre uma segunda coluna.
#
# PALAVRAS DO GLOSSÁRIO: a fala aceita a marcação do GDD no translations.csv ("Achei uma [FACA] no
# beco.", ver ClickableWordText). A palavra fica sublinhada até o jogador clicar nela; o clique a põe
# no glossário, o sublinhado sai e o WordDiscoveryToast faz a palavra voar pro diário. Clicar numa
# palavra NÃO pula a revelação nem avança a conversa: o clique é consumido aqui.
class_name DialogueEntry
extends MarginContainer

signal reveal_finished

enum EntryState { ENTERING, CURRENT, PAST }

static var show_ids: bool = false

@onready var _text_label: RichTextLabel = $Row/Text
@onready var _id_label: Label = $Row/IdLabel

var exchange_index: int = 0

var _style: DialogueStyle
var _line: DialogueLine
var _resolved: DialogueSpeakerResolver.Resolved
var _state: EntryState = EntryState.ENTERING
var _reveal_schedule: PackedFloat32Array = PackedFloat32Array()
var _reveal_elapsed: float = 0.0
var _revealing: bool = false
# Quantos caracteres o nome ocupa no começo do label: ele não é revelado letra por letra, então a
# revelação sempre mostra o prefixo inteiro mais o que o cronograma já liberou da fala.
var _prefix_chars: int = 0
var _revealed_chars: int = 0
# O payload ("faca" ou "marcos|castro") da palavra do glossário sob o mouse, ou vazio. O clique é
# tratado no APERTAR do botão, e não pelo meta_clicked (que só sai no soltar): o apertar é o que a
# DialogueScreen usa pra pular a revelação e confirmar "Continuar", então é ele que precisa ser
# consumido.
var _hovered_word_payload: String = ""
# A fala tem palavra do glossário marcada. Evita redesenhar toda fala do log a cada palavra colhida.
var _has_glossary_words: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text_label.meta_underlined = false
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_text_label.meta_hover_started.connect(_on_word_hover_started)
	_text_label.meta_hover_ended.connect(_on_word_hover_ended)
	_text_label.gui_input.connect(_on_text_gui_input)
	_text_label.meta_clicked.connect(_on_word_clicked)
	EventBus.glossary_word_discovered.connect(_on_glossary_word_discovered)
	set_process(false)


func setup(line: DialogueLine, resolved: DialogueSpeakerResolver.Resolved, p_exchange_index: int,
		style: DialogueStyle) -> void:
	_line = line
	_resolved = resolved
	_style = style
	exchange_index = p_exchange_index
	modulate.a = 0.0
	_id_label.text = String(line.line_id)
	_id_label.visible = show_ids
	refresh()


# Reconstrói o texto de tudo (troca de idioma, escala, fonte). Cor sempre por push_color, nunca por
# BBCode vindo do GD.
func refresh() -> void:
	if _line == null:
		return
	var content: String = _sanitized_text()
	_text_label.clear()
	# O clear() apaga os links sem emitir meta_hover_ended: sem isto, a palavra que acabou de ser
	# colhida continuaria "sob o mouse" e o próximo clique a colheria de novo.
	_set_hovered_word("")
	_prefix_chars = 0
	if _line.is_narration():
		_text_label.push_color(_style.narration_color)
		_text_label.push_italics()
		_text_label.append_text(content)
		_text_label.pop()
		_text_label.pop()
	else:
		# add_text (e não append_text) no nome: nome é dado do projeto, não BBCode — um "[" num nome
		# não pode virar tag.
		var speaker_name: String = _speaker_display_name()
		var separator: String = tr(&"DIALOGUE_SPEAKER_SEPARATOR")
		_prefix_chars = speaker_name.length() + separator.length()
		_text_label.push_color(_resolved.color)
		_text_label.push_bold()
		_text_label.add_text(speaker_name)
		_text_label.pop()
		_text_label.add_text(separator)
		_text_label.pop()
		_text_label.push_color(_style.text_color)
		_text_label.append_text(content)
		_text_label.pop()
	_apply_visible_chars()


func play_enter(duration: float) -> void:
	var target_y: float = position.y
	modulate.a = 0.0
	position.y = target_y + _style.entry_slide_px
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, duration)
	tween.tween_property(self, "position:y", target_y, duration)


func set_past(is_past: bool) -> void:
	_state = EntryState.PAST if is_past else EntryState.CURRENT
	var target_alpha: float = _style.past_alpha if is_past else 1.0
	create_tween().tween_property(self, "modulate:a", target_alpha, _style.hover_out)


func start_reveal() -> void:
	var plain: String = DialogueRevealTimer.strip_bbcode(_sanitized_text())
	_reveal_schedule = DialogueRevealTimer.build_schedule(plain, _style)
	_reveal_elapsed = 0.0
	_revealing = true
	_revealed_chars = 0
	_apply_visible_chars()
	set_process(true)


func complete_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	set_process(false)
	_apply_visible_chars()
	reveal_finished.emit()


func is_revealing() -> bool:
	return _revealing


# Duração total do cronograma de revelação (0 se a fala nunca foi revelada com start_reveal()).
# Usado pelo modo AUTO para não somar a espera de leitura à animação (SPEC §9.6): o tempo já gasto
# revelando conta como parte do tempo de leitura, não além dele.
func get_reveal_duration() -> float:
	return _reveal_schedule[-1] if not _reveal_schedule.is_empty() else 0.0


func _process(delta: float) -> void:
	if not _revealing:
		set_process(false)
		return
	_reveal_elapsed += delta
	var count: int = 0
	while count < _reveal_schedule.size() and _reveal_schedule[count] <= _reveal_elapsed:
		count += 1
	_revealed_chars = count
	_apply_visible_chars()
	if count >= _reveal_schedule.size():
		complete_reveal()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh()


# O nome aparece inteiro desde o primeiro quadro da revelação; só a fala anda pelo cronograma. Fora
# da revelação (inclusive depois de um refresh por troca de idioma), o label mostra tudo.
func _apply_visible_chars() -> void:
	_text_label.visible_characters = (_prefix_chars + _revealed_chars) if _revealing else -1


# "NOME, ALCUNHA" (ver DialogueSpeakerResolver.EPITHET_KEY_SUFFIX). Alcunha sem tradução — tr()
# devolve a própria chave — cai para só o nome, em vez de mostrar a chave crua para o jogador.
func _speaker_display_name() -> String:
	var speaker_name: String = tr(_resolved.name_key)
	var epithet_key: String = _resolved.get_epithet_key()
	var epithet: String = tr(epithet_key) if epithet_key != "" else ""
	if epithet == "" or epithet == epithet_key:
		return speaker_name.to_upper()
	return (tr(&"DIALOGUE_SPEAKER_EPITHET_FORMAT") % [speaker_name, epithet]).to_upper()


# A fala pronta pro label: BBCode limpo e a marcação do glossário já convertida em sublinhado/link.
# A conversão vem DEPOIS da limpeza porque ela gera [url]/[color]/[u], que a limpeza cortaria.
func _sanitized_text() -> String:
	var sanitized: String = DialogueEntry.sanitize_bbcode(tr(_line.text_key), _line.line_id)
	_has_glossary_words = not ClickableWordText.find_word_ids(sanitized).is_empty()
	if not _has_glossary_words:
		return sanitized
	return ClickableWordText.render_markup(sanitized, &"", _style.glossary_word_color,
		_style.glossary_word_collected_color)


# Remove qualquer tag BBCode fora da lista permitida (i, b) e loga o corte. A marcação do glossário
# ([FACA], só maiúsculas) passa: ela não é BBCode, é convertida depois por ClickableWordText.
static func sanitize_bbcode(text: String, line_id: StringName) -> String:
	var regex := RegEx.new()
	regex.compile("\\[(/?)(\\w+)[^\\]]*\\]")
	var markup_regex: RegEx = RegEx.create_from_string("^%s$" % ClickableWordText.MARKUP_PATTERN)
	var removed: PackedStringArray = []
	var result: String = text
	for m: RegExMatch in regex.search_all(text):
		var tag_name: String = m.get_string(2).to_lower()
		if tag_name != "i" and tag_name != "b" and markup_regex.search(m.get_string()) == null:
			removed.append(m.get_string())
	for tag: String in removed:
		result = result.replace(tag, "")
	if not removed.is_empty():
		print("[Dialogue] - AVISO: tag %s removida da fala \"%s\"" % [", ".join(removed), line_id])
	return result


# Guarda a palavra sob o mouse e troca o cursor pra mãozinha enquanto ela estiver lá: é o que diz ao
# jogador que aquele sublinhado se clica.
func _set_hovered_word(payload: String) -> void:
	_hovered_word_payload = payload
	_text_label.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if not payload.is_empty() else Control.CURSOR_ARROW)


func _on_word_hover_started(meta: Variant) -> void:
	_set_hovered_word(str(meta))


func _on_word_hover_ended(_meta: Variant) -> void:
	_set_hovered_word("")


# Clique numa palavra do glossário: colhe a palavra (e o par dela, em [MARCOS]/[CASTRO]) e consome o
# clique, pra ele não pular a revelação nem confirmar "Continuar" na DialogueScreen. O redesenho sem
# sublinhado vem do evento glossary_word_discovered, que também atualiza as outras falas do log com a
# mesma palavra.
func _on_text_gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if _hovered_word_payload.is_empty():
		return
	_text_label.accept_event()
	# Cópia local: a colheita redesenha a fala (via evento) e o redesenho limpa _hovered_word_payload.
	var payload: String = _hovered_word_payload
	if ClickableWordText.collect_payload(payload):
		print("[Dialogue] - Palavra(s) \"%s\" colhida(s) da fala \"%s\"" % [payload, _line.line_id])


# Rede de segurança: a fala que nasce embaixo de um mouse parado não recebe meta_hover_started, e aí
# o apertar passa direto pra DialogueScreen. O soltar ainda colhe a palavra. No caminho normal isto
# não roda: o apertar já colheu, o redesenho tirou o link, e o soltar não acha mais palavra.
func _on_word_clicked(meta: Variant) -> void:
	ClickableWordText.collect_payload(str(meta))


# Qualquer palavra colhida (nesta fala, em outra fala do log ou fora do diálogo) pode ser uma das
# desta fala, que então precisa perder o sublinhado.
func _on_glossary_word_discovered(_npc_id: StringName, _word_id: StringName) -> void:
	if _has_glossary_words:
		refresh()


func _on_mouse_entered() -> void:
	if _state != EntryState.PAST or _style == null:
		return
	create_tween().tween_property(self, "modulate:a", _style.past_hover_alpha, _style.hover_out)


func _on_mouse_exited() -> void:
	if _state != EntryState.PAST or _style == null:
		return
	create_tween().tween_property(self, "modulate:a", _style.past_alpha, _style.hover_out)
