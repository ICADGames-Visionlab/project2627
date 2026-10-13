## MenuFocus - faz um menu funcionar no controle (e nas setas do teclado) sem código no menu.
##
## COMO USAR: adicione um nó MenuFocus DENTRO do menu (Adicionar Nó > MenuFocus: ele aparece na lista
## por ter class_name) e preencha no Inspector:
##
##   Menu Root      o Control que, visível, quer dizer "o menu está aberto". Vazio = o pai.
##   Initial Focus  quem recebe o foco ao abrir. Vazio = o primeiro Control focável dentro do menu.
##   Cancel Button  o botão apertado pelo ui_cancel (B no controle, ESC no teclado) com o menu aberto
##                  — normalmente o "Voltar"/"Fechar". Vazio = o menu não responde ao cancelar.
##
## O QUE ELE FAZ:
##   - Menu abre com o controle em uso -> foco no Initial Focus, pra o D-pad e o A funcionarem na hora.
##   - O jogador pega o controle com o menu já aberto -> mesmo foco. O aperto que trouxe o controle
##     só põe o foco, não anda com ele (o jogador começa no primeiro botão, não no segundo).
##   - Seta/D-pad apertado sem nada focado -> o primeiro aperto só põe o foco (não se perde).
##   - ui_cancel com o menu aberto -> aperta o Cancel Button.
##   - Botão desabilitado fica fora do caminho do D-pad (Skip Disabled Buttons): o cursor não para num
##     "Continuar" sem save, onde o A não faria nada.
##
## Com o mouse, ele não mexe em foco nenhum: quem joga de mouse não vê o contorno de foco pulando
## pela tela sem ter pedido.
##
## SÓ O MENU DE CIMA RESPONDE: um menu que o jogo pausou por baixo de outro (as evidências, com o
## diário ou a pausa aberta por cima) fica quieto até voltar a rodar — senão o B fecharia a tela de
## baixo em vez da de cima. E quem cuida do MUNDO (andar, interagir, fechar a caixa de um orbe) pergunta
## MenuFocus.is_any_menu_open() antes de reagir a um botão que os menus também usam (A, B, D-pad).
##
## DIÁLOGO DE CONFIRMAÇÃO (AcceptDialog/ConfirmationDialog) dentro do menu: chame
## MenuFocus.bind_joypad_cancel(dialogo) no _ready() do menu, para o B cancelar como o ESC cancela.
##
## MENU MONTADO EM CÓDIGO (a lista de evidências, que se refaz a cada mudança): troque initial_focus
## quando a lista mudar e chame focus_initial() se o foco estava dentro dela — o nó que tinha foco
## foi liberado junto com a lista antiga. Se o foco de entrada depende do estado da tela (a tela de
## profiling: primeira emoção, ou primeira palavra, ou a seta de voltar), passe um Callable em
## initial_focus_provider que devolve o Control certo na hora.
##
## O guia completo está em docs/suporte_a_controle.md.
class_name MenuFocus
extends Node

## Espaço para constantes

# As ações de navegação que, apertadas sem nada focado, só servem pra pôr o foco no menu.
const NAVIGATION_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]

# Onde um botão desabilitado guarda o focus_mode que tinha, para devolvê-lo quando voltar a valer.
const ORIGINAL_FOCUS_MODE_META: StringName = &"menu_focus_original_focus_mode"

## Espaço para variáveis exportadas

## O Control que, visível, quer dizer "o menu está aberto". Vazio = o pai deste nó.
@export var menu_root: Control

## Quem recebe o foco ao abrir. Vazio = o primeiro Control focável dentro de menu_root.
@export var initial_focus: Control

## Apertado pelo ui_cancel (B / ESC) com o menu aberto. Vazio = o cancelar passa adiante.
@export var cancel_button: BaseButton

## Tira do caminho do D-pad os botões desabilitados do menu (e devolve quando eles voltam a valer).
@export var skip_disabled_buttons: bool = true

## Espaço para variáveis

# Opcional: devolve o Control que deve receber o foco agora, para telas cujo foco de entrada muda com
# o estado (ver o cabeçalho). Quando devolve null, ou um Control que não pode receber foco, vale o
# initial_focus.
var initial_focus_provider: Callable = Callable()

# Todos os MenuFocus na árvore. Estático para quem cuida do mundo poder perguntar "tem menu aberto?"
# sem conhecer menu nenhum (ver is_any_menu_open).
static var _instances: Array[MenuFocus] = []

## Espaço para funções nativas

func _enter_tree() -> void:
	if not _instances.has(self):
		_instances.append(self)


func _exit_tree() -> void:
	_instances.erase(self)


func _ready() -> void:
	# Menus aparecem com o jogo pausado (pausa, profiling, diário): o foco precisa responder igual. Quem
	# decide se ESTE menu responde agora é is_menu_active(), que olha se o menu em si está rodando.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_root == null:
		menu_root = get_parent() as Control
	if menu_root == null:
		push_warning("[MenuFocus] - AVISO: \"%s\" sem menu_root e com pai que não é Control; desligado" % get_path())
		set_process_unhandled_input(false)
		return
	menu_root.visibility_changed.connect(_on_menu_visibility_changed)
	EventBus.input_device_changed.connect(_on_input_device_changed)
	if is_menu_open():
		_on_menu_visibility_changed()


# _unhandled_input: o que um Control focado consome (o D-pad navegando, o A apertando um botão) nem
# chega aqui. Só chega o que ninguém pegou — é exatamente o caso "nada focado" e o cancelar.
func _unhandled_input(event: InputEvent) -> void:
	if not is_menu_active():
		return
	if cancel_button != null and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		print("[MenuFocus] - Cancelar no menu \"%s\": apertando \"%s\"" % [menu_root.name, cancel_button.name])
		cancel_button.pressed.emit()
		return
	if _has_focus_inside():
		return
	for action: StringName in NAVIGATION_ACTIONS:
		if event.is_action_pressed(action):
			if focus_initial():
				get_viewport().set_input_as_handled()
			return

## Espaço para funções personalizadas

# Diz se algum menu com MenuFocus está aberto e respondendo agora. É a pergunta de quem cuida do mundo
# antes de reagir a um botão que os menus também usam: com as evidências abertas, o A aperta o botão do
# painel e não aciona o orbe atrás dele, o analógico navega o painel e não anda com o personagem, e o B
# fecha o painel e não a caixa do orbe.
static func is_any_menu_open() -> bool:
	for instance: MenuFocus in _instances:
		if is_instance_valid(instance) and instance.is_menu_active():
			return true
	return false


# Diz se o menu está aberto (visível na tela, e não só com visible ligado num pai escondido).
func is_menu_open() -> bool:
	return menu_root != null and menu_root.is_visible_in_tree()


# Diz se o menu está aberto E rodando. Um menu pausável que ficou por baixo de uma tela que pausa o jogo
# (as evidências por baixo do diário ou da pausa) continua visível, mas não responde: o B é da tela de
# cima.
func is_menu_active() -> bool:
	return is_menu_open() and menu_root.can_process()


# Põe o foco no Initial Focus (ou no que o initial_focus_provider escolher), ou no primeiro focável do
# menu. Devolve se conseguiu.
func focus_initial() -> bool:
	refresh_focus_modes()
	var target: Control = _provided_focus()
	if target == null:
		target = initial_focus if can_take_focus(initial_focus) else find_first_focusable(menu_root)
	if target == null:
		return false
	target.grab_focus()
	return true


# Tira do foco os botões desabilitados do menu e devolve o foco aos que voltaram a valer. Roda sozinho
# quando o menu abre e quando o jogador pega o controle; um menu que desabilita botão com ele já aberto
# (e com o controle em uso) chama de novo logo depois.
func refresh_focus_modes() -> void:
	if not skip_disabled_buttons or menu_root == null:
		return
	for node: Node in menu_root.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		if button.disabled:
			if button.focus_mode != Control.FOCUS_NONE:
				button.set_meta(ORIGINAL_FOCUS_MODE_META, button.focus_mode)
				button.focus_mode = Control.FOCUS_NONE
		elif button.has_meta(ORIGINAL_FOCUS_MODE_META):
			button.focus_mode = button.get_meta(ORIGINAL_FOCUS_MODE_META) as Control.FocusMode
			button.remove_meta(ORIGINAL_FOCUS_MODE_META)


# Primeiro Control focável dentro de root, na ordem da árvore (de cima pra baixo na tela, na maioria
# dos menus). Estática para quem monta foco à mão (a tela de profiling) usar a mesma regra.
static func find_first_focusable(root: Node) -> Control:
	if root == null:
		return null
	for child: Node in root.get_children():
		var control: Control = child as Control
		if control != null and can_take_focus(control):
			return control
		var nested: Control = find_first_focusable(child)
		if nested != null:
			return nested
	return null


# Diz se o Control pode receber foco agora: existe, está na tela, aceita foco e não está desligado.
static func can_take_focus(control: Control) -> bool:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	var button: BaseButton = control as BaseButton
	return button == null or not button.disabled


# Liga o foco de um Control só enquanto o controle está em uso. É para peça que a cena tirou do foco de
# propósito por causa do mouse (um botão que, focado, desenharia o contorno de foco depois de cada
# clique) mas que precisa ser alcançável pelo D-pad. Quem chama também escuta
# EventBus.input_device_changed e chama de novo — ver GlossaryWordChip, por exemplo.
static func apply_joypad_focus_mode(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL if GameManager.is_joypad_active() else Control.FOCUS_NONE


# Faz o B do controle cancelar um AcceptDialog/ConfirmationDialog. A Godot fecha esses diálogos no ESC
# sozinha, mas não no B, mesmo com o B no ui_cancel (testado na 4.7) — o D-pad e o A já funcionam
# dentro deles. Cancelar aqui é o mesmo caminho do ESC: esconde e emite canceled. Só o evento do
# controle: o ESC continua com a Godot, senão o canceled sairia duas vezes.
static func bind_joypad_cancel(dialog: AcceptDialog) -> void:
	dialog.window_input.connect(func(event: InputEvent) -> void:
		if not dialog.visible or not event is InputEventJoypadButton:
			return
		if event.is_action_pressed(&"ui_cancel"):
			dialog.set_input_as_handled()
			dialog.hide()
			dialog.canceled.emit()
			print("[MenuFocus] - Diálogo \"%s\" cancelado pelo controle" % dialog.name))


# O Control que o initial_focus_provider escolheu, se ele escolheu um que pode receber foco agora.
func _provided_focus() -> Control:
	if not initial_focus_provider.is_valid():
		return null
	var provided: Control = initial_focus_provider.call() as Control
	return provided if can_take_focus(provided) else null


# Diz se o foco atual está dentro deste menu.
func _has_focus_inside() -> bool:
	var owner_control: Control = menu_root.get_viewport().gui_get_focus_owner()
	return owner_control != null and (owner_control == menu_root or menu_root.is_ancestor_of(owner_control))


# Menu abriu com o controle em uso: foco nele. Adiado pro fim do quadro porque o menu pode estar
# terminando de se montar (lista refeita no mesmo quadro em que aparece).
func _on_menu_visibility_changed() -> void:
	if not is_menu_open():
		return
	refresh_focus_modes()
	if GameManager.is_joypad_active():
		focus_if_needed.call_deferred()


# O jogador pegou o controle com o menu aberto e nada focado nele: foco no menu.
# Adiado pro fim do quadro de propósito: a troca é avisada no meio do evento que a causou, antes de a
# interface recebê-lo. Focando na hora, aquele mesmo aperto do D-pad já andaria o foco, e o jogador
# começaria no segundo botão. Adiado, o aperto chega sem nada focado e só põe o foco
# (_unhandled_input); quando a troca veio de um analógico ou de outro botão, o adiado foca sozinho.
func _on_input_device_changed(device: int) -> void:
	if device == GameManager.InputDevice.JOYPAD and is_menu_active():
		refresh_focus_modes()
		focus_if_needed.call_deferred()


# Foca o menu se o foco ainda não estiver nele (quem abriu o menu pode já ter posto o foco). Pública
# para telas que trocam de conteúdo com o menu aberto (a tela de profiling, ao trocar de vista): o
# foco que estava na parte que sumiu se perde, e esta chamada põe o foco de entrada de novo.
func focus_if_needed() -> void:
	if is_menu_active() and not _has_focus_inside():
		focus_initial()
