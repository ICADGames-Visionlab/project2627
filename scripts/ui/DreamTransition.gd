## DreamTransition - A passagem entre o mundo acordado e o mundo dos sonhos: a tela ondula, apodrece
## em vermelho e é engolida por uma vinheta que pulsa até o preto. O mundo troca por trás, no
## escuro, e a tela abre de novo.
##
## COMO USAR: instancie DreamTransition.tscn uma vez na cena de jogo. Quem quer atravessar (a cama)
## acha o nó pelo grupo e passa o que deve acontecer no escuro:
##
##     var transition: DreamTransition = get_tree().get_first_node_in_group(DreamTransition.GROUP)
##     await transition.play(GameClock.enter_dream)
##
## O visual mora em shaders/dream_transition.gdshader — cor, ondulação e pulso são uniforms do
## material, ajustáveis no Inspector. Aqui ficam só os tempos.
##
## O JOGO PAUSA durante a passagem inteira: sem isso o jogador sairia andando da cama com a tela
## preta, e os NPCs seriam vistos teleportando no meio do fechamento. Este nó roda com
## PROCESS_MODE_ALWAYS justamente para continuar animando com a árvore pausada.
class_name DreamTransition
extends CanvasLayer

## Espaço para constantes

const GROUP: StringName = &"dream_transition"

## Espaço para variáveis exportadas

## Quanto tempo a tela leva para fechar no preto.
@export var close_duration: float = 1.8

## Quanto tempo a tela fica preta depois que o mundo trocou. Um respiro: sem ele a abertura
## começa no mesmo frame da troca e a passagem parece um corte.
@export var hold_duration: float = 0.6

## Quanto tempo a tela leva para abrir de novo.
@export var open_duration: float = 1.4

## Espaço para variáveis

var _material: ShaderMaterial

## Espaço para variáveis onready

@onready var _effect: ColorRect = $Effect

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = _effect.material as ShaderMaterial
	# Escondido fora da transição: o efeito relê a tela inteira a cada frame, e não há motivo para
	# pagar isso com progress em zero.
	_effect.hide()

## Espaço para funções personalizadas

# Fecha a tela, chama midpoint no escuro e abre de novo. Termina quando a tela está aberta, então
# quem chama pode dar await e seguir como se nada tivesse acontecido.
func play(midpoint: Callable) -> void:
	print("[DreamTransition] - Fechando a tela")
	# A mesma flag das trocas de cena: é ela que impede o menu de pausa de abrir (e depois soltar
	# a pausa) no meio da passagem.
	GameManager.in_transition = true
	get_tree().paused = true
	_set_progress(0.0)
	_effect.show()

	await _tween_progress(1.0, close_duration)
	midpoint.call()
	await get_tree().create_timer(hold_duration, true).timeout
	await _tween_progress(0.0, open_duration)

	_effect.hide()
	get_tree().paused = false
	GameManager.in_transition = false
	print("[DreamTransition] - Tela aberta")


# Anima o progress do shader até target e espera terminar.
func _tween_progress(target: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_method(_set_progress, _material.get_shader_parameter(&"progress"), target, duration)
	await tween.finished


func _set_progress(value: float) -> void:
	_material.set_shader_parameter(&"progress", value)
