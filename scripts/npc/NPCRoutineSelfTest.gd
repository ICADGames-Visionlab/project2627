# NPCRoutineSelfTest.gd — Autoteste da resolução de rotinas de NPC, com as exceções (a ronda).
#
# A parte que dá bug num sistema de rotina é a aritmética de horário, e é a que mais custa achar: um
# erro de uma parada no fim da ronda não quebra nada visível, só faz o policial voltar pro quartel dez
# minutos cedo numa cena que ninguém está olhando. Este autoteste confere a LÓGICA da resolução contra
# rotinas montadas em memória — sem cena, sem relógio e sem tocar em nenhum arquivo do design.
#
# Cobre o que é fácil de errar: a faixa que atravessa a meia-noite, a que atravessa a hora de acordar,
# o fim exclusivo, a prioridade entre faixas, a exceção incompleta que não pode deixar o NPC sem lugar,
# e a garantia de que uma rotina SEM exceção continua resolvendo como sempre resolveu.
#
# Duas portas de entrada: a ação "Autoteste das rotinas" no menu de debug (F4) e o script de linha de
# comando tests/run_npc_routine_self_test.gd, que sai com código de erro quando algo falha.
#
# Os textos são hardcoded em português: são texto de ferramenta, que nunca chega ao jogador — ver
# docs/debug_menu.md, "Os textos da ferramenta não passam por tr()".
class_name NPCRoutineSelfTest
extends RefCounted

const CHECK: String = "✓"
const CROSS: String = "✗"

# Hora de acordar de todos os casos: a do TimeSettings de hoje. O que importa é que NÃO seja zero, pra a
# diferença entre "minuto do dia de jogo" e "relógio de parede" ser exercitada de verdade.
const WAKE_HOUR: int = 6

# Só um texto: nenhuma cena é carregada, o resolver nunca abre o arquivo.
const SCENE: String = "res://scenes/City.tscn"

var passed_count: int = 0
var failed_count: int = 0

var _lines: PackedStringArray = PackedStringArray()


# Roda todos os casos. Pode ser chamado de novo: cada execução começa zerada.
func run() -> void:
	passed_count = 0
	failed_count = 0
	_lines.clear()

	_test_entry_helpers()
	_test_baseline()
	_test_patrol()
	_test_next_change()
	_test_window_shapes()
	_test_priority()
	_test_incomplete()
	_test_issues()
	_test_windows()


# Relatório da última execução, pronto para print(): o resumo na primeira linha e um ✓/✗ por caso.
func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[NPCs] - Autoteste das rotinas: %d ok, %d falha(s)" % [passed_count, failed_count])
	lines.append_array(_lines)
	return "\n".join(lines)


# As duas peças que a exceção usa pra falar com o resto do sistema.
func _test_entry_helpers() -> void:
	var late: NPCRoutineEntry = NPCRoutineEntry.from_clock_minutes(25 * 60 + 5, SCENE, &"a")
	_expect_equal("Entrada avulsa dá a volta no dia", late.format_clock(), "01:05")

	var first: NPCRoutineEntry = _entry(8, 0, &"praca")
	var second: NPCRoutineEntry = _entry(12, 0, &"praca")
	var elsewhere: NPCRoutineEntry = _entry(8, 0, &"feira")
	_expect_true("Mesmo lugar em horários diferentes é o mesmo lugar", first.is_same_place(second))
	_expect_true("Waypoint diferente é lugar diferente", not first.is_same_place(elsewhere))
	_expect_true("Nenhuma entrada é o mesmo lugar que nada", not first.is_same_place(null))


# Rotina sem exceção: tem que resolver exatamente como resolvia antes de as exceções existirem.
func _test_baseline() -> void:
	var definition: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), _entry(7, 30, &"quartel"), _entry(19, 0, &"casa")], [])

	_expect_waypoint("Sem exceção: antes da segunda entrada, vale a primeira", _decide(definition, 7, 29), &"casa")
	_expect_waypoint("Sem exceção: a entrada vale a partir do horário dela", _decide(definition, 7, 30), &"quartel")
	_expect_waypoint("Sem exceção: vale até a entrada seguinte", _decide(definition, 18, 59), &"quartel")
	_expect_waypoint("Sem exceção: de madrugada vale a última entrada (onde ele passou a noite)",
		_decide(definition, 3, 0), &"casa")

	var decision: NPCRoutineResolver.Decision = _decide(definition, 7, 0)
	_expect_true("Sem exceção: a próxima entrada é a linha seguinte da rotina, no horário dela",
		decision.next_entry.waypoint == &"quartel" and decision.minutes_until_next == 30
		and decision.next_entry.format_clock() == "07:30")
	_expect_true("Sem exceção: nenhuma exceção é registrada na decisão", decision.exception == null)
	_expect_true("Sem exceção: o resumo da rotina não menciona exceção",
		not _routine_of(definition).resumo.contains("exceç"))
	_expect_true("Sem exceção: a rotina não tem problema nenhum", _routine_of(definition).collect_issues().is_empty())


# A ronda do policial: faixa, ciclo pelos pontos e volta da rotina padrão.
func _test_patrol() -> void:
	var patrol: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b", &"c"])
	var definition: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), _entry(7, 30, &"quartel"), _entry(19, 0, &"casa")], [patrol])

	_expect_waypoint("Antes da faixa, a rotina padrão vale", _decide(definition, 7, 59), &"quartel")
	_expect_true("Antes da faixa, nenhuma exceção manda", _decide(definition, 7, 59).exception == null)
	_expect_waypoint("A faixa abre no primeiro ponto", _decide(definition, 8, 0), &"a")
	_expect_true("Dentro da faixa, a decisão registra a exceção", _decide(definition, 8, 0).exception == patrol)
	_expect_waypoint("Ele fica no ponto até completar o tempo", _decide(definition, 8, 29), &"a")
	_expect_waypoint("Depois do tempo, segue pro segundo ponto", _decide(definition, 8, 30), &"b")
	_expect_waypoint("Depois, pro terceiro", _decide(definition, 9, 0), &"c")
	_expect_waypoint("No último ponto, volta ao primeiro", _decide(definition, 9, 30), &"a")
	_expect_waypoint("A volta se repete até o fim da faixa", _decide(definition, 16, 59), &"c")
	_expect_waypoint("O fim da faixa é exclusivo: às 17:00 a rotina padrão já voltou", _decide(definition, 17, 0), &"quartel")
	_expect_true("Depois da faixa, nenhuma exceção manda", _decide(definition, 17, 0).exception == null)
	_expect_waypoint("Mais tarde, as entradas seguintes da rotina continuam valendo", _decide(definition, 19, 0), &"casa")

	_expect_equal("O horário da parada é o de quando ele CHEGOU nela",
		_decide(definition, 9, 40).entry.format_clock(), "09:30")


# "Próxima mudança" do menu de debug: tem que dizer a verdade com a ronda em andamento.
func _test_next_change() -> void:
	var patrol: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b", &"c"])
	var definition: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), _entry(7, 30, &"quartel"), _entry(19, 0, &"casa")], [patrol])

	var decision: NPCRoutineResolver.Decision = _decide(definition, 8, 10)
	_expect_true("Em ronda, a próxima mudança é a próxima parada, no horário dela",
		decision.next_entry.waypoint == &"b" and decision.minutes_until_next == 20
		and decision.next_entry.format_clock() == "08:30")

	decision = _decide(definition, 16, 40)
	_expect_true("Na última parada, a próxima mudança é o fim da faixa, com a hora do fim (e não a da entrada)",
		decision.next_entry.waypoint == &"quartel" and decision.minutes_until_next == 20
		and decision.next_entry.format_clock() == "17:00")

	decision = _decide(definition, 7, 0)
	_expect_true("Antes da faixa, uma entrada que vem antes dela é a próxima mudança",
		decision.next_entry.waypoint == &"quartel" and decision.minutes_until_next == 30)

	decision = _decide(definition, 7, 40)
	_expect_true("Antes da faixa, o começo dela é a próxima mudança, com o primeiro ponto",
		decision.next_entry.waypoint == &"a" and decision.minutes_until_next == 20
		and decision.next_entry.format_clock() == "08:00")

	# Uma entrada da rotina padrão que cai no meio da ronda não muda nada visível. A entrada é às 11:55,
	# antes da próxima parada (12:00): se ela contasse, o resultado seria 5 minutos e não 10.
	var with_lunch: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), _entry(11, 55, &"quartel")], [_patrol(8, 17, 30, [&"a", &"b", &"c"])])
	decision = _decide(with_lunch, 11, 50)
	_expect_true("Entrada da rotina no meio da ronda não conta como mudança",
		decision.next_entry.waypoint == &"c" and decision.minutes_until_next == 10)


# Formas de faixa: a que atravessa a meia-noite, a que atravessa a hora de acordar, a que vale o dia todo.
func _test_window_shapes() -> void:
	# Três pontos de uma hora cada numa faixa de quatro horas: à meia-noite ele está no TERCEIRO ponto, e
	# não de volta ao primeiro, que é o que um ciclo reiniciado na virada do relógio daria.
	var midnight: NPCDefinition = _definition([_entry(6, 0, &"casa")], [_patrol(22, 2, 60, [&"a", &"b", &"c"])])
	_expect_waypoint("Faixa 22:00-02:00: antes de abrir, vale a rotina padrão", _decide(midnight, 21, 59), &"casa")
	_expect_waypoint("Faixa 22:00-02:00: abre às 22:00", _decide(midnight, 22, 0), &"a")
	_expect_waypoint("Faixa 22:00-02:00: às 23:00 vai pro segundo ponto", _decide(midnight, 23, 0), &"b")
	_expect_waypoint("Faixa 22:00-02:00: atravessa a meia-noite sem reiniciar o ciclo", _decide(midnight, 0, 0), &"c")
	_expect_waypoint("Faixa 22:00-02:00: vale até 01:59, já na segunda volta", _decide(midnight, 1, 59), &"a")
	_expect_waypoint("Faixa 22:00-02:00: às 02:00 acabou", _decide(midnight, 2, 0), &"casa")

	var wake: NPCDefinition = _definition([_entry(6, 0, &"casa")], [_patrol(5, 7, 30, [&"a", &"b", &"c", &"d"])])
	_expect_waypoint("Faixa 05:00-07:00 (atravessa a hora de acordar): abre às 05:00", _decide(wake, 5, 0), &"a")
	_expect_waypoint("Faixa 05:00-07:00: o ciclo não reinicia quando o dia de jogo vira", _decide(wake, 6, 0), &"c")
	_expect_waypoint("Faixa 05:00-07:00: vale até 06:59", _decide(wake, 6, 59), &"d")
	_expect_waypoint("Faixa 05:00-07:00: às 07:00 acabou", _decide(wake, 7, 0), &"casa")
	_expect_waypoint("Faixa 05:00-07:00: antes de abrir, vale a rotina padrão", _decide(wake, 4, 59), &"casa")

	var whole_day: NPCPatrol = _patrol(6, 6, 60, [&"a", &"b"])
	var all_day: NPCDefinition = _definition([], [whole_day])
	_expect_equal("Começo igual ao fim vale como o dia inteiro", whole_day.describe_window(), "o dia inteiro")
	_expect_waypoint("Dia inteiro: começa no primeiro ponto", _decide(all_day, 6, 0), &"a")
	_expect_waypoint("Dia inteiro: segue o ciclo", _decide(all_day, 7, 0), &"b")
	_expect_waypoint("Dia inteiro: vale até o último minuto do dia de jogo", _decide(all_day, 5, 59), &"b")
	_expect_true("Dia inteiro sem entrada nenhuma: o NPC sem rotina padrão de verdade tem onde estar",
		_decide(all_day, 12, 0).entry != null)
	_expect_true("Dia inteiro: a rotina não reclama de não ter entradas", _routine_of(all_day).collect_issues().is_empty())


# Duas faixas na mesma rotina: vale a primeira da lista.
func _test_priority() -> void:
	var first: NPCPatrol = _patrol(8, 12, 60, [&"a", &"b"])
	var second: NPCPatrol = _patrol(10, 14, 60, [&"x", &"y"])
	var definition: NPCDefinition = _definition([_entry(6, 0, &"casa")], [first, second])

	_expect_true("Duas faixas: onde só a primeira vale, ela manda", _decide(definition, 9, 0).exception == first)
	_expect_true("Duas faixas: onde se sobrepõem, vale a primeira da lista", _decide(definition, 11, 0).exception == first)
	_expect_waypoint("Duas faixas: onde só a segunda vale, ela manda", _decide(definition, 12, 0), &"x")
	_expect_issue("Duas faixas que se sobrepõem são apontadas", _routine_of(definition).collect_issues(), "se sobrepõem")

	var back_to_back: NPCDefinition = _definition(
		[_entry(6, 0, &"casa")], [_patrol(8, 12, 60, [&"a", &"b"]), _patrol(12, 14, 60, [&"x", &"y"])])
	_expect_true("Faixas coladas não se sobrepõem", _routine_of(back_to_back).collect_issues().is_empty())


# Exceção incompleta: não pode deixar o NPC sem lugar, e a rotina sem entrada precisa dizer o que falta.
func _test_incomplete() -> void:
	var empty_patrol: NPCPatrol = _patrol(8, 17, 30, [])
	var with_empty: NPCDefinition = _definition([_entry(6, 0, &"casa"), _entry(7, 30, &"quartel")], [empty_patrol])
	var decision: NPCRoutineResolver.Decision = _decide(with_empty, 9, 0)
	_expect_true("Ronda sem pontos é ignorada: vale a rotina padrão",
		decision.entry.waypoint == &"quartel" and decision.exception == null)
	_expect_true("Ronda sem pontos não conta como exceção válida", _routine_of(with_empty).count_valid_exceptions() == 0)

	var blank: NPCDefinition = _definition([_entry(6, 0, &"casa")], [_patrol(8, 17, 30, [&"a", &"", &"c"])])
	_expect_waypoint("Ponto vazio no meio: os pontos de antes funcionam", _decide(blank, 8, 0), &"a")
	_expect_waypoint("Ponto vazio no meio: enquanto ele dura, vale a rotina padrão", _decide(blank, 8, 30), &"casa")
	_expect_waypoint("Ponto vazio no meio: os pontos de depois funcionam", _decide(blank, 9, 0), &"c")

	var only_patrol: NPCDefinition = _definition([], [_patrol(8, 17, 30, [&"a", &"b"])])
	_expect_true("Só exceção: fora da faixa não há de onde tirar um lugar", _decide(only_patrol, 7, 0).entry == null)
	_expect_true("Só exceção: dentro da faixa ele tem lugar", _decide(only_patrol, 9, 0).entry != null)
	_expect_true("Só exceção: no fim da faixa a próxima mudança não tem lugar definido",
		_decide(only_patrol, 16, 50).next_entry == null)
	_expect_issue("Só exceção, sem cobrir o dia: a rotina avisa do buraco",
		_routine_of(only_patrol).collect_issues(), "não tem onde ficar")

	_expect_issue("Exceção vazia na lista é apontada",
		_routine_of(_definition([_entry(6, 0, &"casa")], [null])).collect_issues(), "Exceção 0 está vazia")


# Validação: as frases que o design lê no Inspector e no "Validar rotinas".
func _test_issues() -> void:
	var valid: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b", &"c"])
	_expect_true("Ronda completa não tem problema nenhum", valid.collect_issues().is_empty())

	var off_tick: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b"])
	off_tick.dwell_minutes = 25
	_expect_issue("Tempo fora do passo do relógio é apontado", off_tick.collect_issues(), "múltiplo")

	var single: NPCPatrol = _patrol(8, 17, 30, [&"a"])
	_expect_issue("Ronda de um ponto só é apontada", single.collect_issues(), "um ponto só")

	var no_scene: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b"])
	no_scene.scene_path = ""
	_expect_issue("Ronda sem cena é apontada", no_scene.collect_issues(), "não aponta cena")

	var too_short: NPCPatrol = _patrol(8, 9, 30, [&"a", &"b", &"c", &"d"])
	_expect_issue("Faixa curta demais pra passar por todos os pontos é apontada",
		too_short.collect_issues(), "só passa pelos 2 primeiros")

	var fits_exactly: NPCPatrol = _patrol(8, 10, 30, [&"a", &"b", &"c", &"d"])
	_expect_true("Faixa que dá tempo justo de passar por todos os pontos não reclama",
		fits_exactly.collect_issues().is_empty())


# Contas de faixa: sobreposição (em relógio de parede) e se ela cai dentro do dia jogável.
func _test_windows() -> void:
	var day: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b"])
	_expect_true("Faixas coladas não se sobrepõem", not day.overlaps(_patrol(17, 20, 30, [&"a", &"b"])))
	_expect_true("Faixas que se cruzam se sobrepõem", day.overlaps(_patrol(16, 18, 30, [&"a", &"b"])))
	_expect_true("A sobreposição é simétrica", _patrol(16, 18, 30, [&"a", &"b"]).overlaps(day))
	_expect_true("Faixa que atravessa a meia-noite sobrepõe uma que cai depois dela",
		_patrol(22, 2, 30, [&"a", &"b"]).overlaps(_patrol(1, 3, 30, [&"a", &"b"])))
	_expect_true("Faixa do dia inteiro sobrepõe qualquer outra", _patrol(6, 6, 30, [&"a", &"b"]).overlaps(day))

	# Dia jogável de 06:00 a 22:00 (960 minutos), o do TimeSettings de hoje.
	var day_length: int = 960
	_expect_true("Faixa que cabe no dia jogável é vivida", day.overlaps_playable_day(WAKE_HOUR, day_length))
	_expect_true("Faixa que começa antes do fim do dia é vivida, mesmo passando dele",
		_patrol(21, 23, 30, [&"a", &"b"]).overlaps_playable_day(WAKE_HOUR, day_length))
	_expect_true("Faixa que começa depois do fim do dia nunca é vivida",
		not _patrol(22, 23, 30, [&"a", &"b"]).overlaps_playable_day(WAKE_HOUR, day_length))
	_expect_true("Faixa da madrugada, toda depois do fim do dia, nunca é vivida",
		not _patrol(23, 5, 30, [&"a", &"b"]).overlaps_playable_day(WAKE_HOUR, day_length))
	_expect_true("Faixa que atravessa a hora de acordar é vivida pela parte da manhã",
		_patrol(5, 7, 30, [&"a", &"b"]).overlaps_playable_day(WAKE_HOUR, day_length))


# Cria uma entrada de rotina em memória.
func _entry(hour: int, minute: int, waypoint: StringName) -> NPCRoutineEntry:
	var entry: NPCRoutineEntry = NPCRoutineEntry.new()
	entry.hour = hour
	entry.minute = minute
	entry.scene_path = SCENE
	entry.waypoint = waypoint
	return entry


# Cria uma ronda em memória. O tempo de parada e os pontos são o que cada caso quer variar; os minutos
# de começo e de fim quase nunca, por isso vêm por último.
func _patrol(start_hour: int, end_hour: int, dwell: int, points: Array,
		start_minute: int = 0, end_minute: int = 0) -> NPCPatrol:
	var patrol: NPCPatrol = NPCPatrol.new()
	patrol.start_hour = start_hour
	patrol.start_minute = start_minute
	patrol.end_hour = end_hour
	patrol.end_minute = end_minute
	patrol.scene_path = SCENE
	patrol.dwell_minutes = dwell

	var typed_points: Array[StringName] = []
	for point: Variant in points:
		typed_points.append(point as StringName)
	patrol.waypoints = typed_points
	return patrol


# Cria um NPC em memória cuja rotina neutro/trabalho tem as entradas e as exceções dadas. Aceita null
# nas duas listas de propósito: a rotina precisa sobreviver a uma posição vazia no Inspector.
func _definition(entries: Array, exceptions: Array) -> NPCDefinition:
	var typed_entries: Array[NPCRoutineEntry] = []
	for entry: Variant in entries:
		typed_entries.append(entry as NPCRoutineEntry)

	var typed_exceptions: Array[NPCRoutineException] = []
	for exception: Variant in exceptions:
		typed_exceptions.append(exception as NPCRoutineException)

	var routine: NPCRoutine = NPCRoutine.new()
	routine.entries = typed_entries
	routine.exceptions = typed_exceptions

	var definition: NPCDefinition = NPCDefinition.new()
	definition.id = &"__selftest_npc"
	definition.work_weekdays = NPCDefinition.ALL_WEEKDAYS
	definition.routine_neutral_workday = routine
	return definition


# A rotina neutro/trabalho de um NPC de teste.
func _routine_of(definition: NPCDefinition) -> NPCRoutine:
	return definition.routine_neutral_workday


# A decisão do resolver pra um horário de relógio de parede, num dia de trabalho, emoção neutra.
func _decide(definition: NPCDefinition, hour: int, minute: int) -> NPCRoutineResolver.Decision:
	var minutes_into_day: int = posmod(hour * 60 + minute - WAKE_HOUR * 60, NPCRoutineEntry.MINUTES_PER_DAY)
	return NPCRoutineResolver.resolve(definition, NPCDefinition.EmotionSlot.NEUTRAL, 0, minutes_into_day, WAKE_HOUR)


# Confere onde a decisão manda o NPC.
func _expect_waypoint(label: String, decision: NPCRoutineResolver.Decision, expected: StringName) -> void:
	var actual: String = "nenhum lugar" if decision.entry == null else "\"%s\"" % decision.entry.waypoint
	_record(label, decision.entry != null and decision.entry.waypoint == expected,
		"esperado \"%s\", veio %s" % [expected, actual])


# Confere um texto.
func _expect_equal(label: String, actual: String, expected: String) -> void:
	_record(label, actual == expected, "esperado \"%s\", veio \"%s\"" % [expected, actual])


# Confere uma condição.
func _expect_true(label: String, condition: bool) -> void:
	_record(label, condition, "condição falsa")


# Confere que alguma frase da lista de problemas contém o trecho dado.
func _expect_issue(label: String, issues: PackedStringArray, fragment: String) -> void:
	var found: bool = false
	for issue: String in issues:
		if issue.contains(fragment):
			found = true
			break
	_record(label, found, "nenhum problema contém \"%s\" (veio: %s)" % [fragment, issues])


# Registra o resultado de um caso no relatório.
func _record(label: String, passed: bool, failure_detail: String) -> void:
	if passed:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
		return
	failed_count += 1
	_lines.append("  %s %s — %s" % [CROSS, label, failure_detail])
