# InsightInteractor.gd — Abre insights sem mouse: tecla de interagir e controle.
#
# Não contradiz a regra "não há tecla para revelar nada" (docs/insights.md): essa regra fala de
# ESCONDER orbes atrás de uma tecla. Aqui todo orbe continua sempre na tela; a tecla só ACIONA o que
# o jogador já está vendo. O acionamento passa por InsightMarker.activate(), o mesmo caminho do
# clique, então a fonte e a órbita não sabem, e não precisam saber, se o orbe foi clicado ou não.
#
# Foco: um dos orbes na tela fica marcado com um anel — é ele que a tecla de interagir aciona.
#   - Sem escolha do jogador, o foco segue o orbe de ambiente mais perto (ou a primeira cabeça, se
#     não houver orbe de ambiente na tela), e acompanha o jogador enquanto ele anda.
#   - A tecla de ciclo passa o foco adiante e fixa a escolha, até aquele orbe sumir da tela.
#   - Orbe de ambiente não tem alcance, mas só entra no foco se estiver na tela: o mouse também só
#     alcança o que o jogador vê, e o ciclo não pode parar num orbe fora da câmera.
#   - O anel só aparece no "modo teclado/controle": ele liga com a tecla de interagir, a de ciclo ou
#     qualquer botão/analógico do controle, e desliga quando o mouse se move. Quem joga de mouse não
#     vê um anel pulando entre orbes a cada passo.
#
# Vive como filho do Player, porque "mais perto" é mais perto do jogador.
#
# O guia completo está em docs/insights.md.
class_name InsightInteractor
extends Node2D

const INTERACT_ACTION: StringName = &"insight_interact"
const CYCLE_ACTION: StringName = &"insight_cycle"

@export_group("Detecção de dispositivo")
# Movimento do mouse, em pixels, a partir do qual o jogador é considerado de volta ao mouse. Evita
# que o tremor de um mouse parado na mesa desligue o foco no meio do uso do controle.
@export var mouse_motion_threshold: float = 3.0
# Inclinação do analógico a partir da qual o jogador é considerado jogando de controle. Abaixo disso
# é folga do analógico parado, não intenção.
@export var joypad_axis_threshold: float = 0.5

var _is_focus_mode: bool = false
var _focused_marker: InsightMarker = null
# Diz se o foco atual foi escolhido pelo ciclo. Foco escolhido fica parado; foco automático segue o
# orbe mais perto.
var _is_manual_focus: bool = false
var _target_sources: Dictionary = {}    # InsightMarker -> InsightSource (só orbes de ambiente)


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	_set_focused_marker(null)


func _input(event: InputEvent) -> void:
	# Só observa, nunca consome: aqui se decide qual dispositivo o jogador está usando, e o evento
	# continua valendo para quem mais precisar dele.
	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null:
		if mouse_motion.relative.length() >= mouse_motion_threshold:
			_set_focus_mode(false)
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.pressed:
			_set_focus_mode(false)
		return
	var joypad_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joypad_button != null:
		if joypad_button.pressed:
			_set_focus_mode(true)
		return
	var joypad_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joypad_motion != null and absf(joypad_motion.axis_value) >= joypad_axis_threshold:
		_set_focus_mode(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(INTERACT_ACTION):
		get_viewport().set_input_as_handled()
		_set_focus_mode(true)
		_interact()
	elif event.is_action_pressed(CYCLE_ACTION):
		get_viewport().set_input_as_handled()
		_set_focus_mode(true)
		_cycle_focus()


func _process(_delta: float) -> void:
	# Refeito a cada quadro enquanto o modo teclado/controle está ligado: o jogador anda, orbes entram
	# e saem da tela, e o foco automático precisa acompanhar.
	_update_focus(_collect_targets())


# Aciona o orbe em foco. Apertar de novo num orbe de ambiente com a caixa aberta fecha a caixa: sem
# isso, quem joga de controle só teria o botão de cancelar para fechar, e apertar o mesmo botão duas
# vezes para abrir e fechar é o que a mão espera.
func _interact() -> void:
	_update_focus(_collect_targets())
	if _focused_marker == null:
		print("[Insights] - Interagir: nenhum orbe na tela")
		return
	var source: InsightSource = _target_sources.get(_focused_marker, null) as InsightSource
	if source != null and source.is_bubble_open():
		source.close_bubble()
		print("[Insights] - Interagir: caixa de \"%s\" fechada" % source.name)
		return
	# O clique do mouse fecha a caixa aberta em outro lugar (qualquer clique fecha). A tecla precisa
	# fazer o mesmo, senão duas caixas ficariam abertas ao mesmo tempo.
	_close_bubbles_except(source)
	print("[Insights] - Interagir: orbe acionado pelo teclado/controle")
	_focused_marker.activate()


# Passa o foco para o próximo orbe, na ordem de _collect_targets(), e fixa a escolha.
func _cycle_focus() -> void:
	var targets: Array[InsightMarker] = _collect_targets()
	if targets.is_empty():
		_set_focused_marker(null)
		print("[Insights] - Ciclo de foco: nenhum orbe na tela")
		return
	if not is_instance_valid(_focused_marker):
		_focused_marker = null
	var index: int = targets.find(_focused_marker) if _focused_marker != null else -1
	_set_focused_marker(targets[(index + 1) % targets.size()])
	_is_manual_focus = true


# Orbes que dá para acionar agora, na ordem em que o ciclo percorre: primeiro os de ambiente na tela,
# do mais perto para o mais longe, depois as cabeças da esquerda para a direita.
func _collect_targets() -> Array[InsightMarker]:
	_target_sources.clear()
	var targets: Array[InsightMarker] = []
	var screen_rect: Rect2 = get_viewport().get_visible_rect()
	for source: InsightSource in InsightDirector.get_sources():
		var marker: InsightMarker = source.get_marker()
		if marker == null or marker.is_queued_for_deletion():
			continue
		if not screen_rect.has_point(marker.get_global_transform_with_canvas().origin):
			continue
		targets.append(marker)
		_target_sources[marker] = source
	targets.sort_custom(_is_closer)
	var orbit_layer: HeadOrbitLayer = InsightDirector.get_orbit_layer()
	if orbit_layer != null:
		for marker: InsightMarker in orbit_layer.get_markers():
			if not marker.is_queued_for_deletion():
				targets.append(marker)
	return targets


# Mantém o foco coerente com os alvos atuais. Foco escolhido pelo ciclo fica enquanto o orbe
# continuar na lista; foco automático (ou escolhido que saiu da lista) vai para o primeiro alvo.
func _update_focus(targets: Array[InsightMarker]) -> void:
	if not is_instance_valid(_focused_marker):
		_focused_marker = null
	var is_focus_still_valid: bool = _focused_marker != null and targets.has(_focused_marker)
	if _is_manual_focus and is_focus_still_valid:
		return
	_is_manual_focus = false
	_set_focused_marker(targets[0] if not targets.is_empty() else null)


# Liga ou desliga o modo teclado/controle. Desligado, nenhum orbe fica com anel e o processamento
# por quadro para.
func _set_focus_mode(enabled: bool) -> void:
	if _is_focus_mode == enabled:
		return
	_is_focus_mode = enabled
	set_process(enabled)
	if enabled:
		_update_focus(_collect_targets())
	else:
		_is_manual_focus = false
		_set_focused_marker(null)
	print("[Insights] - Foco por teclado/controle %s" % ("ligado" if enabled else "desligado"))


# Troca o orbe em foco, apagando o anel do anterior. Tolera o anterior já ter sido liberado: orbes
# somem sozinhos quando o jogador lê o último insight de um lugar.
func _set_focused_marker(marker: InsightMarker) -> void:
	if not is_instance_valid(_focused_marker):
		_focused_marker = null
	if marker == _focused_marker:
		return
	if _focused_marker != null:
		_focused_marker.set_focused(false)
	_focused_marker = marker
	if _focused_marker != null:
		_focused_marker.set_focused(true)


# Fecha as caixas abertas de todas as fontes, menos a informada (que pode ser null, para fechar
# todas).
func _close_bubbles_except(kept_source: InsightSource) -> void:
	for source: InsightSource in InsightDirector.get_sources():
		if source != kept_source and source.is_bubble_open():
			source.close_bubble()


# Ordena dois orbes de ambiente pela distância até o jogador.
func _is_closer(left: InsightMarker, right: InsightMarker) -> bool:
	return global_position.distance_squared_to(left.global_position) < global_position.distance_squared_to(right.global_position)
