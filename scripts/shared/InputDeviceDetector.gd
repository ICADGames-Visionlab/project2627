## InputDeviceDetector - descobre se o jogador está usando o controle ou o teclado/mouse.
##
## COMO USAR: ninguém instancia isto à mão. O GameManager cria um como filho no _ready() dele, e quem
## precisa saber do dispositivo pergunta ao GameManager (GameManager.is_joypad_active()) ou escuta a
## TROCA pelo EventBus:
##
##     EventBus.input_device_changed.connect(_on_input_device_changed)
##
## POR QUE NÃO É UM AUTOLOAD: o guideline pede que Singleton novo passe pelo Lead, e não precisa — a
## pergunta "qual dispositivo está em uso" já tem dono global (o GameManager, que também guarda o
## esquema de movimentação). Este nó só separa a detecção do resto do GameManager, que é sobre cenas.
##
## POR QUE UM NÓ SEPARADO, e não _input() no próprio GameManager: a detecção precisa rodar com o jogo
## pausado (o jogador pega o controle no meio do menu de pausa), e trocar o process_mode do
## GameManager inteiro mexeria na troca de cenas dele. Aqui o PROCESS_MODE_ALWAYS vale só para isto.
##
## SÓ OBSERVA, NUNCA CONSOME: roda em _input e não chama set_input_as_handled(). O evento segue para
## quem mais precisar dele.
##
## O guia completo está em docs/suporte_a_controle.md.
class_name InputDeviceDetector
extends Node

## Espaço para constantes

const DEBUG_SECTION: StringName = &"Controle"

## Espaço para variáveis

# Movimento do mouse, em pixels, a partir do qual o jogador é considerado de volta ao mouse. Não é
# exposto aqui porque este nó nasce em código: o valor vem do GameManager (mouse_motion_threshold).
var mouse_motion_threshold: float = 3.0

# Inclinação do analógico (ou do gatilho) a partir da qual o jogador é considerado no controle. Vem
# do GameManager (joypad_axis_threshold).
var joypad_axis_threshold: float = 0.5

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Controle": a trava do checklist de docs/suporte_a_controle.md.
		DebugMenu.register_action(DEBUG_SECTION, "Autoteste do controle", _debug_run_self_test)


func _input(event: InputEvent) -> void:
	var device: int = detect_device(event, mouse_motion_threshold, joypad_axis_threshold)
	if device >= 0:
		GameManager.set_active_input_device(device as GameManager.InputDevice)

## Espaço para funções personalizadas

# Diz qual dispositivo um evento indica, ou -1 quando o evento não diz nada (tecla repetida, mouse
# tremendo parado na mesa, analógico na folga). Estática e sem estado para o autoteste poder
# perguntar sobre eventos montados à mão.
static func detect_device(event: InputEvent, mouse_threshold: float, axis_threshold: float) -> int:
	var joypad_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joypad_button != null:
		return GameManager.InputDevice.JOYPAD if joypad_button.pressed else -1
	var joypad_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joypad_motion != null:
		return GameManager.InputDevice.JOYPAD if absf(joypad_motion.axis_value) >= axis_threshold else -1
	var key: InputEventKey = event as InputEventKey
	if key != null:
		return GameManager.InputDevice.KEYBOARD_MOUSE if key.pressed and not key.echo else -1
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		return GameManager.InputDevice.KEYBOARD_MOUSE if mouse_button.pressed else -1
	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null:
		return GameManager.InputDevice.KEYBOARD_MOUSE if mouse_motion.relative.length() >= mouse_threshold else -1
	return -1


# Controle desconectado no meio do jogo: volta pro teclado/mouse, senão os avisos continuariam
# mostrando botões de um controle que nem está mais ali.
func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	print("[Input] - Controle %s (%d conectado(s))" % [
		"conectado" if connected else "desconectado", Input.get_connected_joypads().size()])
	if not connected and Input.get_connected_joypads().is_empty():
		GameManager.set_active_input_device(GameManager.InputDevice.KEYBOARD_MOUSE)


# [DEBUG] Roda o autoteste do suporte a controle e imprime o resultado no log.
func _debug_run_self_test() -> void:
	var self_test: ControllerSupportSelfTest = ControllerSupportSelfTest.new()
	self_test.run()
	print(self_test.report())
