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

## Espaço para constantes

# Nomes dos slots e dos tipos de dia em português, para log e menu de debug. Texto de ferramenta,
# não de jogador — por isso não passa pelo CSV.
const SLOT_NAMES: Array[String] = ["neutro", "emoção 1", "emoção 2"]
const DAY_TYPE_NAMES: Array[String] = ["trabalho", "folga"]

# Todos os dias de semana marcados (seg a dom), usado no resumo pra dizer "trabalha todo dia".
const ALL_WEEKDAYS: int = 127

## Espaço para variáveis exportadas

## Identificador estável do NPC. É o que aparece em log, no menu de debug e o que outros sistemas
## (diálogo, quest) vão usar pra falar dele. Não é texto exibido ao jogador.
@export var id: StringName = &"":
	set(value):
		id = value
		_refresh_summary()

## Chave de tradução do nome, em translations/translations.csv (ex.: NPC_NAME_ZE). É o que aparece
## acima da cabeça dele. Nunca escreva o nome direto aqui.
## No diálogo o nome segue o padrão "Nome, Alcunha": a alcunha é a linha <name_key>_ALCUNHA do CSV
## (ex.: NPC_NAME_ZE_ALCUNHA = "O Padeiro"). Não há campo para ela aqui.
@export var name_key: StringName = &"":
	set(value):
		name_key = value
		_refresh_summary()

## PLACEHOLDER: cor que tinge o sprite do NPC. Enquanto todos usam o mesmo spritesheet do Player, é
## o que diferencia um do outro (ver a chave PLACEHOLDER_NPC_BODY no CSV).
@export var tint: Color = Color.WHITE

## Velocidade de caminhada, em pixels de tela por segundo. Balanceamento por NPC: um velho anda
## mais devagar que uma criança.
@export var walk_speed: float = 220.0

@export_group("Diálogo")

## Cor do nome do NPC na coluna de diálogo. Diferente de tint (que é placeholder de sprite): esta
## precisa passar no contraste mínimo contra o fundo da coluna de diálogo.
@export var dialogue_color: Color = Color("#E0C080"):
	set(value):
		dialogue_color = value
		_refresh_summary()

## Conversa aberta ao clicar no NPC (o id da conversa no catálogo de diálogo). Vazio = NPC não
## conversa (NPCInteraction não pede nada ao clicar nele).
@export var conversation_id: StringName = &""

## Retrato mostrado numa moldura ao lado da coluna de diálogo enquanto este NPC conversa. Vazio =
## o diálogo desenha uma silhueta na dialogue_color (PLACEHOLDER até a arte final). O slot é 3:4
## (DialogueStyle.portrait_slot_size, 180x240): imagem em outra proporção é cortada embaixo.
@export var portrait: Texture2D

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

@export_group("")

## Só leitura: as seis rotinas e o que está faltando, escrito por extenso. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

func _init() -> void:
	_refresh_summary()


func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

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


# Problemas da definição, uma frase por problema. Compartilhado entre o resumo do Inspector e o
# comando "Validar rotinas" do menu de debug.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []

	if id == &"":
		issues.append("Sem id.")
	if name_key == &"":
		issues.append("Sem chave de nome (name_key) — o nome acima da cabeça sairia vazio.")
	if emotion_first == null:
		issues.append("Sem emoção no slot 1.")
	if emotion_second == null:
		issues.append("Sem emoção no slot 2.")
	if get_routine(EmotionSlot.NEUTRAL, DayType.WORKDAY) == null:
		issues.append("Sem rotina neutro/trabalho — ela é o último fallback de todos os outros slots.")

	var dialogue_style: DialogueStyle = load("res://resources/dialogue/dialogue_style.tres")
	if dialogue_style != null:
		var ratio: float = DialogueContrast.worst_case_ratio(dialogue_color, 1.0, dialogue_style, 0.82)
		if ratio < dialogue_style.min_contrast_ratio:
			issues.append("Cor de diálogo com contraste %.1f:1 (mínimo %.1f:1)." % [ratio, dialogue_style.min_contrast_ratio])

	for slot: int in EmotionSlot.values():
		for day_type: int in DayType.values():
			var routine: NPCRoutine = get_routine(slot, day_type)
			if routine == null:
				issues.append("Sem rotina %s/%s: vai cair no fallback." % [
					SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]])
			elif routine.count_valid_entries() == 0:
				issues.append("Rotina %s/%s está vazia ou incompleta." % [
					SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]])

	return issues


func _refresh_summary() -> void:
	var lines: PackedStringArray = []
	lines.append("NPC \"%s\" · emoção inicial: %s" % [id, describe_slot(starting_slot)])
	lines.append("Trabalha: %s" % _describe_work_weekdays())
	lines.append("")

	for slot: int in EmotionSlot.values():
		for day_type: int in DayType.values():
			var routine: NPCRoutine = get_routine(slot, day_type)
			var status: String = "FALTANDO (cai no fallback)"
			if routine != null:
				status = "%d entradas" % routine.count_valid_entries()
			lines.append("%-22s %s" % ["%s / %s" % [SLOT_NAMES[slot], DAY_TYPE_NAMES[day_type]], status])

	var issues: PackedStringArray = collect_issues()
	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()


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
