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
	_test_scene_paths()
	_test_baseline()
	_test_patrol()
	_test_next_change()
	_test_travel()
	_test_travel_consistency()
	_test_walk_seconds()
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


# O caminho de cena que o Inspector grava. Desde o Godot 4.4 um campo @export_file escolhido pelo seletor
# vira "uid://...", e o jogo compara "res://...": sem a conversão o NPC some de cena sem nenhum aviso.
func _test_scene_paths() -> void:
	_expect_equal("Caminho de cena comum passa direto", NPCRoutineEntry.to_scene_path(SCENE), SCENE)
	_expect_equal("Caminho de cena vazio passa direto", NPCRoutineEntry.to_scene_path(""), "")
	_expect_equal("UID que não existe passa direto, e nunca bate com uma cena em jogo",
		NPCRoutineEntry.to_scene_path("uid://__selftest_inexistente"), "uid://__selftest_inexistente")

	var scene_uid: String = ResourceUID.path_to_uid(SCENE)
	if not scene_uid.begins_with("uid://"):
		_skip("UID da cena vira o caminho dela", "a cena não tem UID neste checkout")
		return
	_expect_equal("UID da cena vira o caminho dela", NPCRoutineEntry.to_scene_path(scene_uid), SCENE)

	var by_uid: NPCRoutineEntry = _entry(8, 0, &"praca")
	by_uid.scene_path = scene_uid
	_expect_true("A descrição mostra o nome da cena, e não o UID", by_uid.describe().contains("City"))

	var patrol: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b"])
	patrol.scene_path = scene_uid
	_expect_true("A ronda com cena em UID também mostra o nome da cena", patrol.describe().contains("ronda em City"))


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

	# A rotina padrão continua correndo por baixo da ronda: quando a faixa acaba às 17:00, vale a entrada
	# que a rotina tem PARA AQUELE HORÁRIO (a das 11:55, quartel). "casa" seria o resultado de retomar a
	# entrada que valia quando a ronda abriu, às 08:00.
	_expect_waypoint("Ao fim da faixa vale a entrada da rotina para aquele horário, e não a de quando a faixa abriu",
		_decide(with_lunch, 17, 0), &"quartel")


# O tempo parado conta a partir da chegada: cada parada dura a caminhada até o ponto MAIS o tempo parado.
# A caminhada vem do TravelTimes (que em jogo o NPCDirector monta com o Pathfinder); aqui é uma tabela.
func _test_travel() -> void:
	# Ronda 08:00-17:00, 30 min parado, pontos a, b, c. A rotina padrão o deixa no "quartel" antes da faixa.
	var entries: Array = [_entry(6, 0, &"casa"), _entry(7, 30, &"quartel"), _entry(19, 0, &"casa")]
	var definition: NPCDefinition = _definition(entries, [_patrol(8, 17, 30, [&"a", &"b", &"c"])])
	var flat: NPCRoutineException.TravelTimes = _flat_travel(10)

	# Caminhada de 10 min entre pontos diferentes (inclusive do quartel até o primeiro ponto): cada parada
	# dura 40 min. Sem a caminhada, dura 30.
	_expect_waypoint("Com caminhada, a primeira parada dura a caminhada da origem mais o tempo parado",
		_decide_travel(definition, 8, 39, flat), &"a")
	_expect_waypoint("Só aos 40 min ele é mandado pro segundo ponto", _decide_travel(definition, 8, 40, flat), &"b")
	_expect_waypoint("Segunda parada: mais 40 min", _decide_travel(definition, 9, 19, flat), &"b")
	_expect_waypoint("Terceira parada", _decide_travel(definition, 9, 20, flat), &"c")
	_expect_waypoint("Ao fim da volta, o primeiro ponto volta (a caminhada agora vem do último)",
		_decide_travel(definition, 10, 0, flat), &"a")
	_expect_equal("O horário da parada é o de quando ele é mandado pra lá",
		_decide_travel(definition, 8, 45, flat).entry.format_clock(), "08:40")

	var decision: NPCRoutineResolver.Decision = _decide_travel(definition, 8, 10, flat)
	_expect_true("A próxima mudança conta a caminhada: daqui a 30 min, às 08:40, no segundo ponto",
		decision.next_entry.waypoint == &"b" and decision.minutes_until_next == 30
		and decision.next_entry.format_clock() == "08:40")

	decision = _decide_travel(definition, 16, 50, flat)
	_expect_true("O fim da faixa continua mandando: às 17:00 a rotina padrão volta, mesmo no meio da caminhada",
		decision.minutes_until_next == 10 and decision.next_entry.waypoint == &"quartel")

	# A origem: só conta se ele vinha de OUTRO ponto da mesma cena.
	var at_first: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), _entry(7, 30, &"a")], [_patrol(8, 17, 30, [&"a", &"b", &"c"])])
	_expect_waypoint("Já no primeiro ponto quando a faixa abre: a primeira parada dura só o tempo parado",
		_decide_travel(at_first, 8, 29, flat), &"a")
	_expect_waypoint("...e o segundo ponto vem aos 30 min", _decide_travel(at_first, 8, 30, flat), &"b")

	var came_from_inside: NPCRoutineEntry = _entry(7, 30, &"forno")
	came_from_inside.scene_path = "res://scenes/BakeryInterior.tscn"
	var from_other_scene: NPCDefinition = _definition(
		[_entry(6, 0, &"casa"), came_from_inside], [_patrol(8, 17, 30, [&"a", &"b", &"c"])])
	_expect_waypoint("Veio de outra cena: ele aparece no ponto, sem caminhada até ele",
		_decide_travel(from_other_scene, 8, 29, flat), &"a")
	_expect_waypoint("...e a segunda parada já começa aos 30 min", _decide_travel(from_other_scene, 8, 30, flat), &"b")

	# Caminhadas diferentes por trecho: quartel->a 10, a->b 10, b->c 20, c->a 30.
	var table: NPCRoutineException.TravelTimes = _table_travel({
		"quartel>a": 10, "a>b": 10, "b>c": 20, "c>a": 30})
	_expect_waypoint("Trechos diferentes: a primeira parada dura 40", _decide_travel(definition, 8, 39, table), &"a")
	_expect_waypoint("...a segunda começa aos 40 e dura 40", _decide_travel(definition, 9, 19, table), &"b")
	_expect_waypoint("...a terceira começa aos 80 e dura 50 (caminhada de 20)", _decide_travel(definition, 10, 9, table), &"c")
	_expect_waypoint("...a volta ao primeiro ponto começa aos 130 e dura 60 (caminhada de 30)",
		_decide_travel(definition, 10, 10, table), &"a")
	_expect_waypoint("...e a seguinte, já na segunda volta, aos 190", _decide_travel(definition, 11, 10, table), &"b")

	# A "próxima mudança" também usa a caminhada. Às 09:40 ele está no terceiro ponto (que dura até os 130),
	# e o próximo é o primeiro, às 10:10: sem caminhada a conta cairia no segundo ponto, então este caso
	# só passa se a caminhada entrar no cálculo do futuro e não só no do presente.
	decision = _decide_travel(definition, 9, 40, table)
	_expect_true("Com caminhadas diferentes, a próxima mudança é o primeiro ponto às 10:10, daqui a 30 min",
		decision.next_entry.waypoint == &"a" and decision.minutes_until_next == 30
		and decision.next_entry.format_clock() == "10:10")

	# Quantos pontos a faixa dá tempo de visitar: a caminhada tira tempo dela.
	var short: NPCPatrol = _patrol(8, 9, 30, [&"a", &"b", &"c"], 0, 20)
	_expect_true("Faixa de 80 min, sem contar a caminhada, passa pelos 3 pontos",
		short.count_visited_points(null) == 3)
	_expect_true("...contando 10 min de caminhada por parada (40 cada), o terceiro ponto não dá tempo",
		short.count_visited_points(flat.with_origin(SCENE, &"quartel")) == 2)


# As duas respostas do contrato (onde ele está, e quando muda) têm que concordar sobre onde cada parada
# começa e termina, em todos os minutos da faixa. Se divergissem, o menu de debug mentiria sobre a próxima
# mudança, e a agenda teria buracos que ninguém vê. É a conferência que pega erro de índice na conta das
# voltas, que o teste de um instante só não pega.
func _test_travel_consistency() -> void:
	var patrol: NPCPatrol = _patrol(8, 17, 30, [&"a", &"b", &"c", &"b"])
	var length: int = patrol.get_length_minutes()
	var travels: Array = [
		null, _flat_travel(10), _flat_travel(20),
		_table_travel({"a>b": 10, "b>c": 20, "c>b": 30, "b>a": 20, "quartel>a": 10}).with_origin(SCENE, &"quartel")]
	var problems: Array[String] = []

	for travel_index: int in travels.size():
		var travel: NPCRoutineException.TravelTimes = travels[travel_index] as NPCRoutineException.TravelTimes
		for elapsed: int in length:
			var until: int = patrol.get_minutes_until_stop_change(elapsed, travel)
			var here: NPCRoutineEntry = patrol.get_stop(elapsed, travel)
			if until <= 0 or here == null:
				problems.append("travel %d, minuto %d: until=%d" % [travel_index, elapsed, until])
				continue
			# Constante até o fim da parada...
			var last: NPCRoutineEntry = patrol.get_stop(elapsed + until - 1, travel)
			if not (last.is_same_place(here) and last.get_clock_minutes() == here.get_clock_minutes()):
				problems.append("travel %d, minuto %d: a parada muda antes do fim" % [travel_index, elapsed])
			# ...e outra parada (que começa exatamente aí) logo depois.
			var next: NPCRoutineEntry = patrol.get_stop(elapsed + until, travel)
			if next.get_clock_minutes() == here.get_clock_minutes():
				problems.append("travel %d, minuto %d: a parada não muda no fim" % [travel_index, elapsed])

	_record("get_stop e get_minutes_until_stop_change concordam em todos os minutos da faixa, com 4 caminhadas",
		problems.is_empty(), "; ".join(PackedStringArray(problems.slice(0, 3))))


# A conta do tempo de caminhada é a do movimento (Isometric.screen_velocity): mais lenta quanto mais vertical.
func _test_walk_seconds() -> void:
	_expect_true("Horizontal: 300 px a 200 px/s levam 1,5 s",
		is_equal_approx(Isometric.walk_seconds(Vector2.ZERO, PackedVector2Array([Vector2(300, 0)]), 200.0, 0.5, 0.75), 1.5))
	_expect_true("Vertical: 100 px a 200 px/s x 0,75 levam 0,667 s",
		absf(Isometric.walk_seconds(Vector2.ZERO, PackedVector2Array([Vector2(0, 100)]), 200.0, 0.5, 0.75) - 100.0 / 150.0) < 0.0001)
	_expect_true("Um caminho de dois trechos soma os dois",
		absf(Isometric.walk_seconds(Vector2.ZERO, PackedVector2Array([Vector2(300, 0), Vector2(300, 100)]), 200.0, 0.5, 0.75)
			- (1.5 + 100.0 / 150.0)) < 0.0001)
	_expect_true("Caminho vazio leva zero", Isometric.walk_seconds(Vector2.ZERO, PackedVector2Array(), 200.0, 0.5, 0.75) == 0.0)

	var nothing: NPCRoutineException.TravelTimes = NPCRoutineException.TravelTimes.new()
	_expect_true("TravelTimes sem lookup responde zero (não sabe, então não anda)", nothing.minutes(&"a", &"b") == 0)
	_expect_true("Mesmo ponto: zero", _flat_travel(10).minutes(&"a", &"a") == 0)
	_expect_true("Sem origem, a primeira parada não caminha", _flat_travel(10).minutes_from_origin(SCENE, &"a") == 0)


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


# Um TravelTimes de teste em que toda caminhada entre pontos diferentes leva `minutes` minutos.
func _flat_travel(minutes: int) -> NPCRoutineException.TravelTimes:
	return NPCRoutineException.TravelTimes.new(func(_from_id: StringName, _to_id: StringName) -> int:
		return minutes)


# Um TravelTimes de teste com a caminhada de cada trecho numa tabela "de>para" -> minutos (o que não
# está na tabela é zero).
func _table_travel(table: Dictionary) -> NPCRoutineException.TravelTimes:
	return NPCRoutineException.TravelTimes.new(func(from_id: StringName, to_id: StringName) -> int:
		return int(table.get("%s>%s" % [from_id, to_id], 0)))


# A decisão com o tempo de caminhada. Sem `travel` é um _decide igual ao de sempre. Usa os mesmos
# horários de relógio de parede; a origem da ronda o resolver descobre sozinho, da rotina padrão.
func _decide_travel(definition: NPCDefinition, hour: int, minute: int,
		travel: NPCRoutineException.TravelTimes = null) -> NPCRoutineResolver.Decision:
	var minutes_into_day: int = posmod(hour * 60 + minute - WAKE_HOUR * 60, NPCRoutineEntry.MINUTES_PER_DAY)
	return NPCRoutineResolver.resolve(
		definition, NPCDefinition.EmotionSlot.NEUTRAL, 0, minutes_into_day, WAKE_HOUR, travel)


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


# Registra um caso que não pôde rodar. Não conta como falha nem como acerto.
func _skip(label: String, reason: String) -> void:
	_lines.append("  - %s (pulado: %s)" % [label, reason])


# Registra o resultado de um caso no relatório.
func _record(label: String, passed: bool, failure_detail: String) -> void:
	if passed:
		passed_count += 1
		_lines.append("  %s %s" % [CHECK, label])
		return
	failed_count += 1
	_lines.append("  %s %s — %s" % [CROSS, label, failure_detail])
