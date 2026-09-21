## NPCRoutine - uma rotina inteira: a lista de entradas [horário, cena, waypoint] que descreve o
## dia de um NPC.
##
## COMO USAR: crie um .tres em res://resources/npcs/rotinas/ e vá adicionando entradas. O campo
## "resumo" (cinza, só leitura) se reescreve sozinho e mostra a rotina em ordem de relógio, já
## apontando o que está faltando — não é preciso rodar o jogo pra revisar uma rotina.
##
## A rotina é REAPROVEITÁVEL de propósito: o mesmo arquivo pode ser apontado em vários dos seis
## slots de um NPC (ver NPCDefinition.gd) e por vários NPCs. Se o dia de folga na raiva é igual ao
## dia de folga neutro, aponte o mesmo arquivo nos dois em vez de copiar as entradas — copiar
## significa corrigir duas vezes depois.
##
## A rotina pode ter EXCEÇÕES, e é opcional: faixas de horário em que um comportamento especial assume
## o NPC no lugar das entradas — a ronda do policial, por exemplo (ver NPCRoutineException). Sem
## exceção, que é o normal, a rotina se comporta exatamente como uma lista de entradas.
##
## A rotina não sabe quem a executa e não sabe que horas são: quem cruza rotina com relógio é o
## NPCRoutineResolver.
##
## O guia completo está em docs/sistema_de_npc.md.
@tool
class_name NPCRoutine
extends Resource

## Espaço para variáveis exportadas

## As entradas do dia. A ordem em que você adiciona não importa: quem executa ordena por horário
## (ver NPCRoutineResolver.sorted_entries).
@export var entries: Array[NPCRoutineEntry] = []:
	set(value):
		_disconnect_entries()
		entries = value
		_connect_entries()
		_refresh_summary()

## Exceções à rotina padrão (opcional, e vazio é o normal): faixas de horário em que um comportamento
## especial assume o NPC no lugar das entradas. Fora das faixas as entradas valem sozinhas, e onde
## duas faixas se sobrepõem vale a primeira da lista.
@export var exceptions: Array[NPCRoutineException] = []:
	set(value):
		_disconnect_exceptions()
		exceptions = value
		_connect_exceptions()
		_refresh_summary()

## Só leitura: a rotina por extenso, com os problemas apontados. Editar aqui não faz nada.
@export_multiline var resumo: String = ""

## Espaço para funções nativas

# Reconecta os avisos de mudança ao abrir o recurso: sem isso, o resumo só se atualizaria quando
# alguém mexesse na lista de entradas, e não quando mexesse DENTRO de uma entrada.
func _init() -> void:
	_connect_entries()
	_connect_exceptions()
	_refresh_summary()


# Deixa o campo "resumo" cinza no Inspector. Ele é saída, não entrada.
func _validate_property(property: Dictionary) -> void:
	if property.name == "resumo":
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Espaço para funções personalizadas

# Quantas entradas válidas (com cena e waypoint preenchidos) a rotina tem.
func count_valid_entries() -> int:
	var total: int = 0
	for entry: NPCRoutineEntry in entries:
		if entry != null and entry.scene_path != "" and entry.waypoint != &"":
			total += 1
	return total


# Quantas exceções executáveis (que sabem dizer onde o NPC está) a rotina tem.
func count_valid_exceptions() -> int:
	var total: int = 0
	for exception: NPCRoutineException in exceptions:
		if exception != null and exception.is_executable():
			total += 1
	return total


# Problemas encontrados na rotina, uma frase por problema. Usado no resumo do Inspector e no
# comando "Validar rotinas" do menu de debug — mesma lista nos dois lugares, pra não existir
# validação que só aparece num deles.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	var seen_minutes: Dictionary = {}

	if entries.is_empty() and exceptions.is_empty():
		issues.append("A rotina está vazia.")

	for index: int in entries.size():
		var entry: NPCRoutineEntry = entries[index]
		if entry == null:
			issues.append("Entrada %d está vazia (falta criar o recurso)." % index)
			continue
		if entry.scene_path == "":
			issues.append("Entrada %d (%s) não aponta cena." % [index, entry.format_clock()])
		if entry.waypoint == &"":
			issues.append("Entrada %d (%s) não aponta waypoint." % [index, entry.format_clock()])

		var clock: int = entry.get_clock_minutes()
		if seen_minutes.has(clock):
			issues.append("Duas entradas no mesmo horário (%s): a última ganha." % entry.format_clock())
		seen_minutes[clock] = true

	_collect_exception_issues(issues)
	return issues


# Reescreve o resumo. A ordem mostrada é a do RELÓGIO DE PAREDE, não a do dia de jogo: a ordem do
# dia depende da hora de acordar (ver NPCRoutineEntry.get_minutes_into_day), que é balanceamento
# do TimeSettings e não pertence a este arquivo.
func _refresh_summary() -> void:
	var ordered: Array[NPCRoutineEntry] = []
	for entry: NPCRoutineEntry in entries:
		if entry != null:
			ordered.append(entry)
	ordered.sort_custom(func(a: NPCRoutineEntry, b: NPCRoutineEntry) -> bool:
		return a.get_clock_minutes() < b.get_clock_minutes())

	var lines: PackedStringArray = []
	lines.append("%d entradas (ordem de relógio):" % entries.size())
	for entry: NPCRoutineEntry in ordered:
		lines.append("  " + entry.describe())

	# Bloco só existe quando há exceção: o resumo de uma rotina comum continua exatamente o mesmo.
	if not exceptions.is_empty():
		lines.append("")
		lines.append("Exceções (onde as faixas se sobrepõem, vale a primeira):")
		for exception: NPCRoutineException in exceptions:
			lines.append("  " + (exception.describe() if exception != null else "(vazia)"))

	var issues: PackedStringArray = collect_issues()
	if not issues.is_empty():
		lines.append("")
		lines.append("ATENÇÃO:")
		for issue: String in issues:
			lines.append("  - " + issue)

	resumo = "\n".join(lines)
	notify_property_list_changed()


# Passa a escutar as entradas atuais, pro resumo reagir também a mudanças feitas dentro de uma
# entrada (trocar o horário de uma linha, por exemplo).
func _connect_entries() -> void:
	for entry: NPCRoutineEntry in entries:
		if entry != null and not entry.changed.is_connected(_refresh_summary):
			entry.changed.connect(_refresh_summary)


func _disconnect_entries() -> void:
	for entry: NPCRoutineEntry in entries:
		if entry != null and entry.changed.is_connected(_refresh_summary):
			entry.changed.disconnect(_refresh_summary)


# Mesma ideia das entradas, pras exceções: a ronda é um recurso compartilhado entre rotinas, e cada
# rotina que a usa precisa reescrever o próprio resumo quando alguém mexe nos pontos dela.
func _connect_exceptions() -> void:
	for exception: NPCRoutineException in exceptions:
		if exception != null and not exception.changed.is_connected(_refresh_summary):
			exception.changed.connect(_refresh_summary)


# Solta as exceções atuais antes de a lista ser trocada, pra uma ronda que saiu da rotina não continuar
# mandando avisos pro resumo dela.
func _disconnect_exceptions() -> void:
	for exception: NPCRoutineException in exceptions:
		if exception != null and exception.changed.is_connected(_refresh_summary):
			exception.changed.disconnect(_refresh_summary)


# Acrescenta à lista os problemas das exceções: recurso faltando, problema dentro de uma exceção,
# faixas que se sobrepõem e rotina sem nenhuma entrada que não cobre o dia inteiro.
func _collect_exception_issues(issues: PackedStringArray) -> void:
	var covers_whole_day: bool = false

	for index: int in exceptions.size():
		var exception: NPCRoutineException = exceptions[index]
		if exception == null:
			issues.append("Exceção %d está vazia (falta criar o recurso)." % index)
			continue

		for issue: String in exception.collect_issues():
			issues.append("Exceção %d (%s): %s" % [index, exception.describe_window(), issue])

		if exception.get_length_minutes() == NPCRoutineException.MINUTES_PER_DAY:
			covers_whole_day = true

		for other_index: int in range(index + 1, exceptions.size()):
			var other: NPCRoutineException = exceptions[other_index]
			if other != null and exception.overlaps(other):
				issues.append("As exceções %d (%s) e %d (%s) se sobrepõem: onde as faixas se cruzam, vale a primeira da lista." % [
					index, exception.describe_window(), other_index, other.describe_window()])

	# Sem entrada nenhuma, o NPC só tem onde estar dentro das faixas das exceções.
	if not exceptions.is_empty() and count_valid_entries() == 0 and not covers_whole_day:
		issues.append("A rotina não tem entradas: fora das faixas das exceções o NPC não tem onde ficar.")
