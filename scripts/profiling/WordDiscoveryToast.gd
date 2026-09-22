## WordDiscoveryToast - o aviso de palavra nova: a palavra desce pro canto da tela, na direção do
## diário, e do lado aparece "Palavra adicionada ao Glossário do Zé".
##
## COMO USAR: instancie WordDiscoveryToast.tscn uma vez na cena de jogo. Nada a configurar — ele
## escuta EventBus.glossary_word_discovered e se cuida. Quem descobre a palavra (o texto clicável, o
## inventário quando existir, o menu de debug) não conhece esta cena.
##
## O layout está na cena: o canto, a mensagem e o retângulo do diário. A palavra que voa é a cena
## apontada em "Flying Word Scene" (FlyingWord.tscn) — fonte e contorno dela se mexem lá, não aqui.
##
## PLACEHOLDER: o "asset pequeno do diário" que o GDD pede no canto inferior direito é um retângulo
## identificado. O DIÁRIO NÃO EXISTE AINDA (ver docs/sistema_de_profiling.md, "O que ainda não
## existe"): quando existir, o retângulo daqui vira o ícone dele, e o destino da animação continua
## sendo o mesmo canto.
##
## Duas palavras descobertas juntas ([MARCOS]/[CASTRO]) geram DOIS avisos, porque são duas palavras —
## o texto do aviso é o da última, e as duas animações acontecem ao mesmo tempo.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name WordDiscoveryToast
extends CanvasLayer

## Espaço para variáveis exportadas

## Quanto tempo a palavra leva pra descer até o canto, em segundos.
@export var travel_seconds: float = 0.8

## Quanto tempo a mensagem fica na tela depois de a palavra chegar, em segundos.
@export var message_seconds: float = 1.8

## A cena da palavra que desce pro canto (FlyingWord.tscn).
@export var flying_word_scene: PackedScene

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _message: Label = $Root/Corner/Message
@onready var _diary_icon: Panel = $Root/Corner/DiaryIcon

## Espaço para funções nativas

func _ready() -> void:
	# O aviso aparece sobre telas que pausam o jogo (o glossário dentro do sonho), então ele precisa
	# continuar animando com a árvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.glossary_word_discovered.connect(_on_glossary_word_discovered)
	_message.hide()

## Espaço para funções personalizadas

# Mostra o aviso de uma palavra nova: a palavra voando e a mensagem no canto.
func show_word(npc_id: StringName, word_id: StringName) -> void:
	var word: GlossaryWord = ProfilingCatalog.find_word(word_id)
	if word == null:
		return

	_fly_word(word)
	# replace(), e não o operador %: se alguém esquecer a chave no CSV, tr() devolve a própria chave
	# (que não tem "%s") e o operador % viraria erro em tempo de execução no meio do jogo.
	_message.text = tr("PROFILING_WORD_ADDED").replace("%s", _get_npc_name(npc_id))
	_message.show()
	# Cada palavra nova reinicia a contagem: com duas palavras seguidas, a mensagem da segunda não
	# pode ser apagada pelo timer da primeira.
	var timer: SceneTreeTimer = get_tree().create_timer(travel_seconds + message_seconds, true)
	timer.timeout.connect(_on_message_timeout.bind(_message.text))


# A palavra descendo pra o canto do diário. Ela nasce onde o mouse está: é lá que o jogador acabou de
# clicar, então a animação sai da própria palavra que ele colheu.
func _fly_word(word: GlossaryWord) -> void:
	if flying_word_scene == null:
		push_error("[Profiling] - Aviso de palavra sem \"Flying Word Scene\" apontada")
		return

	var flying: Label = flying_word_scene.instantiate() as Label
	if flying == null:
		push_error("[Profiling] - A cena da palavra que voa não é um Label")
		return
	flying.text = word.get_display_text()
	# modulate, e não override de fonte: a cor é a da CATEGORIA da palavra (dado), e a fonte e o
	# contorno continuam sendo os da cena.
	flying.modulate = word.get_color()
	_root.add_child(flying)
	# reset_size() antes de ler o tamanho: o Label só ganha tamanho no próximo layout, e sem isto o
	# destino sairia deslocado meio retângulo.
	flying.reset_size()
	flying.position = _root.get_local_mouse_position()

	var corner: Vector2 = _diary_icon.get_global_rect().get_center()
	var destination: Vector2 = corner - _root.global_position - flying.size * 0.5

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	var move: PropertyTweener = tween.tween_property(flying, "position", destination, travel_seconds)
	move.set_ease(Tween.EASE_IN)
	move.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(flying, "modulate:a", 0.0, travel_seconds).set_delay(travel_seconds * 0.5)
	# set_parallel(false) fecha o grupo paralelo: a liberação do nó é um passo DEPOIS das duas
	# animações, e não junto com elas.
	tween.set_parallel(false)
	tween.tween_callback(flying.queue_free)


# Esconde a mensagem, mas só se ela ainda for a mesma: uma palavra descoberta no meio da contagem
# escreve uma mensagem nova, e o timer antigo não pode apagá-la.
func _on_message_timeout(expected_text: String) -> void:
	if _message.text == expected_text:
		_message.hide()


# O nome do NPC de quem é o glossário. Vem do roster, com o id como último recurso.
func _get_npc_name(npc_id: StringName) -> String:
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director != null and director.roster != null:
		var definition: NPCDefinition = director.roster.find(npc_id)
		if definition != null:
			return definition.get_display_name()
	return String(npc_id)


func _on_glossary_word_discovered(npc_id: StringName, word_id: StringName) -> void:
	show_word(npc_id, word_id)
