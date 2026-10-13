## FocusTargets - o contrato de "coisa do mundo que o teclado/controle pode focar e acionar".
##
## O foco de teclado/controle (o anel do InsightInteractor, que segue o alvo mais perto do jogador e
## é acionado pelo A ou pelo E) percorre os orbes de insight E todo nó que estiver no grupo GROUP e
## cumprir o contrato abaixo. É assim que NPCs e objetos interagíveis entraram no controle sem o
## InsightInteractor saber o que é um NPC.
##
## PARA UMA COISA NOVA DO MUNDO FUNCIONAR NO CONTROLE (uma porta, um baú), é só:
##
##     1. add_to_group(FocusTargets.GROUP) no _ready()
##     2. escrever os seis métodos do contrato:
##
##        get_focus_world_position() -> Vector2  posição no mundo, para "mais perto do jogador"
##        get_focus_screen_rect() -> Rect2       retângulo na tela, para "está na tela"
##        can_be_focused() -> bool               dá para acionar AGORA (mesma regra do clique)
##        set_focused(focused: bool) -> void     acende/apaga o destaque de foco
##        activate_focus(player: Player) -> void faz o que o clique faria
##        set_mouse_hover_suppressed(suppressed: bool) -> void
##                                               no modo teclado/controle o hover do mouse não
##                                               destaca nada (o foco é o único destaque)
##
## O autoteste do controle (ControllerSupportSelfTest) varre os scripts e falha se algum que entra no
## grupo não tiver os seis métodos.
##
## Classe só de constantes e funções estáticas: não é Autoload nem nó.
##
## O guia completo está em docs/suporte_a_controle.md.
class_name FocusTargets
extends RefCounted

## Espaço para constantes

# Grupo de quem cumpre o contrato.
const GROUP: StringName = &"focus_targets"

# Os métodos do contrato, na ordem do cabeçalho. Usado pela checagem e pelo autoteste.
const REQUIRED_METHODS: Array[StringName] = [
	&"get_focus_world_position",
	&"get_focus_screen_rect",
	&"can_be_focused",
	&"set_focused",
	&"activate_focus",
	&"set_mouse_hover_suppressed",
]

## Espaço para funções personalizadas

# Os métodos do contrato que o nó NÃO tem (vazio = cumpre o contrato).
static func missing_methods(node: Object) -> Array[StringName]:
	var missing: Array[StringName] = []
	for method: StringName in REQUIRED_METHODS:
		if not node.has_method(method):
			missing.append(method)
	return missing


# Os alvos que dá para focar agora e que aparecem na tela (pelo menos em parte).
static func collect_on_screen(tree: SceneTree, screen_rect: Rect2) -> Array[Node]:
	var targets: Array[Node] = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.is_queued_for_deletion() or not missing_methods(node).is_empty():
			continue
		if not node.call(&"can_be_focused"):
			continue
		var rect: Rect2 = node.call(&"get_focus_screen_rect")
		if screen_rect.intersects(rect):
			targets.append(node)
	return targets
