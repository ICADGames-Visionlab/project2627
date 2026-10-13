## InputGlyphs - escreve na tela a tecla ou o botão de uma ação, no dispositivo que o jogador está
## usando: "Aperte ESPAÇO para dormir" no teclado, "Aperte X para dormir" no controle.
##
## COMO USAR: os textos do CSV citam AÇÕES do Input Map entre chaves, nunca a tecla:
##
##     PROMPT_SLEEP,Press {sleep} to sleep,Aperte {sleep} para dormir
##
## e quem desenha o texto passa a chave por aqui em vez de chamar tr() direto:
##
##     label.text = InputGlyphs.tr_prompt("PROMPT_SLEEP")
##
## Trocar a tecla de uma ação (Projeto > Input Map) muda o aviso sozinho; ninguém reescreve texto.
##
## VARIANTE DE CONTROLE: quando a frase inteira muda no controle (no mouse é "Clique para continuar",
## no controle é "Aperte A para continuar"), escreva uma segunda chave com o sufixo _JOYPAD. Com o
## controle em uso, tr_prompt() usa ela; sem ela, usa a chave normal com o botão no lugar.
##
## OS NOMES DAS TECLAS E BOTÕES também estão no CSV (INPUT_KEY_*, INPUT_JOY_BUTTON_*, INPUT_JOY_AXIS_*,
## INPUT_MOUSE_*), para "ESPAÇO" sair em português. Tecla sem nome no CSV cai no nome que a engine dá,
## em maiúsculas (letras e números não precisam de chave).
##
## Classe só de funções estáticas: não é Autoload nem nó, porque não guarda estado nenhum.
##
## O guia completo está em docs/suporte_a_controle.md.
class_name InputGlyphs
extends RefCounted

## Espaço para constantes

# "{nome_da_acao}" dentro de um texto traduzido. Minúsculas, como os nomes do Input Map: é o que
# separa o marcador de uma chave de tradução, que é em maiúsculas.
const PLACEHOLDER_PATTERN: String = "\\{([a-z][a-z0-9_]*)\\}"

# Sufixo da variante de controle de uma chave de texto (ver o cabeçalho).
const JOYPAD_KEY_SUFFIX: String = "_JOYPAD"

## Espaço para funções personalizadas

# Texto da chave pronto para a tela, no dispositivo em uso (ou no informado): a variante _JOYPAD
# quando o controle está em uso e ela existe, e cada {acao} trocado pela tecla/botão dela.
static func tr_prompt(key: String, device: int = -1) -> String:
	if device < 0:
		device = GameManager.active_input_device
	var text: String = _translate(key)
	if device == GameManager.InputDevice.JOYPAD:
		var joypad_key: String = key + JOYPAD_KEY_SUFFIX
		var joypad_text: String = _translate(joypad_key)
		if joypad_text != joypad_key:
			text = joypad_text
	return format_actions(text, device)


# Troca cada {acao} de um texto já traduzido pela tecla/botão da ação no dispositivo. Ação que não
# existe no Input Map fica escrita como está e avisa: é erro de digitação no CSV, e o autoteste do
# controle também acusa.
static func format_actions(text: String, device: int) -> String:
	var regex: RegEx = RegEx.create_from_string(PLACEHOLDER_PATTERN)
	var result: String = text
	for match_result: RegExMatch in regex.search_all(text):
		var action: StringName = StringName(match_result.get_string(1))
		if not InputMap.has_action(action):
			push_warning("[Input] - AVISO: o texto cita a ação \"%s\", que não existe no Input Map" % action)
			continue
		result = result.replace(match_result.get_string(0), action_label(action, device))
	return result


# Nome curto da tecla/botão de uma ação no dispositivo: o primeiro evento da ação que é daquele
# dispositivo. Teclado/mouse prefere tecla a botão do mouse; controle prefere botão a analógico.
# Ação sem nenhum evento do dispositivo devolve "?" — o autoteste do controle impede isso nas ações
# de jogo.
static func action_label(action: StringName, device: int) -> String:
	var event: InputEvent = find_event(action, device)
	return event_label(event) if event != null else "?"


# O evento de uma ação que o dispositivo usaria, ou null. Pública porque o autoteste do controle
# pergunta a mesma coisa ("esta ação tem botão no controle?") sem montar texto.
static func find_event(action: StringName, device: int) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var preferred: Array = [InputEventJoypadButton, InputEventJoypadMotion] \
		if device == GameManager.InputDevice.JOYPAD else [InputEventKey, InputEventMouseButton]
	for kind: Variant in preferred:
		for event: InputEvent in events:
			if is_instance_of(event, kind):
				return event
	return null


# Nome curto de um evento, traduzido quando o CSV tem nome pra ele.
static func event_label(event: InputEvent) -> String:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		var keycode: Key = key_event.keycode
		if key_event.physical_keycode != KEY_NONE:
			# Tecla física (WASD, E, F): o nome que importa é o da tecla NAQUELE teclado, então a
			# posição física é convertida no layout do jogador antes de virar texto.
			keycode = DisplayServer.keyboard_get_keycode_from_physical(key_event.physical_keycode)
		var key_name: String = OS.get_keycode_string(keycode)
		return _translate_or("INPUT_KEY_" + key_name.to_upper().replace(" ", "_"), key_name.to_upper())
	var joypad_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joypad_button != null:
		return _translate_or("INPUT_JOY_BUTTON_%d" % joypad_button.button_index,
			"JOY %d" % joypad_button.button_index)
	var joypad_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joypad_motion != null:
		var direction: String = "NEG" if joypad_motion.axis_value < 0.0 else "POS"
		return _translate_or("INPUT_JOY_AXIS_%d_%s" % [joypad_motion.axis, direction],
			"AXIS %d" % joypad_motion.axis)
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		return _translate_or("INPUT_MOUSE_%d" % mouse_button.button_index,
			"MOUSE %d" % mouse_button.button_index)
	return event.as_text() if event != null else "?"


# tr() para função estática: estática não tem o tr() de Object, e a tradução é a mesma do resto do
# jogo (o TranslationServer, no idioma escolhido nas opções).
static func _translate(key: String) -> String:
	return String(TranslationServer.translate(key))


# Tradução da chave, ou o texto de reserva quando o CSV não tem a chave.
static func _translate_or(key: String, fallback: String) -> String:
	var translated: String = _translate(key)
	return fallback if translated == key else translated
