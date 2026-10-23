## ClickMoveGesture - traduz o botão do mouse do esquema de clique em intenção de movimento.
##
## Recebe só três coisas — apertou, soltou e "o tempo passou" — sempre com o instante informado por
## quem chama, e devolve um Command dizendo o que o personagem deve fazer. Não conhece o Player, a
## cena nem o Input: quem chama (Player._unhandled_input e Player._update_click_gesture) é quem lê o
## mouse e decide para onde ir.
##
## AS QUATRO REGRAS DO ESQUEMA DE CLIQUE
##
##   1. Um clique ANDA até o ponto clicado.
##   2. Dois cliques rápidos no mesmo lugar CORREM até lá.
##   3. Segurar em vez de clicar faz o personagem ACOMPANHAR o mouse, andando.
##   4. Segurar o segundo clique de um clique duplo acompanha o mouse CORRENDO.
##
## COMO USAR:
##
##     var gesture: ClickMoveGesture = ClickMoveGesture.new()
##     match gesture.press(now, mouse_screen_position):
##         ClickMoveGesture.Command.GO_TO: ...           # anda/corre até o mouse (gesture.is_running)
##     match gesture.update(now, Input.is_action_pressed(&"move_click")):
##         ClickMoveGesture.Command.START_FOLLOW: ...    # passa a acompanhar o mouse
##         ClickMoveGesture.Command.CANCEL_FOLLOW: ...   # parou de segurar sem o soltar chegar
##     match gesture.release(now):
##         ClickMoveGesture.Command.STOP_FOLLOW: ...     # soltou depois de segurar
##
## POR QUE É UMA CLASSE SEPARADA: a parte difícil de acertar aqui é o TEMPO (quanto é "segurar",
## quanto é "rápido"), e testar tempo passando por input de verdade é lento e frágil. Como o instante
## entra por parâmetro, o PlayerMovementSelfTest encena qualquer sequência de cliques em
## microssegundos, sem esperar relógio nenhum.
class_name ClickMoveGesture
extends RefCounted

## Espaço para enums

# O que o personagem deve fazer em resposta ao que acabou de acontecer com o botão.
#   NONE          nada muda.
#   GO_TO         ir até onde o mouse está agora (andando ou correndo, ver is_running).
#   START_FOLLOW  o botão foi segurado: passar a acompanhar o mouse enquanto ele estiver apertado.
#   STOP_FOLLOW   o botão foi solto depois de segurado: parar de acompanhar, terminando no mouse.
#   CANCEL_FOLLOW o botão subiu depois de segurado, mas o evento de soltar nunca chegou (jogo pausado,
#                 janela sem foco, soltou em cima de um menu): parar de acompanhar SEM ir até o mouse,
#                 que a essa altura pode estar em cima de um botão da interface — o "Continuar" do menu
#                 de pausa, por exemplo — e não num lugar do mundo escolhido pelo jogador.
enum Command { NONE, GO_TO, START_FOLLOW, STOP_FOLLOW, CANCEL_FOLLOW }

## Espaço para variáveis

# Os três números abaixo são balanceamento, mas esta classe não é um Node e não aparece no
# Inspector: quem os expõe com @export é o Player, que copia os valores para cá (ver
# Player._configure_click_gesture). Os padrões daqui só valem para quem usar a classe sozinha.

# Quanto tempo o botão precisa ficar apertado para deixar de ser clique e virar "segurar".
var hold_seconds: float = 0.25

# Intervalo máximo entre dois cliques para eles contarem como clique duplo.
var double_click_seconds: float = 0.4

# Distância máxima, em pixels de TELA, entre os dois cliques de um clique duplo. É medida na tela, e
# não no mundo, de propósito: a câmera segue o personagem, então o mesmo ponto da tela aponta pra
# lugares diferentes do mundo entre um clique e outro — o que importa é a mão do jogador não ter
# saído do lugar. A unidade é a da posição do evento de mouse no viewport: pixels da resolução base
# do projeto (1920x1080), então o limite vale o mesmo em janela pequena ou tela cheia.
var double_click_distance: float = 24.0

# Verdadeiro quando o gesto em andamento (o clique atual, ou o segurar atual) é de corrida. Continua
# valendo depois de o botão ser solto, até o próximo press(): é o que o Player consulta para saber a
# velocidade do trajeto que acabou de ser pedido.
var is_running: bool = false

# Verdadeiro enquanto o personagem deve acompanhar o mouse (regras 3 e 4).
var is_following: bool = false

var _is_pressed: bool = false
var _press_time: float = 0.0

# Último clique CURTO (que não virou segurar): é a primeira metade candidata de um clique duplo.
var _has_previous_click: bool = false
var _previous_click_time: float = 0.0
var _previous_click_position: Vector2 = Vector2.ZERO

## Espaço para funções personalizadas

# Registra o botão sendo apertado. Sempre devolve GO_TO: o personagem sai andando no mesmo instante,
# sem esperar para descobrir se vem um segundo clique ou se o botão vai ser segurado — esperar
# deixaria todo clique simples com um atraso perceptível. Se vier o segundo clique, ele só troca a
# caminhada em andamento por corrida; se o botão for segurado, update() troca o destino por "seguir".
func press(time: float, screen_position: Vector2) -> Command:
	var is_double_click: bool = _has_previous_click \
		and time - _previous_click_time <= double_click_seconds \
		and screen_position.distance_to(_previous_click_position) <= double_click_distance

	_is_pressed = true
	_press_time = time
	is_running = is_double_click
	is_following = false

	# Não zera nada depois de um clique duplo: um terceiro clique rápido no mesmo lugar forma par com
	# o segundo e continua correndo. Zerar faria quem clica repetidas vezes alternar corre/anda/corre.
	_has_previous_click = true
	_previous_click_time = time
	_previous_click_position = screen_position
	return Command.GO_TO


# Avança o tempo com o botão no estado informado. Chamado a cada frame de física pelo Player.
#
# is_button_down é o estado real do botão, lido do Input, e serve de rede de segurança: se o evento
# de soltar se perder (a janela perdeu o foco, o jogo pausou, ou o botão foi solto em cima de um menu
# que engoliu o evento), o personagem não fica seguindo o mouse para sempre. Nesse caso a resposta é
# CANCEL_FOLLOW, e não STOP_FOLLOW: ninguém soltou o botão num ponto do mundo pra ele ir até lá.
func update(time: float, is_button_down: bool) -> Command:
	if not _is_pressed:
		return Command.NONE

	if not is_button_down:
		var was_following: bool = is_following
		release(time)
		return Command.CANCEL_FOLLOW if was_following else Command.NONE

	if is_following or time - _press_time < hold_seconds:
		return Command.NONE

	is_following = true
	# Um botão segurado não pode ser a primeira metade de um clique duplo: soltar e clicar logo em
	# seguida seria lido como "clique duplo" e correria sem o jogador ter pedido.
	_has_previous_click = false
	return Command.START_FOLLOW


# Registra o botão sendo solto. Só interessa se ele estava sendo segurado; soltar um clique curto
# não muda nada, porque o destino já foi pedido no press().
func release(_time: float) -> Command:
	if not _is_pressed:
		return Command.NONE

	_is_pressed = false
	if not is_following:
		return Command.NONE

	is_following = false
	return Command.STOP_FOLLOW


# Esquece tudo: o gesto em andamento e o clique anterior. Usado quando o movimento é interrompido
# por fora (conversa começou, troca de esquema de movimento), para que o próximo clique comece do
# zero em vez de completar um clique duplo ou retomar um "segurar" de antes da interrupção.
func reset() -> void:
	_is_pressed = false
	_press_time = 0.0
	is_running = false
	is_following = false
	_has_previous_click = false
	_previous_click_time = 0.0
	_previous_click_position = Vector2.ZERO


# Diz se o botão está registrado como apertado. O Player usa para só repassar ao gesto o soltar de
# um press que ele mesmo viu (um press consumido pela interface nunca chega aqui).
func is_pressed() -> bool:
	return _is_pressed
