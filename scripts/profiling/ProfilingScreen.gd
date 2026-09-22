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
##   ESPÍRITO  o portrait do NPC no centro, as emoções dele em volta. Segurar o botão esquerdo em
##             cima de uma emoção troca a emoção do NPC (a partir do dia seguinte); passar o mouse
##             mostra o INVESTIGAR, que abre a história dela. "Sair" no canto inferior direito volta
##             pro sonho, e o jogador pode procurar outro espírito.
##   HISTÓRIA  a página com lacunas, o glossário embaixo e o portrait na direita. A seta no canto
##             inferior esquerdo volta pra tela de emoções.
##
## Acertar TODAS as emoções de um NPC faz o jogador ACORDAR — é o GDD: entender o NPC inteiro fecha
## o sonho. O jogador tem alguns segundos pra ler a história completa antes (wake_delay).
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

## Quanto tempo a mensagem "Tudo foi preenchido corretamente" fica na tela antes de a página ser
## trocada pela história completa, em segundos.
@export var reveal_delay: float = 2.5

## Quanto tempo o jogador tem pra ler a história completa do último acerto antes de acordar, em
## segundos. Só vale quando aquele acerto completou TODAS as emoções do NPC.
@export var wake_delay: float = 6.0

## Tremor da tela enquanto o jogador segura uma emoção, em pixels no auge do gesto.
@export var shake_strength: float = 12.0

## Opacidade do filtro de cor da emoção vigente, sempre presente na tela do espírito.
@export var filter_base_alpha: float = 0.10

## Opacidade do filtro no auge do gesto de segurar uma emoção.
@export var filter_hold_alpha: float = 0.38

## Período do pisca-pisca da seta de voltar depois de uma história resolvida, em segundos.
@export var blink_period: float = 0.8

## Espaço para variáveis

var _npc_id: StringName = &""
var _profile: NPCProfile
var _definition: NPCDefinition
var _story: ProfilingStory
var _view: View = View.SPIRIT
# Verdadeiro entre o acerto da página e a troca dela pela história completa. Segura o pedido de
# revelar pra ele não acontecer duas vezes (o diário muda, a página se redesenha e a correção é
# anunciada de novo no meio da espera).
var _is_revealing: bool = false
# O jogador acertou a última emoção deste NPC: quando a revelação terminar, ele acorda.
var _wake_pending: bool = false
var _blink_time: float = 0.0

## Espaço para variáveis onready

@onready var _root: Control = $Root
@onready var _filter: ColorRect = $Root/EmotionFilter
@onready var _shake: Control = $Root/Shake
@onready var _spirit_view: Control = $Root/Shake/SpiritView
@onready var _spirit_name: Label = $Root/Shake/SpiritView/Center/NpcName
@onready var _spirit_portrait: TextureRect = $Root/Shake/SpiritView/Center/Portrait/Content/Image
@onready var _spirit_caption: Label = $Root/Shake/SpiritView/Center/Portrait/Content/Caption
@onready var _emotions: HBoxContainer = $Root/Shake/SpiritView/Center/Emotions
@onready var _exit_button: Button = $Root/Shake/SpiritView/ExitButton
@onready var _story_view: Control = $Root/Shake/StoryView
@onready var _page: ProfilingPage = $Root/Shake/StoryView/Columns/Left/Page
@onready var _glossary: GlossaryPanel = $Root/Shake/StoryView/Columns/Left/Glossary
@onready var _story_name: Label = $Root/Shake/StoryView/Columns/Right/NpcName
@onready var _story_portrait: TextureRect = $Root/Shake/StoryView/Columns/Right/Portrait/Content/Image
@onready var _story_caption: Label = $Root/Shake/StoryView/Columns/Right/Portrait/Content/Caption
@onready var _back_button: Button = $Root/Shake/StoryView/BackButton

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
	_page.evaluated.connect(_on_page_evaluated)
	_glossary.word_activated.connect(_on_glossary_word_activated)

	_root.hide()
	set_process(false)


func _process(delta: float) -> void:
	# Só roda pelo pisca-pisca da seta: "a seta para voltar para a tela de selecionar emoções fica
	# piscando" (GDD), o aviso de que não há mais nada pra fazer naquela página.
	_blink_time += delta
	var wave: float = 0.55 + 0.45 * sin(_blink_time * TAU / maxf(blink_period, 0.05))
	_back_button.modulate = Color(1.0, 1.0, 1.0, wave)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or not event.is_action_pressed(&"ui_cancel"):
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
	_root.hide()
	set_process(false)
	get_tree().paused = false
	_story = null
	_npc_id = &""
	print("[Profiling] - Espírito de \"%s\" fechado" % closed_id)
	EventBus.profiling_closed.emit(closed_id)


# Mostra a tela de escolher emoção, montando uma opção por emoção do NPC.
func show_spirit_view() -> void:
	_view = View.SPIRIT
	_story = null
	_is_revealing = false
	_spirit_view.show()
	_story_view.hide()
	set_process(false)
	_back_button.modulate = Color.WHITE
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
	_story_view.show()

	_story_name.text = _get_npc_name()
	_apply_portrait(_story_portrait, _story_caption)
	_page.configure(_profile, story)
	_glossary.configure(_npc_id, story)
	# O glossário sai da tela nas histórias já resolvidas: não há mais lacuna pra preencher, e é o
	# "o glossário some" do GDD.
	_glossary.visible = not ProfilingJournal.is_story_solved(story.id)
	set_process(ProfilingJournal.is_story_solved(story.id))

	print("[Profiling] - História \"%s\" aberta (emoção \"%s\")" % [
		story.id, emotion.id if emotion != null else "?"])


# Redesenha a tela de emoções: uma opção por emoção do NPC, com o estado de cada uma.
#
# As emoções vêm do NPCDefinition, não de uma lista fixa de três como no GDD: o projeto usa emoções
# modulares em slots (ver EmotionDefinition), e é por isso que o dia em que um NPC tiver um terceiro
# slot esta tela não muda.
func _refresh_spirit_view() -> void:
	for child: Node in _emotions.get_children():
		child.queue_free()

	_spirit_name.text = _get_npc_name()
	_apply_portrait(_spirit_portrait, _spirit_caption)

	var current_slot: int = _get_current_slot()
	var scheduled_slot: int = ProfilingJournal.get_scheduled_slot(_npc_id)

	for slot: int in NPCDefinition.EmotionSlot.values():
		var emotion: EmotionDefinition = _get_emotion(slot)
		if emotion == null:
			# O neutro não é uma emoção do catálogo: é a ausência de emoção vigente, e não tem
			# história por trás nem pode ser escolhido no sonho.
			continue

		var story: ProfilingStory = _profile.find_story_for_emotion(emotion)
		var option: ProfilingEmotionOption = ProfilingEmotionOption.new()
		_emotions.add_child(option)
		option.configure(emotion, slot, slot == current_slot, slot == scheduled_slot,
			story != null and ProfilingJournal.is_story_solved(story.id), story != null)
		option.hold_changed.connect(_on_option_hold_changed)
		option.hold_completed.connect(_on_option_hold_completed)
		option.investigate_requested.connect(show_story_view)

	_apply_filter(_get_emotion(scheduled_slot if scheduled_slot >= 0 else current_slot), 0.0)


# A revelação do acerto, na ordem do GDD: a mensagem fica alguns segundos, a página some e dá lugar à
# história contada por inteiro, o glossário sai e a seta de voltar começa a piscar.
func _reveal_solved() -> void:
	_is_revealing = true
	var story: ProfilingStory = _story

	# MÚSICA: é AQUI que a "música curta" do GDD tocaria, no instante do acerto, antes da espera.
	# Não há música no projeto ainda (ver docs/AudioManager.md); quando houver, é uma linha:
	#     AudioManager.play_sfx(...)
	print("[Profiling] - Acerto da história \"%s\" (música do acerto: pendente)" % story.id)

	# O timer roda com a árvore pausada porque o jogo está parado enquanto esta tela está aberta.
	await get_tree().create_timer(reveal_delay, true).timeout
	# A tela pode ter sido fechada (ou trocado de história) durante a espera.
	if not _root.visible or _story != story:
		_is_revealing = false
		return

	# DIÁRIO: marcar é o funil de todo acerto, e é lá (ProfilingJournal.mark_story_solved) que o
	# diário do jogador vai se pendurar quando existir — ele guarda ProfilingStory.journal_entry_key.
	# DIÁLOGO: o GDD quer a história NARRADA pelo NPC. Enquanto a tela de diálogo não existe, ela
	# aparece como texto na própria página — trocar isso é trocar a linha abaixo por um pedido de fala.
	ProfilingJournal.mark_story_solved(_npc_id, story.id)

	_page.show_resolved()
	_glossary.hide()
	_blink_time = 0.0
	set_process(true)
	_is_revealing = false

	if _wake_pending:
		# O jogador entendeu o NPC inteiro: ele tem wake_delay pra ler a história e acorda.
		await get_tree().create_timer(wake_delay, true).timeout
		if _root.visible and _wake_pending:
			_wake_up()


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


# Pinta o filtro de cor da tela com a cor da emoção. É o "filtro relacionado a emoção" do GDD, e a
# cor vem de EmotionDefinition.tint — não há cor de emoção escrita nesta tela.
func _apply_filter(emotion: EmotionDefinition, hold_progress: float) -> void:
	var tint: Color = emotion.tint if emotion != null else Color.WHITE
	tint.a = lerpf(filter_base_alpha, filter_hold_alpha, hold_progress)
	_filter.color = tint


# PLACEHOLDER: põe o retrato do NPC, ou o retângulo com o nome dele quando não há arte.
#
# O retrato vem do NPCDefinition, e não do perfil de profiling: é a cara do NPC, e o diário e a tela
# de diálogo vão mostrar a mesma imagem.
func _apply_portrait(image: TextureRect, caption: Label) -> void:
	var has_art: bool = _definition != null and _definition.portrait != null
	image.texture = _definition.portrait if has_art else null
	image.visible = has_art
	caption.visible = not has_art
	if not has_art:
		caption.text = "%s\n%s" % [tr("PLACEHOLDER_NPC_PORTRAIT"), _get_npc_name()]


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
	_shake.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
		* shake_strength * progress
	_apply_filter(_get_emotion(slot), progress)


# O retângulo encheu: a emoção do NPC passa a ser esta a partir do dia seguinte. Quem aplica isso na
# cidade é o NPCDirector, na virada de dia (ver ProfilingJournal.resolve_emotion_slot).
func _on_option_hold_completed(slot: int) -> void:
	_shake.position = Vector2.ZERO
	ProfilingJournal.schedule_emotion_slot(_npc_id, slot)


# A correção da página, a cada mudança. Só o acerto de uma história AINDA NÃO RESOLVIDA dispara a
# revelação — reabrir uma história resolvida mostra a mesma página sem tocar música de novo.
func _on_page_evaluated(evaluation: ProfilingEvaluation) -> void:
	if _story == null or _is_revealing or not evaluation.is_solved():
		return
	if ProfilingJournal.is_story_solved(_story.id):
		return
	_reveal_solved()


func _on_glossary_word_activated(word_id: StringName) -> void:
	_page.activate_word(word_id)


# O diário mudou (palavra nova, lacuna preenchida, marca posta): a tela aberta se redesenha.
func _on_journal_changed() -> void:
	if not _root.visible:
		return
	if _view == View.STORY:
		_page.refresh()
		_glossary.refresh()
	else:
		_refresh_spirit_view()


# O jogador acertou a última emoção deste NPC. Acordar não acontece aqui: a revelação da história
# ainda está na tela, e é ela que leva ao sono no fim (ver _reveal_solved).
func _on_npc_profiling_completed(npc_id: StringName) -> void:
	if npc_id != _npc_id:
		return
	_wake_pending = true
