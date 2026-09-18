# DialogueValidator.gd — "Validar conversas" (SPEC §15.2).
#
# D1 decidido: sem addon Godot Dialogue Manager. Roteiro real é um .dlg em res://dialogue/,
# convertido pelo DialogueScriptParser — erro de sintaxe vira Issue igual a qualquer outro problema.
# Confere as chaves fixas do sistema, as conversas sintéticas de debug (DialoguePrototypeData) e
# todo roteiro real (DialogueCatalog.list_script_ids()), com os mesmos critérios de conteúdo pros
# três: falante desconhecido, chave sem tradução, mais de 9 opções e fala acima de max_line_chars.
# Também confere o padrão de nome dos personagens: todo NPC do roster com alcunha no CSV.
class_name DialogueValidator
extends RefCounted

enum Severity { ERROR, WARNING }

const FIXED_KEYS: PackedStringArray = [
	"DIALOGUE_SPEAKER_PLAYER", "DIALOGUE_SPEAKER_SEPARATOR", "DIALOGUE_SPEAKER_EPITHET_FORMAT",
	"DIALOGUE_OPTION_FORMAT",
	"DIALOGUE_CONTINUE", "DIALOGUE_END", "DIALOGUE_NEW_LINES", "DIALOGUE_LOG_TRIMMED",
	"DIALOGUE_TAG_AUTHORITY",
]
const SYNTHETIC_IDS: PackedStringArray = ["__stress_text"]


class Issue:
	var severity: Severity
	var conversation_id: StringName
	var node_or_line_id: String
	var message: String

	func _init(p_severity: Severity, p_conversation_id: StringName, p_node_or_line_id: String,
			p_message: String) -> void:
		severity = p_severity
		conversation_id = p_conversation_id
		node_or_line_id = p_node_or_line_id
		message = p_message


static func run() -> Array[Issue]:
	var issues: Array[Issue] = []
	issues.append_array(_validate_fixed_keys())
	var rows: Dictionary = read_csv_rows()
	issues.append_array(_validate_npc_epithets(rows))
	var style: DialogueStyle = load("res://resources/dialogue/dialogue_style.tres")
	var resolver: DialogueSpeakerResolver = DialogueCatalog.make_default_resolver(style)
	for id: String in SYNTHETIC_IDS:
		var content: Dictionary = DialoguePrototypeData.get_content(StringName(id))
		issues.append_array(_validate_content(StringName(id), content, rows, style, resolver))
	for id: String in DialogueCatalog.list_script_ids():
		issues.append_array(_validate_script(StringName(id), rows, style, resolver))
	return issues


# Relatório pronto para print(), no formato dos outros validadores em lote do projeto (ver
# InsightDebugReport.project_report()).
static func report() -> String:
	var issues: Array[Issue] = run()
	var errors: int = 0
	var warnings: int = 0
	var lines: PackedStringArray = []
	for issue: Issue in issues:
		var label: String = "%s/%s" % [issue.conversation_id, issue.node_or_line_id] \
			if issue.conversation_id != &"" else issue.node_or_line_id
		if issue.severity == Severity.ERROR:
			errors += 1
			lines.append("  ✗ %s — %s" % [label, issue.message])
		else:
			warnings += 1
			lines.append("  ✗ %s — %s (aviso)" % [label, issue.message])
	if issues.is_empty():
		lines.append("  ✓ Nenhum problema encontrado.")
	var script_count: int = DialogueCatalog.list_script_ids().size()
	var summary: String = "[Dialogue] - Validação: %d erro(s), %d aviso(s) em %d conversa(s) sintética(s) e %d roteiro(s) real(is)" % [
		errors, warnings, SYNTHETIC_IDS.size(), script_count
	]
	return summary + "\n" + "\n".join(lines)


# Faz o parser do .dlg e roda os mesmos critérios de conteúdo da conversa sintética; erro de
# sintaxe vira Issue de ERROR (sem node_id — o próprio parser já aponta a linha na mensagem).
static func _validate_script(conversation_id: StringName, rows: Dictionary, style: DialogueStyle,
		resolver: DialogueSpeakerResolver) -> Array[Issue]:
	var path: String = DialogueCatalog.get_script_path(conversation_id)
	var source: String = FileAccess.get_file_as_string(path)
	var result: DialogueScriptParser.Result = DialogueScriptParser.parse(source, conversation_id)
	if not result.ok():
		var issues: Array[Issue] = []
		for error: DialogueScriptParser.ParseError in result.errors:
			issues.append(Issue.new(Severity.ERROR, conversation_id, "", str(error)))
		return issues
	return _validate_content(conversation_id, result.content, rows, style, resolver)


static func _validate_fixed_keys() -> Array[Issue]:
	var issues: Array[Issue] = []
	var rows: Dictionary = read_csv_rows()
	if rows.is_empty():
		issues.append(Issue.new(Severity.ERROR, &"", "translations.csv", "não foi possível ler o CSV"))
		return issues
	for key: String in FIXED_KEYS:
		if not rows.has(key):
			issues.append(Issue.new(Severity.ERROR, &"", key, "chave ausente no CSV"))
			continue
		var columns: PackedStringArray = rows[key]
		for column: int in range(1, columns.size()):
			if columns[column].strip_edges() == "":
				issues.append(Issue.new(Severity.ERROR, &"", key, "coluna %d vazia" % column))
	return issues


# Padrão "Nome, Alcunha" (DialogueSpeakerResolver.EPITHET_KEY_SUFFIX): todo NPC do roster precisa
# da linha <name_key>_ALCUNHA no CSV. Aviso, não erro — sem ela o diálogo ainda funciona, só mostra
# o nome sozinho.
static func _validate_npc_epithets(rows: Dictionary) -> Array[Issue]:
	var issues: Array[Issue] = []
	var roster: NPCRoster = load(DialogueCatalog.NPC_ROSTER_PATH)
	if roster == null or rows.is_empty():
		return issues
	for definition: NPCDefinition in roster.npcs:
		if definition == null or definition.name_key == &"":
			continue
		var epithet_key: String = DialogueSpeakerResolver.epithet_key_for(String(definition.name_key))
		if not rows.has(epithet_key):
			issues.append(Issue.new(Severity.WARNING, &"", "npc:%s" % definition.id,
				"sem alcunha: chave \"%s\" ausente no CSV" % epithet_key))
	return issues


# Confere um conteúdo já no formato do MemoryRunner (§15.6), venha de conversa sintética ou de
# roteiro real já parseado: chave ausente no CSV, falante desconhecido, mais de 9 opções e fala
# acima de max_line_chars.
static func _validate_content(conversation_id: StringName, content: Dictionary, rows: Dictionary,
		style: DialogueStyle, resolver: DialogueSpeakerResolver) -> Array[Issue]:
	var issues: Array[Issue] = []
	var nodes: Dictionary = content.get("nodes", {})
	for node_id: Variant in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if node.has("line"):
			var raw: Array = node["line"]
			var speaker_id: StringName = raw[1]
			var text_key: String = raw[2]
			_check_key(issues, rows, conversation_id, node_id, text_key)
			_check_length(issues, rows, style, conversation_id, node_id, text_key)
			if resolver.resolve(speaker_id).kind == DialogueSpeakerResolver.Kind.UNKNOWN:
				issues.append(Issue.new(Severity.WARNING, conversation_id, str(node_id),
					"falante \"%s\" desconhecido" % speaker_id))
		var choices: Array = node.get("choices", [])
		for choice: Dictionary in choices:
			for field: String in ["text", "tag", "reason"]:
				_check_key(issues, rows, conversation_id, node_id, choice.get(field, ""))
		if choices.size() > DialogueChoiceLayout.MAX_SHORTCUTS:
			issues.append(Issue.new(Severity.ERROR, conversation_id, str(node_id),
				"%d opções, mais de %d possíveis" % [choices.size(), DialogueChoiceLayout.MAX_SHORTCUTS]))
	return issues


static func _check_key(issues: Array[Issue], rows: Dictionary, conversation_id: StringName,
		node_id: Variant, key: String) -> void:
	if key == "" or rows.has(key):
		return
	issues.append(Issue.new(Severity.ERROR, conversation_id, str(node_id), "chave \"%s\" ausente no CSV" % key))


static func _check_length(issues: Array[Issue], rows: Dictionary, style: DialogueStyle,
		conversation_id: StringName, node_id: Variant, text_key: String) -> void:
	if not rows.has(text_key):
		return
	var columns: PackedStringArray = rows[text_key]
	for column: int in range(1, columns.size()):
		var plain: String = DialogueRevealTimer.strip_bbcode(columns[column])
		if plain.length() > style.max_line_chars:
			issues.append(Issue.new(Severity.WARNING, conversation_id, str(node_id),
				"fala \"%s\" com %d caracteres (máximo %d)" % [text_key, plain.length(), style.max_line_chars]))


# Lê o CSV inteiro para um dicionário chave -> colunas, para não reabrir o arquivo a cada chave
# checada (ver o mesmo cuidado em InsightCatalog._ensure_translation_keys()). Público porque o
# __stress_text (DialoguePrototypeData) também varre o CSV inteiro.
static func read_csv_rows() -> Dictionary:
	var file: FileAccess = FileAccess.open(InsightCatalog.TRANSLATIONS_CSV, FileAccess.READ)
	if file == null:
		return {}
	var rows: Dictionary = {}
	var is_header: bool = true
	while not file.eof_reached():
		var columns: PackedStringArray = file.get_csv_line()
		if columns.is_empty() or columns[0].strip_edges() == "":
			continue
		if is_header:
			is_header = false
			continue
		rows[columns[0]] = columns
	file.close()
	return rows
