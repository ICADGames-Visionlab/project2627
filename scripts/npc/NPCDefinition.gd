## NPCDefinition - quem um NPC é: nome, aparência, as duas emoções que ele pode sentir, os dias em
## que ele trabalha e as SEIS rotinas dele.
##
## COMO USAR: um .tres por NPC em res://resources/npcs/, apontado no roster
## (res://resources/npcs/npc_roster.tres). Criar um NPC novo é criar o arquivo, preencher e
## arrastar pro roster — nenhuma edição de código, nenhuma cena tocada.
##
## AS SEIS ROTINAS
##
## A emoção vigente escolhe a LINHA e o dia da semana escolhe a COLUNA:
##
##                     dia de trabalho          dia de folga
##     neutro          routine_neutral_workday  routine_neutral_day_off
##     emoção 1        routine_first_workday    routine_first_day_off
##     emoção 2        routine_second_workday   routine_second_day_off
##
## Campo vazio não quebra nada: a resolução cai no neutro (ver NPCRoutineResolver.resolve_routine),
## e o campo "resumo" aqui embaixo avisa quais dos seis estão faltando. Dois slots podem apontar o
## MESMO arquivo de rotina quando o comportamento é igual — é o jeito certo de dizer "na tristeza
## ele faz o mesmo que no neutro" sem duplicar entradas.
##
## POR QUE SLOT E NÃO EMOÇÃO: as rotinas são indexadas por slot (neutro / primeira / segunda), não
## pelo nome da emoção. É isso que permite que a emoção 1 do padeiro seja raiva e a da feirante
## seja medo, com as duas rodando exatamente no mesmo código.
##
## OS TRÊS TIPOS (campo kind): nem todo NPC precisa de tudo isso. O tipo diz o que vale pra ele, e
## o Inspector esconde os campos que não valem:
##
##                  rotina                 profiling (espírito, emoção)   cabeça nos insights
##     principal    sim                    sim                            ao completar o profiling
##     auxiliar     sim                    não                            não
##     estático     não: fica em           não                            não
##                  fixed_entry
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name NPCDefinition
extends Resource

## Espaço para enums

# Qual das emoções do NPC está vigente. NEUTRAL é o padrão e o fallback de todo mundo; FIRST e
# SECOND são os dois espaços que cada NPC preenche com emoções do catálogo.
enum EmotionSlot { NEUTRAL, FIRST, SECOND }

# Se hoje é dia de trabalho ou de folga PARA ESTE NPC — quem decide é work_weekdays, então o
# padeiro pode folgar na segunda enquanto a feirante folga no domingo.
enum DayType { WORKDAY, DAY_OFF }

# Que tipo de NPC este é (ver "OS TRÊS TIPOS" no topo). MAIN é o NPC completo, com tudo o que o
# sistema já faz; AUXILIARY cumpre rotina mas não tem profiling; STATIC não tem nem rotina nem
# profiling e fica o tempo todo em fixed_entry. A ordem importa: o .tres grava o número, e MAIN ser
# o zero é o que mantém como principal todo NPC criado antes de o tipo existir.
enum Kind { MAIN, AUXILIARY, STATIC }

## Espaço para constantes

# Nomes dos slots, dos tipos de dia e dos tipos de NPC em português, para log, resumo e menu de
# debug. Texto de ferramenta, não de jogador — por isso não passa pelo CSV.
const SLOT_NAMES: Array[String] = ["neutro", "emoção 1", "emoção 2"]
const DAY_TYPE_NAMES: Array[String] = ["trabalho", "folga"]
const KIND_NAMES: Array[String] = ["principal", "auxiliar", "estático"]

# Campos que só existem pra quem cumpre rotina: o estático não os usa, e o Inspector os esconde dele.
# As emoções estão aqui porque, sem profiling, a única coisa que a emoção escolhe é a rotina.
const ROUTINE_PROPERTIES: Array[StringName] = [
	&"walk_speed", &"emotion_first", &"emotion_second", &"starting_slot", &"work_weekdays",
	&"routine_neutral_workday", &"routine_neutral_day_off", &"routine_first_workday",
	&"routine_first_day_off", &"routine_second_workday", &"routine_second_day_off"]

# Campos que só existem pra quem tem profiling: o espírito no sonho e a cabeça nos insights. O
# Inspector os esconde do auxiliar e do estático.
const PROFILING_PROPERTIES: Array[StringName] = [&"spirit_art", &"dream_entry", &"head_glyph"]

# Todos os dias de semana marcados (seg a dom), usado no resumo pra dizer "trabalha todo dia".
const ALL_WEEKDAYS: int = 127

## Espaço para variáveis exportadas

## Identificador estável do NPC. É o que aparece em log, no menu de debug e o que outros sistemas
## (diálogo, quest) vão usar pra falar dele. Não é texto exibido ao jogador.
@export var id: StringName = &"":
	set(value):
		id = value
		_refresh_summary()

## Principal, auxiliar ou estático (ver "OS TRÊS TIPOS" no topo do script). Trocar o tipo esconde e
## mostra campos no Inspector, mas não apaga nada: o que estava preenchido continua no arquivo e
## volta a valer se o tipo voltar.
@export var kind: Kind = Kind.MAIN:
	set(value):
		kind = value
		_refresh_summary()

## Chave de tradução do nome, em translations/translations.csv (ex.: NPC_NAME_ZE). É o que aparece
## acima da cabeça dele. Nunca escreva o nome direto aqui.
## No diálogo o nome segue o padrão "Nome, Alcunha": a alcunha é a linha <name_key>_ALCUNHA do CSV
## (ex.: NPC_NAME_ZE_ALCUNHA = "O Padeiro"). Não há campo para ela aqui.
@export var name_key: StringName = &"":
	set(value):
		name_key = value
		_refresh_summary()

## A cor do NPC, a mesma em todo lugar em que ele aparece: o nome dele na coluna de diálogo, a
## silhueta do retrato vazio e o orbe da cabeça dele nos insights (ver InsightCatalog.load_all_heads).
## Precisa passar no contraste mínimo contra o fundo da coluna de diálogo — o resumo avisa quando não
## passa.
##
## PLACEHOLDER: enquanto todos os NPCs usam o spritesheet do Player, ela também tinge o sprite, e é o
## que diferencia um corpo do outro (ver a chave PLACEHOLDER_NPC_BODY no CSV). Quando a arte chegar,
## só essa parte some.
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		_refresh_summary()

## O retrato do NPC: a arte que representa a CARA dele, usada por quem precisa mostrá-lo sem ele
## estar em cena. Hoje quem usa é a tela de profiling no mundo dos sonhos (a metade direita da
## página da história) e a tela de diálogo (a moldura ao lado da coluna, slot 3:4 de
## DialogueStyle.portrait_slot_size, 180x240: imagem em outra proporção é cortada embaixo); o diário
## ("Pessoas Importantes") vai usar o mesmo campo — é por isso que ele mora aqui, e não dentro de um
## sistema só.
##
## Vazio não quebra nada: cada tela desenha o seu placeholder (o profiling, um retângulo com o nome
## do NPC; o diálogo, uma silhueta na cor do NPC). Basta arrastar a textura aqui no dia em que a
## arte existir.
@export var portrait: Texture2D

## A arte do espírito do NPC, em 1920x1080: cobre a tela inteira de escolher a emoção, no mundo dos
## sonhos, com o nome e as emoções por cima. Numa tela de outra proporção ela é cortada nas bordas,
## nunca esticada.
##
## Vazio não quebra nada: a tela mostra o aviso de placeholder no lugar.
@export var spirit_art: Texture2D

## Velocidade de caminhada, em pixels de tela por segundo. Balanceamento por NPC: um velho anda
## mais devagar que uma criança.
@export var walk_speed: float = 220.0

@export_group("Diálogo")

## Conversa aberta ao clicar no NPC (o id da conversa no catálogo de diálogo). Vazio = NPC não
## conversa (NPCInteraction não pede nada ao clicar nele).
@export var conversation_id: StringName = &""

@export_group("Emoções")

## A emoção do slot 1 deste NPC. Pode ser diferente da de qualquer outro NPC.
@export var emotion_first: EmotionDefinition:
	set(value):
		emotion_first = value
		_refresh_summary()

## A emoção do slot 2 deste NPC.
@export var emotion_second: EmotionDefinition:
	set(value):
		emotion_second = value
		_refresh_summary()

## Com qual emoção ele começa a partida. Enquanto o sistema de emoção não existir, é a emoção dele
## sempre — e o menu de debug permite forçar as outras pra testar as seis rotinas.
@export var starting_slot: EmotionSlot = EmotionSlot.NEUTRAL:
	set(value):
		starting_slot = value
		_refresh_summary()

@export_group("Calendário")

## Em que dias da semana este NPC trabalha. Os outros são folga, e puxam as rotinas de folga.
## O padrão é segunda a sexta.
@export_flags("Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom") var work_weekdays: int = 31:
	set(value):
		work_weekdays = value
		_refresh_summary()

@export_group("Rotinas")

@export var routine_neutral_workday: NPCRoutine:
	set(value):
		routine_neutral_workday = value
		_refresh_summary()

@export var routine_neutral_day_off: NPCRoutine:
	set(value):
		routine_neutral_day_off = value
		_refresh_summary()

@export var routine_first_workday: NPCRoutine:
	set(value):
		routine_first_workday = value
		_refresh_summary()

@export var routine_first_day_off: NPCRoutine:
	set(value):
		routine_first_day_off = value
		_refresh_summary()

@export var routine_second_workday: NPCRoutine:
	set(value):
		routine_second_workday = value
		_refresh_summary()

@export var routine_second_day_off: NPCRoutine:
	set(value):
		routine_second_day_off = value
		_refresh_summary()

@export_group("Posição fixa")

## Onde o NPC estático fica: a cena e o waypoint, no mesmo formato de uma entrada de rotina. O
## HORÁRIO DA ENTRADA É IGNORADO — ele está ali o dia inteiro, todo dia, e nunca anda. Só aparece no
## Inspector quando o tipo é estático. Vazio = ele não aparece em lugar nenhum (o resumo avisa).
@export var fixed_entry: NPCRoutineEntry:
	set(value):
		fixed_entry = value
		_refresh_summary()

@export_group("Mundo dos sonhos")

## Onde este NPC fica enquanto o jogador sonha: a cena e o waypoint, no mesmo formato de uma entrada
## de rotina. O HORÁRIO DA ENTRADA É IGNORADO — no sonho o relógio está travado (ver
## TimeSettings.dream_hour) e o NPC não sai do lugar. Vazio = o NPC não aparece no sonho.
## Preenchido, ele só aparece depois de o jogador conversar com ele no mundo real (ver
## ProfilingJournal.can_appear_in_dream).
@export var dream_entry: NPCRoutineEntry:
	set(value):
		dream_entry = value
		_refresh_summary()

@export_group("Insights")

## O que as cabeças do jogador têm a dizer sobre este NPC quando o jogador chega perto dele. O orbe
## aparece acima da cabeça do JOGADOR, na cor da cabeça que fala — nunca em cima do NPC.
##
## Só insights do canal de personagem: NPC não tem insight de ambiente (o orbe verde ficaria em cima
## dele, disputando o clique que abre a conversa). Um de ambiente aqui é ignorado, e o resumo avisa.
## Os .tres ficam em res://resources/insights/, como todos os outros, para a validação em lote
## conferir id, text_key e head_id.
@export var insights: Array[InsightData] = []:
	set(value):
		insights = value
		_refresh_summary()

## A letra desenhada dentro do orbe da cabeça deste NPC — a cabeça que o jogador ganha ao completar o
## profiling dele. Vazio = a inicial do id. Precisa ser diferente da letra de todas as outras
## cabeças: é o que distingue os orbes para quem não distingue as cores.
@export var head_glyph: String = ""

@export_group("")

## Só leitura: as seis rotinas e o que está faltando, escrito por extenso. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

func _init() -> void:
	_refresh_summary()


# Deixa o resumo só de leitura e esconde os campos que o tipo do NPC não usa. Esconder tira só a flag
# de editor: o valor continua sendo gravado no .tres, então trocar o tipo e voltar não perde nada.
func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY
		return

	var property_name: StringName = StringName(property.name)
	var hidden: bool = false
	if property_name == &"fixed_entry":
		hidden = has_routine()
	elif ROUTINE_PROPERTIES.has(property_name):
		hidden = not has_routine()
	elif PROFILING_PROPERTIES.has(property_name):
		hidden = not has_profiling()
	if hidden:
		property.usage &= ~PROPERTY_USAGE_EDITOR

## Espaço para funções personalizadas

# Diz se o NPC cumpre rotina. O estático não: fica o tempo todo em fixed_entry.
func has_routine() -> bool:
	return kind != Kind.STATIC


# Diz se o NPC tem profiling: espírito no sonho, emoção escolhida pelo jogador e, com o profiling
# completo, a cabeça dele falando nos insights. Só o principal tem — auxiliar e estático não têm
# perfil, e por isso nunca liberam cabeça nenhuma.
func has_profiling() -> bool:
	return kind == Kind.MAIN


# A emoção com que o NPC começa a partida. O estático fica sempre no neutro: sem rotina, não há o que
# a emoção escolher, e o starting_slot dele (escondido no Inspector) pode ter sobrado de quando ele
# era de outro tipo.
func get_starting_slot() -> EmotionSlot:
	if not has_routine():
		return EmotionSlot.NEUTRAL
	return starting_slot


# A posição do NPC estático, ou null se cena ou waypoint não foram preenchidos. Quem usa é o
# NPCRoutineResolver, que só pergunta isto quando has_routine() é falso.
func get_fixed_entry() -> NPCRoutineEntry:
	if fixed_entry == null or fixed_entry.scene_path == "" or fixed_entry.waypoint == &"":
		return null
	return fixed_entry


# A rotina de um dos seis slots, ou null se o design não preencheu aquele campo. Quem quer a
# rotina que VALE (com a cadeia de fallback) chama NPCRoutineResolver.resolve_routine, não isto.
func get_routine(slot: EmotionSlot, day_type: DayType) -> NPCRoutine:
	var is_workday: bool = day_type == DayType.WORKDAY
	match slot:
		EmotionSlot.FIRST:
			return routine_first_workday if is_workday else routine_first_day_off
		EmotionSlot.SECOND:
			return routine_second_workday if is_workday else routine_second_day_off
		_:
			return routine_neutral_workday if is_workday else routine_neutral_day_off


# A emoção que ocupa um slot, ou null no neutro (que não é uma emoção do catálogo: é a ausência
# de emoção vigente).
func get_emotion(slot: EmotionSlot) -> EmotionDefinition:
	match slot:
		EmotionSlot.FIRST:
			return emotion_first
		EmotionSlot.SECOND:
			return emotion_second
		_:
			return null


# Diz se este NPC trabalha num dia da semana. O índice é o do GameTime.get_weekday(): 0 = segunda.
func is_workday(weekday: int) -> bool:
	return (work_weekdays & (1 << weekday)) != 0


# Nome do NPC traduzido, com o id como último recurso pra nunca aparecer vazio.
func get_display_name() -> String:
	if name_key == &"":
		return String(id)
	return tr(name_key)


# Nome legível de um slot, já dizendo qual emoção o preenche neste NPC: "emoção 1 (raiva)".
func describe_slot(slot: EmotionSlot) -> String:
	var emotion: EmotionDefinition = get_emotion(slot)
	if emotion == null:
		return SLOT_NAMES[slot]
	return "%s (%s)" % [SLOT_NAMES[slot], emotion.id]


# Os insights deste NPC que valem: só os do canal de personagem. Entrada vazia e insight de ambiente
# ficam de fora (ver o campo insights); quem aponta o erro é o collect_issues().
func get_character_insights() -> Array[InsightData]:
	var result: Array[InsightData] = []
	for insight: InsightData in insights:
		if insight != null and insight.is_character():
			result.append(insight)
	return result


# A letra do orbe da cabeça deste NPC: a escolhida no Inspector, ou a inicial do id.
func get_head_glyph() -> String:
	if not head_glyph.is_empty():
		return head_glyph
	return String(id).left(1).to_upper()


# Problemas da definição, uma frase por problema. Compartilhado entre o resumo do Inspector e o
# comando "Validar rotinas" do menu de debug. Só cobra o que o tipo do NPC usa: do estático não se
# cobra rotina, e de quem não tem profiling não se cobram as emoções nem a posição no sonho.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []

	if id == &"":
		issues.append("Sem id.")
	if name_key == &"":
		issues.append("Sem chave de nome (name_key) — o nome acima da cabeça sairia vazio.")
	# Sem profiling ninguém troca a emoção do NPC (quem troca é o jogador, no espírito), então só o
	# principal precisa ter as duas.
	if has_profiling() and emotion_first == null:
		issues.append("Sem emoção no slot 1.")
	if has_profiling() and emotion_second == null:
		issues.append("Sem emoção no slot 2.")
	if has_routine() and get_routine(EmotionSlot.NEUTRAL, DayType.WORKDAY) == null:
		issues.append("Sem rotina neutro/trabalho — ela é o último fallback de todos os outros slots.")
	if not has_routine() and get_fixed_entry() == null:
		issues.append("Sem posição fixa (fixed_entry com cena e waypoint): o NPC estático não aparece em lugar nenhum.")
	if has_profiling() and (dream_entry == null or dream_entry.scene_path == "" or dream_entry.waypoint == &""):
		issues.append("Sem posição no mundo dos sonhos (dream_entry): some enquanto o jogador sonha.")

	var dialogue_style: DialogueStyle = load("res://resources/dialogue/dialogue_style.tres")
	if dialogue_style != null:
		var ratio: float = DialogueContrast.worst_speaker_ratio(color, dialogue_style, 0.82)
		if ratio < dialogue_style.min_contrast_ratio:
			issues.append("Cor do NPC com contraste %.1f:1 no diálogo, contando a fala passada (mínimo %.1f:1)."
				% [ratio, dialogue_style.min_contrast_ratio])
		# Branco é o padrão do campo e passa em qualquer contraste, então uma cor esquecida (ou perdida
		# num .tres que ainda grava um campo renomeado) só aparece aqui: o nome do NPC fica igual ao do
		# jogador na coluna, e o sprite fica sem tinta, igual ao corpo do jogador.
		if color.is_equal_approx(dialogue_style.player_name_color):
			issues.append("Cor do NPC igual à do jogador no diálogo — provavelmente não foi preenchida.")

	for index: int in insights.size():
		var insight: InsightData = insights[index]
		if insight == null:
			issues.append("Insight %d está vazio." % index)
		elif not insight.is_character():
			issues.append("Insight \"%s\" é de ambiente: NPC só tem insight de personagem, e este é ignorado." % insight.id)

	if not has_routine():
		return issues

	for slot: int in EmotionSlot.values():
		for day_type: int in DayType.values():
			var routine: NPCRoutine = get_routine(slot, day_type)
			if routine == null:
				if _expects_routine(slot):
					issues.append("Sem rotina %s/%s: vai cair no fallback." % [
						SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]])
			# Uma rotina só de exceção (um guarda que só circula) não está vazia: o que ela deixa de
			# cobrir é apontado pela própria rotina (NPCRoutine.collect_issues).
			elif routine.count_valid_entries() == 0 and routine.count_valid_exceptions() == 0:
				issues.append("Rotina %s/%s está vazia ou incompleta." % [
					SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]])

	return issues


# Diz se a falta da rotina de um slot merece aviso. No principal, sempre: o jogador pode escolher
# qualquer emoção no espírito. No auxiliar, só no neutro e nos slots que têm emoção: sem profiling
# ninguém troca a emoção dele, e deixar um slot vazio é fazer um NPC mais simples, não esquecimento.
func _expects_routine(slot: EmotionSlot) -> bool:
	return has_profiling() or slot == EmotionSlot.NEUTRAL or get_emotion(slot) != null


func _refresh_summary() -> void:
	var lines: PackedStringArray = []
	if has_routine():
		lines.append("NPC %s \"%s\" · emoção inicial: %s" % [KIND_NAMES[kind], id, describe_slot(get_starting_slot())])
		lines.append("Trabalha: %s" % _describe_work_weekdays())
		if not has_profiling():
			lines.append("Sem profiling: não aparece no sonho, a emoção não muda e não libera cabeça.")
		lines.append("")
		_append_routine_lines(lines)
	else:
		var place: NPCRoutineEntry = get_fixed_entry()
		lines.append("NPC %s \"%s\" · %s" % [KIND_NAMES[kind], id,
			"fica em %s" % place.describe_place() if place != null else "SEM POSIÇÃO FIXA"])
		lines.append("Sem rotina e sem profiling: não anda, não aparece no sonho e não libera cabeça.")

	var issues: PackedStringArray = collect_issues()
	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()


# As seis linhas de rotina do resumo, uma por slot e tipo de dia, com quantas entradas cada uma tem.
func _append_routine_lines(lines: PackedStringArray) -> void:
	for slot: int in EmotionSlot.values():
		for day_type: int in DayType.values():
			var routine: NPCRoutine = get_routine(slot, day_type)
			var status: String = "FALTANDO (cai no fallback)"
			if routine != null:
				status = "%d entradas" % routine.count_valid_entries()
				if not routine.exceptions.is_empty():
					status += " + %d %s" % [routine.count_valid_exceptions(),
						"exceção" if routine.count_valid_exceptions() == 1 else "exceções"]
			lines.append("%-22s %s" % ["%s / %s" % [SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]], status])


# "seg, ter, qua, qui, sex" — os dias marcados em work_weekdays, por extenso.
func _describe_work_weekdays() -> String:
	if work_weekdays == 0:
		return "nunca (folga todo dia)"
	if work_weekdays == ALL_WEEKDAYS:
		return "todos os dias"

	var names: Array[String] = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]
	var marked: PackedStringArray = []
	for index: int in names.size():
		if is_workday(index):
			marked.append(names[index])
	return ", ".join(marked)
