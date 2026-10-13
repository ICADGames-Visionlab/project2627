# InsightInteractor.gd — O foco de teclado/controle no mundo: aciona os orbes de insight, os NPCs e os
# objetos interagíveis a partir do jogador (tecla de interagir, controle), e dá ao clique no orbe
# prioridade sobre o clique para andar.
#
# O NOME É HISTÓRICO: nasceu só para os orbes. Hoje o foco percorre também todo nó que cumpre o
# contrato de FocusTargets (NPCInteraction e Interactable cumprem) — é por ele que um NPC ou um objeto
# novo passa a funcionar no controle sem mexer aqui (ver docs/suporte_a_controle.md).
#
# Não contradiz a regra "não há tecla para revelar nada" (docs/insights.md): essa regra fala de
# ESCONDER orbes atrás de uma tecla. Aqui todo orbe continua sempre na tela; a tecla só ACIONA o que
# o jogador já está vendo. O acionamento passa por InsightMarker.activate(), o mesmo caminho do
# clique, então a fonte e a órbita não sabem, e não precisam saber, se o orbe foi clicado ou não.
#
# Foco: um dos alvos na tela fica marcado — o orbe com um anel, o NPC e o objeto com o contorno branco
# do hover. É ele que a tecla de interagir aciona.
#   - Sem escolha do jogador, o foco segue o alvo do mundo mais perto (orbe de ambiente, NPC com
#     conversa ou objeto interagível), ou a primeira cabeça se não houver nenhum na tela, e acompanha o
#     jogador enquanto ele anda.
#   - A tecla de ciclo passa o foco adiante e fixa a escolha, até aquele alvo sumir da tela.
#   - Nada tem alcance, mas só entra no foco o que estiver na tela: o mouse também só alcança o que o
#     jogador vê, e o ciclo não pode parar num alvo fora da câmera.
#   - O destaque só aparece no "modo teclado/controle": ele liga com a tecla de interagir, a de ciclo
#     ou qualquer botão/analógico do controle, e desliga quando o mouse se move. Quem joga de mouse não
#     vê o destaque pulando entre alvos a cada passo.
#   - Enquanto o modo teclado/controle está ligado, o hover do mouse não destaca nada. Sem isso,
#     clicar num orbe e apertar Tab deixava o orbe sob o cursor parado "em hover" ao lado do orbe em
#     foco — dois destaques e a mãozinha presa.
#
# Clique do mouse: com a movimentação por clique ligada, o clique esquerdo num orbe precisa abrir o
# insight e NÃO mover o personagem. Ver _handle_orb_click().
#
# Vive como filho do Player por dois motivos: "mais perto" é mais perto do jogador, e ser filho é o
# que garante receber o clique antes do Player (ver _handle_orb_click()). Tirar este nó de dentro do
# Player faz o clique no orbe voltar a mover o personagem.
#
# O guia completo está em docs/insights.md (orbes) e docs/suporte_a_controle.md (NPCs, objetos e o
# contrato de foco).
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

@export_group("Interação")
# Por quanto tempo, depois de uma conversa acabar, o botão de interagir não aciona nada. No controle,
# avançar a fala e falar com alguém são o mesmo botão (A): sem esta folga, quem aperta o A algumas
# vezes para passar as falas reabre a conversa no instante em que ela fecha, porque o foco volta pro
# mesmo NPC. Cada aperto dentro da folga recomeça a contagem, então quem continua martelando o A não
# reabre nada; quem para e aperta de novo fala normalmente.
@export_range(0.0, 2.0, 0.05) var interact_cooldown_after_conversation: float = 0.75

# Se o modo teclado/controle está ligado em algum InsightInteractor da árvore. Estático porque quem
# precisa perguntar (o InteractableInteractor, para não pôr hover do mouse) não conhece este nó.
static var _focus_mode_active: bool = false

var _is_focus_mode: bool = false
# O alvo com foco: um InsightMarker (orbe) ou um nó que cumpre o contrato de FocusTargets.
var _focused_target: Node = null
# Diz se o foco atual foi escolhido pelo ciclo. Foco escolhido fica parado; foco automático segue o
# alvo mais perto.
var _is_manual_focus: bool = false
var _target_sources: Dictionary = {}    # InsightMarker -> InsightSource (só orbes de ambiente)

# Verdadeiro enquanto uma conversa está aberta: os orbes desligam (SPEC §11.5).
var _is_input_locked: bool = false

# Instante (Time.get_ticks_msec) até o qual o botão de interagir fica sem efeito depois de uma conversa.
# Relógio de verdade, e não o do jogo, porque a folga é sobre a mão do jogador, não sobre o mundo.
var _interact_blocked_until_msec: int = 0


func _ready() -> void:
	set_process(false)
	EventBus.conversation_approach_started.connect(_on_conversation_started)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.conversation_ended.connect(_on_conversation_ended)


func _exit_tree() -> void:
	_set_focused_target(null)
	# O estado de hover é estático: sair da árvore em modo teclado/controle (troca de cena) não pode
	# deixar a próxima cena com o hover do mouse desligado.
	InsightMarker.set_mouse_hover_suppressed(false, get_tree())
	_focus_mode_active = false


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


# Com um menu aberto (as evidências, que não pausam o jogo), a tecla de interagir e a de ciclo ficam
# com o menu: o A que apertou um botão do painel não pode, por baixo dele, acionar o orbe mais perto.
func _unhandled_input(event: InputEvent) -> void:
	if _is_input_locked:
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_handle_orb_click(mouse_button)
		return
	if MenuFocus.is_any_menu_open():
		return
	if event.is_action_pressed(INTERACT_ACTION) and Time.get_ticks_msec() < _interact_blocked_until_msec:
		# Consumido, para o mesmo aperto não virar outra coisa por baixo. E a folga recomeça: quem
		# continua apertando o A sem parar ainda está passando falas, não querendo falar de novo.
		get_viewport().set_input_as_handled()
		_start_interact_cooldown()
		return
	if event.is_action_pressed(INTERACT_ACTION):
		get_viewport().set_input_as_handled()
		_set_focus_mode(true)
		_interact()
	elif event.is_action_pressed(CYCLE_ACTION):
		get_viewport().set_input_as_handled()
		_set_focus_mode(true)
		_cycle_focus()


func _process(_delta: float) -> void:
	# Durante a conversa nada fica em foco: o NPC que está falando não pode continuar com o contorno
	# de "aperte para falar comigo".
	if _is_input_locked:
		return
	# Refeito a cada quadro enquanto o modo teclado/controle está ligado: o jogador anda, alvos entram
	# e saem da tela, e o foco automático precisa acompanhar.
	_update_focus(_collect_targets())


# Diz se o modo teclado/controle está ligado (o foco é o único destaque, o hover do mouse não conta).
static func is_focus_mode_active() -> bool:
	return _focus_mode_active


# Aciona o alvo em foco. Apertar de novo num orbe de ambiente com a caixa aberta fecha a caixa: sem
# isso, quem joga de controle só teria o botão de cancelar para fechar, e apertar o mesmo botão duas
# vezes para abrir e fechar é o que a mão espera.
func _interact() -> void:
	_update_focus(_collect_targets())
	if _focused_target == null:
		print("[Insights] - Interagir: nenhum alvo na tela")
		return
	var marker: InsightMarker = _focused_target as InsightMarker
	if marker == null:
		# NPC ou objeto: o clique em qualquer coisa fecha a caixa de insight aberta, e a tecla faz o
		# mesmo antes de acionar.
		_close_bubbles_except(null)
		_focused_target.call(&"activate_focus", get_parent() as Player)
		return
	var source: InsightSource = _target_sources.get(marker, null) as InsightSource
	if source != null and source.is_bubble_open():
		source.close_bubble()
		print("[Insights] - Interagir: caixa de \"%s\" fechada" % source.name)
		return
	# O clique do mouse fecha a caixa aberta em outro lugar (qualquer clique fecha). A tecla precisa
	# fazer o mesmo, senão duas caixas ficariam abertas ao mesmo tempo.
	_close_bubbles_except(source)
	print("[Insights] - Interagir: orbe acionado pelo teclado/controle")
	marker.activate()


# Resolve o clique esquerdo num orbe antes de ele virar movimento. No esquema de clique, o Player
# anda até o ponto clicado em _unhandled_input — que roda ANTES do physics picking que entregaria o
# clique ao orbe —, então clicar num orbe também faria o personagem sair andando até ele.
#
# Funciona porque este nó é filho do Player: a engine chama _unhandled_input dos nós mais adiante na
# árvore primeiro, e filho vem depois do pai. A caixa de texto (filha de uma fonte, depois do Player)
# recebe o clique antes daqui e já consome o clique no próprio orbe.
func _handle_orb_click(event: InputEventMouseButton) -> void:
	var hit_marker: InsightMarker = null
	var hit_distance: float = INF
	for target: Node in _collect_targets():
		var marker: InsightMarker = target as InsightMarker
		if marker == null or not marker.is_mouse_event_inside(event):
			continue
		# Orbes sobrepostos: vence o de centro mais perto do clique.
		var local_event: InputEventMouse = marker.make_input_local(event) as InputEventMouse
		var distance: float = local_event.position.length()
		if distance < hit_distance:
			hit_distance = distance
			hit_marker = marker
	if hit_marker == null:
		return
	get_viewport().set_input_as_handled()
	hit_marker.activate()


# Passa o foco para o próximo alvo, na ordem de _collect_targets(), e fixa a escolha.
func _cycle_focus() -> void:
	var targets: Array[Node] = _collect_targets()
	if targets.is_empty():
		_set_focused_target(null)
		print("[Insights] - Ciclo de foco: nenhum alvo na tela")
		return
	if not is_instance_valid(_focused_target):
		_focused_target = null
	var index: int = targets.find(_focused_target) if _focused_target != null else -1
	_set_focused_target(targets[(index + 1) % targets.size()])
	_is_manual_focus = true


# Alvos que dá para acionar agora, na ordem em que o ciclo percorre: primeiro os do mundo na tela
# (orbes de ambiente, NPCs, objetos), do mais perto para o mais longe, depois as cabeças da esquerda
# para a direita.
func _collect_targets() -> Array[Node]:
	_target_sources.clear()
	var targets: Array[Node] = []
	var screen_rect: Rect2 = get_viewport().get_visible_rect()
	for source: InsightSource in InsightDirector.get_sources():
		var marker: InsightMarker = source.get_marker()
		if marker == null or marker.is_queued_for_deletion():
			continue
		if not screen_rect.has_point(marker.get_global_transform_with_canvas().origin):
			continue
		targets.append(marker)
		_target_sources[marker] = source
	targets.append_array(FocusTargets.collect_on_screen(get_tree(), screen_rect))
	targets.sort_custom(_is_closer)
	var orbit_layer: HeadOrbitLayer = InsightDirector.get_orbit_layer()
	if orbit_layer != null:
		for marker: InsightMarker in orbit_layer.get_markers():
			if not marker.is_queued_for_deletion():
				targets.append(marker)
	return targets


# Mantém o foco coerente com os alvos atuais. Foco escolhido pelo ciclo fica enquanto o alvo
# continuar na lista; foco automático (ou escolhido que saiu da lista) vai para o primeiro alvo.
func _update_focus(targets: Array[Node]) -> void:
	if not is_instance_valid(_focused_target):
		_focused_target = null
	var is_focus_still_valid: bool = _focused_target != null and targets.has(_focused_target)
	if _is_manual_focus and is_focus_still_valid:
		return
	_is_manual_focus = false
	_set_focused_target(targets[0] if not targets.is_empty() else null)


# Liga ou desliga o modo teclado/controle. Ligado, o hover do mouse deixa de destacar orbes, NPCs e
# objetos (só o foco destaca). Desligado, nada fica com foco, o hover volta a valer e o processamento
# por quadro para.
func _set_focus_mode(enabled: bool) -> void:
	if _is_focus_mode == enabled:
		return
	_is_focus_mode = enabled
	_focus_mode_active = enabled
	set_process(enabled)
	InsightMarker.set_mouse_hover_suppressed(enabled, get_tree())
	get_tree().call_group(FocusTargets.GROUP, &"set_mouse_hover_suppressed", enabled)
	if enabled:
		_update_focus(_collect_targets())
	else:
		_is_manual_focus = false
		_set_focused_target(null)
	print("[Insights] - Foco por teclado/controle %s" % ("ligado" if enabled else "desligado"))


# Troca o alvo em foco, apagando o destaque do anterior. Tolera o anterior já ter sido liberado:
# orbes somem sozinhos quando o jogador lê o último insight de um lugar, e evidências somem ao serem
# coletadas.
func _set_focused_target(target: Node) -> void:
	if not is_instance_valid(_focused_target):
		_focused_target = null
	if target == _focused_target:
		return
	if _focused_target != null:
		_focused_target.call(&"set_focused", false)
	_focused_target = target
	if _focused_target != null:
		_focused_target.call(&"set_focused", true)


# Fecha as caixas abertas de todas as fontes, menos a informada (que pode ser null, para fechar
# todas).
func _close_bubbles_except(kept_source: InsightSource) -> void:
	for source: InsightSource in InsightDirector.get_sources():
		if source != kept_source and source.is_bubble_open():
			source.close_bubble()


# Ordena dois alvos do mundo pela distância até o jogador.
func _is_closer(left: Node, right: Node) -> bool:
	return global_position.distance_squared_to(_world_position_of(left)) \
		< global_position.distance_squared_to(_world_position_of(right))


# Posição no mundo de um alvo: o orbe é um Node2D; os outros dizem pelo contrato.
func _world_position_of(target: Node) -> Vector2:
	var marker: InsightMarker = target as InsightMarker
	if marker != null:
		return marker.global_position
	return target.call(&"get_focus_world_position")


func _on_conversation_started(_conversation_id: StringName, _initiator_id: StringName) -> void:
	_is_input_locked = true
	_set_focused_target(null)


# Destrava o foco no fim da conversa e liga a folga do botão de interagir (ver
# interact_cooldown_after_conversation).
func _on_conversation_ended(_conversation_id: StringName, _end_node_id: StringName) -> void:
	_is_input_locked = false
	_start_interact_cooldown()


# Bloqueia o botão de interagir por interact_cooldown_after_conversation a partir de agora.
func _start_interact_cooldown() -> void:
	_interact_blocked_until_msec = Time.get_ticks_msec() + int(interact_cooldown_after_conversation * 1000.0)
