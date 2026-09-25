## ProfilingScreen - a tela do espírito de um NPC no mundo dos sonhos: escolher a emoção dele e
## investigar a história de cada emoção.
##
## COMO USAR: instancie ProfilingScreen.tscn uma vez na cena de jogo. Nada a configurar. Quem quer
## abrir o espírito de alguém pede pelo EventBus, sem conhecer esta cena:
##
##     EventBus.profiling_requested.emit(&"ze")
##
## AS DUAS TELAS, como no GDD:
##
##   ESPÍRITO  a arte do espírito do NPC cobrindo a tela inteira (NPCDefinition.spirit_art, 1920x1080),
##             com o nome e as emoções por cima. Segurar o botão esquerdo em
##             cima de uma emoção troca a emoção do NPC (a partir do dia seguinte); passar o mouse
##             mostra o INVESTIGAR, que abre a história dela. "Sair" no canto inferior direito volta
##             pro sonho, e o jogador pode procurar outro espírito.
##   HISTÓRIA  metade esquerda: a página com lacunas e o glossário embaixo; metade direita: a arte do
##             NPC, sem moldura. A seta no canto inferior esquerdo volta pra tela de emoções.
##
## O ACERTO: a página vira a história completa na hora, sem a seta de voltar — o jogador lê e clica
## (ou aperta Enter/ESC) pra continuar, e volta pra tela de emoções. Quando esse acerto completou
## TODAS as emoções do NPC, a tela de emoções é a última parada: dali, sair é ACORDAR (o GDD:
## entender o NPC inteiro fecha o sonho), e ele ainda pode escolher a emoção antes.
##
## O LAYOUT É LIVRE: as peças da cena são soltas (âncoras), e não presas em contêineres — dá pra
## arrastar cada uma no editor, inclusive as opções de emoção (filhas do nó Emotions, que recebem as
## emoções do NPC na ordem). O script acha os nós pelo nome único (%), então mudar um nó de pai
## também não quebra nada.
##
## O QUE ESTA TELA NÃO FAZ, porque os sistemas ainda não existem:
##
##   MÚSICA  o GDD pede uma música curta no acerto da história. Não há música no projeto; o ponto
##           exato onde ela tocaria está marcado em _reveal_solved(), com o comentário "MÚSICA".
##   DIÁRIO  a história resolvida deveria entrar no diário do jogador. O diário não existe; o gancho
##           dele é ProfilingJournal.mark_story_solved, que é por onde todo acerto passa.
##   DIÁLOGO a história completa deveria ser NARRADA pelo NPC (o GDD sugere até uma animatic). Hoje
##           ela aparece como texto na própria página; ver _reveal_solved().
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingScreen
extends CanvasLayer

## Espaço para enums

# Qual das duas telas está na frente.
enum View { SPIRIT, STORY }

## Espaço para constantes

# Grupo em que esta tela se registra, pra quem precisar dela (menu de debug, testes) não depender de
# NodePath.
const GROUP: StringName = &"profiling_screen"

## Espaço para variáveis exportadas

## Tremor da tela enquanto o jogador segura uma emoção, em pixels no auge do gesto. A arte do
## espírito e o filtro de cor passam 24 px de cada borda da tela (offsets na cena) pra a borda não
## aparecer tremendo: se este valor passar de 24, aumente essa sobra junto.
@export var shake_strength: float = 12.0

## Opacidade do filtro de cor da emoção vigente, sempre presente na tela do espírito.
@export var filter_base_alpha: float = 0.10

## Opacidade do filtro no auge do gesto de segurar uma emoção.
@export var filter_hold_alpha: float = 0.38

## Período do pisca-pisca da seta de voltar numa história resolvida (e do "clique para continuar"
## logo depois do acerto), em segundos.
@export var blink_period: float = 0.8

## Espaço para variáveis

var _npc_id: StringName = &""
var _profile: NPCProfile
var _definition: NPCDefinition
var _story: ProfilingStory
var _view: View = View.SPIRIT
# Verdadeiro entre o acerto da página e a troca dela pela história completa (que é adiada pro fim do
# quadro). Segura o pedido de revelar pra ele não acontecer duas vezes.
var _is_revealing: bool = false
# A história acabou de ser resolvida e está na tela pela primeira vez: sem seta de voltar, e
# qualquer clique continua pra tela de emoções.
var _awaiting_continue: bool = false
# O jogador acertou a última emoção deste NPC: sair do espírito agora é acordar.
var _wake_pending: bool = false
var _blink_time: float = 0.0

## Espaço para variáveis onready

@onready var _root: Control = %Root
@onready var _filter: ColorRect = %EmotionFilter
@onready var _shake: Control = %Shake
@onready var _spirit_view: Control = %SpiritView
@onready var _spirit_name: Label = %SpiritName
# A arte do espírito fica DENTRO do "Shake" (treme junto com a tela) e ABAIXO do filtro de cor, que
# a tinge. Ela sobra um pouco além das bordas da tela, pra a borda não aparecer no tremor.
@onready var _spirit_art: TextureRect = %SpiritArt
@onready var _spirit_caption: Label = %SpiritCaption
# As opções de emoção já estão NA CENA, como filhos deste nó, e cada uma fica onde foi posta no
# editor: a 1ª recebe a primeira emoção do NPC, a 2ª a segunda (ver _refresh_spirit_view).
@onready var _emotions: Control = %Emotions
@onready var _exit_button: Button = %ExitButton
@onready var _story_view: Control = %StoryView
@onready var _page: ProfilingPage = %Page
@onready var _glossary: GlossaryPanel = %Glossary
@onready var _story_name: Label = %StoryName
@onready var _story_portrait: TextureRect = %StoryPortrait
@onready var _story_caption: Label = %StoryCaption
@onready var _back_button: Button = %BackButton
@onready var _continue_hint: Control = %ContinueHint
# O retângulo de marcas fica FORA do "Shake" e por cima de tudo: ele se posiciona em coordenadas de
# tela (acima da palavra clicada), e tremer com a tela o descolaria da palavra.
@onready var _mark_menu: GlossaryMarkMenu = %MarkMenu

## Espaço para funções nativas

func _ready() -> void:
	add_to_group(GROUP)
	# A tela para o jogo, então ela precisa continuar processando enquanto ele está pausado — senão
	# nenhum botão responde e o jogador fica preso no sonho.
	process_mode = Node.PROCESS_MODE_ALWAYS

	EventBus.profiling_requested.connect(_on_profiling_requested)
	EventBus.npc_profiling_completed.connect(_on_npc_profiling_completed)
	# A escolha de emoção não é escutada pelo evento do bus: ela muda o diário, e journal_changed já
	# traz a tela de volta. Escutar os dois redesenharia a tela duas vezes no mesmo quadro.
	ProfilingJournal.journal_changed.connect(_on_journal_changed)

	_exit_button.pressed.connect(close)
	_back_button.pressed.connect(show_spirit_view)
	_story_view.gui_input.connect(_on_story_view_gui_input)
	_page.evaluated.connect(_on_page_evaluated)
	_glossary.word_activated.connect(_on_glossary_word_activated)
	_glossary.mark_menu_requested.connect(_on_glossary_mark_menu_requested)
	_glossary.word_returned.connect(_on_glossary_word_returned)
	_mark_menu.mark_chosen.connect(_on_mark_chosen)
	for option: ProfilingEmotionOption in _get_emotion_options():
		option.hold_changed.connect(_on_option_hold_changed)
		option.hold_completed.connect(_on_option_hold_completed)
		option.investigate_requested.connect(show_story_view)

	_root.hide()
	set_process(false)


func _process(delta: float) -> void:
	# Só roda pelo pisca-pisca: da seta, numa história já resolvida ("a seta para voltar para a tela
	# de selecionar emoções fica piscando", GDD), ou do "clique para continuar" logo depois do acerto.
	_blink_time += delta
	var wave: float = 0.55 + 0.45 * sin(_blink_time * TAU / maxf(blink_period, 0.05))
	var target: CanvasItem = _continue_hint if _awaiting_continue else _back_button
	target.modulate = Color(1.0, 1.0, 1.0, wave)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if _awaiting_continue and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		show_spirit_view()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return

	get_viewport().set_input_as_handled()
	# Cancelar volta um passo, e não fecha tudo de uma vez: sair da história é voltar pras emoções.
	if _view == View.STORY:
		show_spirit_view()
	else:
		close()

## Espaço para funções personalizadas

# Abre o espírito de um NPC. NPC sem perfil não abre nada e avisa: espírito sem história é conteúdo
# faltando, não um estado de jogo.
func open(npc_id: StringName) -> void:
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile == null:
		push_warning("[Profiling] - AVISO: \"%s\" não tem perfil de profiling" % npc_id)
		return

	_npc_id = npc_id
	_profile = profile
	_definition = _find_definition(npc_id)
	_wake_pending = false
	_is_revealing = false

	_root.show()
	get_tree().paused = true
	show_spirit_view()

	print("[Profiling] - Espírito de \"%s\" aberto (%d/%d histórias resolvidas)" % [
		npc_id, ProfilingJournal.count_solved_stories(npc_id), _profile.get_story_count()])
	EventBus.profiling_opened.emit(npc_id)


# Fecha a tela e devolve o jogador ao sonho. Se o último acerto completou o NPC, fechar é acordar —
# o jogador não volta pro sonho depois de entender alguém por inteiro.
func close() -> void:
	if not _root.visible:
		return

	if _wake_pending:
		_wake_up()
		return

	var closed_id: StringName = _npc_id
	_mark_menu.close()
	_root.hide()
	set_process(false)
	get_tree().paused = false
	_story = null
	_npc_id = &""
	print("[Profiling] - Espírito de \"%s\" fechado" % closed_id)
	EventBus.profiling_closed.emit(closed_id)


# Mostra a tela de escolher emoção, montando uma opção por emoção do NPC.
func show_spirit_view() -> void:
	_mark_menu.close()
	_view = View.SPIRIT
	_story = null
	_is_revealing = false
	_awaiting_continue = false
	_spirit_view.show()
	_story_view.hide()
	set_process(false)
	_back_button.modulate = Color.WHITE
	_back_button.show()
	_continue_hint.hide()
	_refresh_spirit_view()


# Abre a história de uma emoção. É o que o botão INVESTIGAR do GDD faz.
func show_story_view(slot: int) -> void:
	var emotion: EmotionDefinition = _get_emotion(slot)
	var story: ProfilingStory = _profile.find_story_for_emotion(emotion)
	if story == null:
		print("[Profiling] - \"%s\" não tem história escrita para a emoção do slot %d" % [_npc_id, slot])
		return

	_view = View.STORY
	_story = story
	_is_revealing = false
	_spirit_view.hide()
	_spirit_art.hide()
	_story_view.show()

	_story_name.text = _get_npc_name()
	_apply_art(_story_portrait, _story_caption,
		_definition.portrait if _definition != null else null, "PLACEHOLDER_NPC_PORTRAIT")
	_page.configure(_profile, story)
	_glossary.configure(_npc_id, story)
	# O glossário sai da tela nas histórias já resolvidas: não há mais lacuna pra preencher, e é o
	# "o glossário some" do GDD.
	_glossary.visible = not ProfilingJournal.is_story_solved(story.id)
	set_process(ProfilingJournal.is_story_solved(story.id))

	print("[Profiling] - História \"%s\" aberta (emoção \"%s\")" % [
		story.id, emotion.id if emotion != null else "?"])


# Redesenha a tela de emoções: cada emoção do NPC vai pra uma das opções que estão na cena, na ordem
# dos filhos do nó Emotions (a 1ª opção recebe a primeira emoção, a 2ª a segunda). As opções não são
# criadas aqui: estão na cena pra poderem ser posicionadas à mão, cada uma num canto da arte.
#
# As emoções vêm do NPCDefinition, não de uma lista fixa de três como no GDD: o projeto usa emoções
# modulares em slots (ver EmotionDefinition). No dia em que um NPC tiver um terceiro slot, basta
# duplicar uma opção na cena. Opção sobrando (NPC com menos emoções) fica escondida.
func _refresh_spirit_view() -> void:
	_spirit_name.text = _get_npc_name()
	_apply_art(_spirit_art, _spirit_caption,
		_definition.spirit_art if _definition != null else null, "PLACEHOLDER_NPC_SPIRIT_ART")

	var current_slot: int = _get_current_slot()
	var scheduled_slot: int = ProfilingJournal.get_scheduled_slot(_npc_id)
	var options: Array[ProfilingEmotionOption] = _get_emotion_options()
	var used: int = 0

	for slot: int in NPCDefinition.EmotionSlot.values():
		var emotion: EmotionDefinition = _get_emotion(slot)
		if emotion == null:
			# O neutro não é uma emoção do catálogo: é a ausência de emoção vigente, e não tem
			# história por trás nem pode ser escolhido no sonho.
			continue
		if used >= options.size():
			push_warning(("[Profiling] - AVISO: \"%s\" tem mais emoções do que opções no nó "
				+ "Emotions da ProfilingScreen.tscn; duplique uma opção lá") % _npc_id)
			break

		var story: ProfilingStory = _profile.find_story_for_emotion(emotion)
		var option: ProfilingEmotionOption = options[used]
		option.show()
		option.configure(emotion, slot, slot == current_slot, slot == scheduled_slot,
			story != null and ProfilingJournal.is_story_solved(story.id), story != null)
		used += 1

	for index: int in range(used, options.size()):
		options[index].hide()

	_apply_base_filter()


# As opções de emoção da cena, na ordem dos filhos do nó Emotions.
func _get_emotion_options() -> Array[ProfilingEmotionOption]:
	var options: Array[ProfilingEmotionOption] = []
	for child: Node in _emotions.get_children():
		var option: ProfilingEmotionOption = child as ProfilingEmotionOption
		if option != null:
			options.append(option)
	return options


# A revelação do acerto: a página dá lugar à história contada por inteiro NA HORA, o glossário sai e
# a seta de voltar também — no lugar dela, o "clique para continuar", que leva à tela de emoções.
func _reveal_solved() -> void:
	_is_revealing = false
	# A tela pode ter sido fechada (ou trocado de história) antes do fim do quadro.
	if not _root.visible or _story == null:
		return
	var story: ProfilingStory = _story

	# MÚSICA: é AQUI que a "música curta" do GDD tocaria, no instante do acerto.
	# Não há música no projeto ainda (ver docs/AudioManager.md); quando houver, é uma linha:
	#     AudioManager.play_sfx(...)
	print("[Profiling] - Acerto da história \"%s\" (música do acerto: pendente)" % story.id)

	# DIÁRIO: marcar é o funil de todo acerto, e é lá (ProfilingJournal.mark_story_solved) que o
	# diário do jogador vai se pendurar quando existir — ele guarda ProfilingStory.journal_entry_key.
	# DIÁLOGO: o GDD quer a história NARRADA pelo NPC. Enquanto a tela de diálogo não existe, ela
	# aparece como texto na própria página — trocar isso é trocar a linha abaixo por um pedido de fala.
	ProfilingJournal.mark_story_solved(_npc_id, story.id)

	_page.show_resolved()
	_glossary.hide()
	_back_button.hide()
	_continue_hint.show()
	_awaiting_continue = true
	_blink_time = 0.0
	set_process(true)


# Acorda o jogador, com a mesma passagem que a cama usa. Fora do sonho (a tela aberta pelo menu de
# debug no mundo acordado), só fecha: acordar quem não está dormindo pularia um dia de graça.
func _wake_up() -> void:
	var closed_id: StringName = _npc_id
	_wake_pending = false
	_root.hide()
	set_process(false)
	get_tree().paused = false
	_story = null
	_npc_id = &""
	EventBus.profiling_closed.emit(closed_id)

	if not GameClock.is_dreaming():
		print("[Profiling] - Profiling de \"%s\" completo fora do sonho: nada a acordar" % closed_id)
		return

	print("[Profiling] - Jogador acordou por ter entendido \"%s\" por inteiro" % closed_id)
	var transition: DreamTransition = get_tree().get_first_node_in_group(
		DreamTransition.GROUP) as DreamTransition
	if transition == null:
		push_warning("[Profiling] - AVISO: nenhuma DreamTransition na cena, acordando sem transição")
		GameClock.start_next_day()
		return
	await transition.play(GameClock.start_next_day)


# Põe o filtro na cor da emoção que vale: a que o jogador já escolheu neste sonho, se houver,
# senão a que o NPC está sentindo hoje. É o estado de repouso da tela do espírito, e é onde ela
# volta quando um gesto de segurar é cancelado.
func _apply_base_filter() -> void:
	var scheduled_slot: int = ProfilingJournal.get_scheduled_slot(_npc_id)
	var slot: int = scheduled_slot if scheduled_slot >= 0 else _get_current_slot()
	_apply_filter(_get_emotion(slot), 0.0)


# Pinta o filtro de cor da tela com a cor da emoção. É o "filtro relacionado a emoção" do GDD, e a
# cor vem de EmotionDefinition.tint — não há cor de emoção escrita nesta tela.
func _apply_filter(emotion: EmotionDefinition, hold_progress: float) -> void:
	var tint: Color = emotion.tint if emotion != null else Color.WHITE
	tint.a = lerpf(filter_base_alpha, filter_hold_alpha, hold_progress)
	_filter.color = tint


# PLACEHOLDER: põe uma arte do NPC (o retrato ou a arte do espírito), ou o aviso de placeholder com
# o nome dele quando a arte não existe.
#
# As artes vêm do NPCDefinition, e não do perfil de profiling: são a cara do NPC, e o diário e a
# tela de diálogo vão mostrar as mesmas imagens.
func _apply_art(image: TextureRect, caption: Label, art: Texture2D, placeholder_key: String) -> void:
	image.texture = art
	image.visible = art != null
	caption.visible = art == null
	if art == null:
		caption.text = "%s\n%s" % [tr(placeholder_key), _get_npc_name()]


# A emoção de um slot do NPC, ou null (o caso do neutro e do slot que o design deixou vazio).
func _get_emotion(slot: int) -> EmotionDefinition:
	if _definition == null or slot < 0:
		return null
	return _definition.get_emotion(slot)


# A emoção vigente do NPC hoje. O dono dessa informação é o NPCDirector, que a aplica na cidade;
# sem diretor na cena (um teste, ou uma cena sem NPCs), o diário responde sozinho.
func _get_current_slot() -> int:
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director != null:
		return director.get_emotion_slot(_npc_id)
	return ProfilingJournal.resolve_emotion_slot(_definition)


# O NPC do roster, ou null. A tela precisa dele pelas emoções e pelo nome; sem ele (perfil de um NPC
# que saiu do roster) a tela abre mostrando só o que o perfil sabe.
func _find_definition(npc_id: StringName) -> NPCDefinition:
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null or director.roster == null:
		push_warning("[Profiling] - AVISO: nenhum NPCDirector na cena; a tela abre sem as emoções")
		return null
	var definition: NPCDefinition = director.roster.find(npc_id)
	if definition == null:
		push_warning("[Profiling] - AVISO: \"%s\" tem perfil de profiling mas não está no roster" % npc_id)
	return definition


# O nome do NPC, traduzido. Cai no id quando o NPC não está no roster, pra a tela nunca ficar sem
# dizer de quem ela é.
func _get_npc_name() -> String:
	if _definition != null:
		return _definition.get_display_name()
	return String(_npc_id)


func _on_profiling_requested(npc_id: StringName) -> void:
	open(npc_id)


# Segurando uma emoção: a tela treme e o filtro vai ganhando a cor dela — os dois proporcionais ao
# quanto falta, que é o que o GDD descreve.
func _on_option_hold_changed(slot: int, progress: float) -> void:
	# PROGRESSO ZERO É CANCELAMENTO (o jogador soltou no meio, ou arrastou o mouse pra fora), e
	# aí a tela volta ao estado de antes: sem tremor e com o filtro da emoção que REALMENTE vale.
	# Sem isto o filtro ficava na cor da emoção que ele desistiu de escolher, dizendo uma coisa
	# que não aconteceu.
	if progress <= 0.0:
		_shake.position = Vector2.ZERO
		_apply_base_filter()
		return

	var jitter: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_shake.position = jitter * shake_strength * progress
	_apply_filter(_get_emotion(slot), progress)


# O retângulo encheu: a emoção do NPC passa a ser esta a partir do dia seguinte. Quem aplica isso na
# cidade é o NPCDirector, na virada de dia (ver ProfilingJournal.resolve_emotion_slot).
func _on_option_hold_completed(slot: int) -> void:
	_shake.position = Vector2.ZERO
	ProfilingJournal.schedule_emotion_slot(_npc_id, slot)


# A correção da página, a cada mudança. Só o acerto de uma história AINDA NÃO RESOLVIDA dispara a
# revelação — reabrir uma história resolvida mostra a mesma página sem tocar música de novo.
#
# A revelação é adiada pro fim do quadro: a correção chega de DENTRO do redesenho da página, e
# revelar ali redesenharia a página no meio do próprio redesenho.
func _on_page_evaluated(evaluation: ProfilingEvaluation) -> void:
	if _story == null or _is_revealing or not evaluation.is_solved():
		return
	if ProfilingJournal.is_story_solved(_story.id):
		return
	_is_revealing = true
	_reveal_solved.call_deferred()


# Clique em qualquer lugar da história logo depois do acerto: continua pra tela de emoções. Chega
# aqui o clique que nenhuma peça da página consumiu (o texto e o papel deixam passar).
func _on_story_view_gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if not _awaiting_continue or mouse_button == null or not mouse_button.pressed \
			or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	_story_view.accept_event()
	show_spirit_view()


func _on_glossary_word_activated(word_id: StringName) -> void:
	# Clicar numa palavra também fecha o retângulo de marcas: o jogador mudou de assunto.
	_mark_menu.close()
	_page.activate_word(word_id)


# A palavra volta pro glossário: o jogador a arrastou de uma lacuna e soltou no glossário, ou soltou
# um arraste em cima de nada. Nos dois casos, se ela estava numa lacuna, a lacuna esvazia.
func _on_glossary_word_returned(word_id: StringName) -> void:
	_page.return_word(word_id)


# Clique direito numa palavra: o retângulo de marcas aparece acima dela. Pedir ao MESMO nó a cada
# clique é o que faz o menu simplesmente MUDAR DE LUGAR quando o jogador clica em outra palavra com
# um já aberto — antes eram menus separados por chip, e o segundo não abria.
func _on_glossary_mark_menu_requested(word_id: StringName, chip_rect: Rect2) -> void:
	_mark_menu.toggle_for(word_id, chip_rect, ProfilingJournal.get_mark(_npc_id, word_id))


# A marca é organização pessoal do jogador: não muda lacuna nem história. Quem grava é a tela, e não
# o painel, porque o painel é reaproveitado pelo diário (que vai ter o retângulo dele).
func _on_mark_chosen(word_id: StringName, kind: GlossaryMark.Kind) -> void:
	ProfilingJournal.set_mark(_npc_id, word_id, kind)


# O diário mudou (palavra nova, lacuna preenchida, marca posta): a tela aberta se redesenha.
func _on_journal_changed() -> void:
	if not _root.visible:
		return
	if _view == View.STORY:
		_page.refresh()
		_glossary.refresh()
	else:
		_refresh_spirit_view()


# O jogador acertou a última emoção deste NPC. Acordar não acontece aqui: ele ainda lê a história,
# continua pra tela de emoções (onde pode escolher a emoção), e acorda ao sair dela (ver close).
func _on_npc_profiling_completed(npc_id: StringName) -> void:
	if npc_id != _npc_id:
		return
	_wake_pending = true
