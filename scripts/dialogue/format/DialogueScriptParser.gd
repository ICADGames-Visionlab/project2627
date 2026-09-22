# DialogueScriptParser.gd — Lê um roteiro de texto (res://dialogue/<id>.dlg) e devolve o mesmo
# formato de Dictionary que o MemoryRunner já consome (documentado em MemoryRunner.gd). Sem addon
# (D1 decidido: não vamos usar o Godot Dialogue Manager): este é o formato próprio de roteiro,
# num estilo Ink/Yarn simplificado, pensado pra descrever a estrutura da conversa (nós, falas,
# opções, condições) — não pra guardar texto.
#
# Formato (ver docs/sistema_de_dialogo/referencia.md para a sintaxe completa). O parser lê uma linha
# por vez: cada fala, opção e "=>" cabe numa linha só.
#
#   participants: ze ana
#
#   == n1 ==
#   ze: ZE_BOM_DIA_01
#
#   - ZE_BOM_DIA_OPT_FIADO [tag:DIALOGUE_TAG_AUTHORITY if:tem_distintivo show_disabled reason:ZE_BOM_DIA_SEM_DISTINTIVO grant:ze_deu_fiado] => n_fiado
#   - ZE_BOM_DIA_OPT_SAIR => END
#
#   == n_fiado ==
#   ze: ZE_BOM_DIA_02
#
# Fala, opção, tag e motivo são sempre uma CHAVE de translations.csv (CAIXA_ALTA_COM_UNDERSCORE),
# igual ao resto do projeto — nunca texto literal. Quem escreve cadastra a chave e o texto no CSV
# do jeito de sempre; o roteiro só descreve a estrutura. Um valor que não parece chave (minúsculo,
# com espaço) é erro de sintaxe, pego aqui — é o erro mais barato de dar, porque o mais caro é essa
# mesma confusão aparecer como "texto errado na tela" duas telas depois.
#
# Duas ou mais falas seguidas no mesmo nó viram uma corrente de nós sintéticos (n1, n1__2, n1__3...)
# encadeados por "Continuar" — assim quem escreve não precisa inventar um nó pra cada troca de fala.
#
# A linha "participants:", antes do primeiro nó, declara o ELENCO: os NPCs que estão na roda de
# conversa junto com o jogador. É o que permite os dois serem segurados, virarem pro jogador,
# entrarem no enquadramento da câmera e terem retrato na tela — nada disso dá pra deduzir das falas,
# porque um NPC pode estar presente e calado num galho inteiro da conversa.
class_name DialogueScriptParser
extends RefCounted

# Quantos NPCs uma conversa aceita. O jogador mais dois: é o que a coluna de retratos mostra e o
# que o enquadramento da câmera consegue manter legível. Subir este número é revisar os dois.
const MAX_PARTICIPANTS: int = 2

# Palavra-chave do elenco, no começo da linha e só antes do primeiro nó.
const PARTICIPANTS_KEYWORD: String = "participants:"

const _HEADER_REGEX_PATTERN: String = "^==\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*==$"
const _SPEAKER_REGEX_PATTERN: String = "^([a-zA-Z_][a-zA-Z0-9_]*(?::[a-zA-Z_][a-zA-Z0-9_]*)?):\\s+(.+)$"
const _KEY_REGEX_PATTERN: String = "^[A-Z][A-Z0-9_]*$"
const _NPC_ID_REGEX_PATTERN: String = "^[a-zA-Z_][a-zA-Z0-9_]*$"


class ParseError:
	var line: int
	var message: String

	func _init(p_line: int, p_message: String) -> void:
		line = p_line
		message = p_message

	func _to_string() -> String:
		return "linha %d: %s" % [line, message] if line > 0 else message


class Result:
	var content: Dictionary = {}
	var errors: Array[ParseError] = []

	func ok() -> bool:
		return errors.is_empty()


static func parse(source: String, conversation_id: StringName) -> Result:
	var result := Result.new()
	var header_regex := RegEx.new()
	header_regex.compile(_HEADER_REGEX_PATTERN)
	var speaker_regex := RegEx.new()
	speaker_regex.compile(_SPEAKER_REGEX_PATTERN)

	var nodes: Dictionary = {}          # StringName -> Dictionary (formato do MemoryRunner)
	var node_order: Array[StringName] = []
	var seen_node_ids: Dictionary = {}  # StringName -> true
	var participants: Array[StringName] = []
	var participants_declared: bool = false

	var current_node_id: StringName = &""
	var current_header_line: int = 0
	var current_speaker_lines: Array = []   # [[speaker_id: StringName, key: String, line: int], ...]
	var current_choices: Array = []          # Array[Dictionary]
	var current_goto: Dictionary = {}        # {"next": StringName, "auto": bool} ou {}

	var lines: PackedStringArray = source.split("\n")
	for i: int in lines.size():
		var line_no: int = i + 1
		var trimmed: String = lines[i].strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue

		var header_match: RegExMatch = header_regex.search(trimmed)
		if header_match != null:
			_flush_node(current_node_id, current_header_line, current_speaker_lines, current_choices,
				current_goto, nodes, node_order, seen_node_ids, result)
			current_node_id = StringName(header_match.get_string(1))
			current_header_line = line_no
			current_speaker_lines = []
			current_choices = []
			current_goto = {}
			continue

		if trimmed.begins_with(PARTICIPANTS_KEYWORD):
			if current_node_id != &"":
				result.errors.append(ParseError.new(line_no,
					"\"participants:\" só vale antes do primeiro \"== nó ==\""))
			elif participants_declared:
				result.errors.append(ParseError.new(line_no,
					"\"participants:\" repetido — declare o elenco inteiro numa linha só"))
			else:
				participants_declared = true
				participants = _parse_participants(trimmed, line_no, result)
			continue

		if current_node_id == &"":
			result.errors.append(ParseError.new(line_no, "conteúdo antes do primeiro \"== nó ==\""))
			continue

		if trimmed.begins_with("-"):
			if not current_goto.is_empty():
				result.errors.append(ParseError.new(line_no, "opção depois de \"=>\" no mesmo nó"))
				continue
			var choice: Dictionary = _parse_choice(trimmed, line_no, conversation_id, result)
			if not choice.is_empty():
				current_choices.append(choice)
			continue

		if trimmed.begins_with("=>"):
			if not current_choices.is_empty():
				result.errors.append(ParseError.new(line_no, "\"=>\" depois de opções — um nó com opções não avança sozinho"))
				continue
			current_goto = _parse_goto(trimmed, line_no, result)
			continue

		if not current_choices.is_empty() or not current_goto.is_empty():
			result.errors.append(ParseError.new(line_no, "fala depois de opções/avanço não é permitida neste nó"))
			continue

		var speaker_match: RegExMatch = speaker_regex.search(trimmed)
		if speaker_match != null:
			var key: String = _validate_key(speaker_match.get_string(2), line_no, result)
			current_speaker_lines.append([StringName(speaker_match.get_string(1)), key])
		else:
			var key: String = _validate_key(trimmed, line_no, result)
			current_speaker_lines.append([&"", key])

	_flush_node(current_node_id, current_header_line, current_speaker_lines, current_choices,
		current_goto, nodes, node_order, seen_node_ids, result)

	if node_order.is_empty():
		result.errors.append(ParseError.new(0, "nenhum nó (\"== id ==\") encontrado no roteiro"))
		return result

	_validate_targets(nodes, result)
	if result.ok():
		result.content = { "start": node_order[0], "nodes": nodes, "participants": participants }
	return result


# Só o elenco, sem montar a conversa inteira: quem clica num NPC precisa saber quem mais entra na
# roda ANTES de a tela abrir, para segurar os dois e enquadrar a câmera neles (NPCInteraction).
# Erros de sintaxe são ignorados aqui de propósito — quem reclama deles é o parse() completo, na
# hora de abrir a conversa, e o "Validar conversas".
static func parse_participants(source: String) -> Array[StringName]:
	var discard := Result.new()
	for line: String in source.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("=="):
			break
		if trimmed.begins_with(PARTICIPANTS_KEYWORD):
			return _parse_participants(trimmed, 0, discard)
	return []


# "participants: ze ana" (vírgula também separa) -> [&"ze", &"ana"]. Só valida a FORMA do id; se o
# NPC existe no roster é o "Validar conversas" que confere, porque o parser não abre recurso nenhum.
static func _parse_participants(trimmed: String, line_no: int, result: Result) -> Array[StringName]:
	var participants: Array[StringName] = []
	var body: String = trimmed.substr(PARTICIPANTS_KEYWORD.length()).replace(",", " ").strip_edges()
	var id_regex := RegEx.new()
	id_regex.compile(_NPC_ID_REGEX_PATTERN)

	for raw_id: String in body.split(" ", false):
		if id_regex.search(raw_id) == null:
			result.errors.append(ParseError.new(line_no,
				"\"%s\" não parece um id de NPC (esperado o id do NPCDefinition, ex.: ze)" % raw_id))
			continue
		var id := StringName(raw_id)
		if participants.has(id):
			result.errors.append(ParseError.new(line_no, "NPC \"%s\" repetido em \"participants:\"" % id))
			continue
		participants.append(id)

	if participants.is_empty():
		result.errors.append(ParseError.new(line_no,
			"\"participants:\" sem nenhum id de NPC — escreva \"participants: ze ana\" ou apague a linha"))
	elif participants.size() > MAX_PARTICIPANTS:
		result.errors.append(ParseError.new(line_no, "%d NPCs na conversa, no máximo %d" % [
			participants.size(), MAX_PARTICIPANTS]))
	return participants


static func _flush_node(node_id: StringName, header_line: int, speaker_lines: Array, choices: Array,
		goto: Dictionary, nodes: Dictionary, node_order: Array[StringName],
		seen_node_ids: Dictionary, result: Result) -> void:
	if node_id == &"":
		return
	if seen_node_ids.has(node_id):
		result.errors.append(ParseError.new(header_line, "nó \"%s\" repetido" % node_id))
		return
	seen_node_ids[node_id] = true
	_emit_chain(node_id, speaker_lines, choices, goto, nodes, node_order)


# Uma fala só = um nó. Duas ou mais no mesmo "== nó ==" viram uma corrente de nós sintéticos
# (id, id__2, id__3...), cada um com uma fala e avanço "Continuar" pro seguinte; opções/"=>" do
# roteiro só valem para o último elo da corrente.
static func _emit_chain(node_id: StringName, speaker_lines: Array, choices: Array, goto: Dictionary,
		nodes: Dictionary, node_order: Array[StringName]) -> void:
	if speaker_lines.is_empty():
		nodes[node_id] = _tail_fields(choices, goto)
		node_order.append(node_id)
		return
	for i: int in speaker_lines.size():
		var this_id: StringName = node_id if i == 0 else StringName("%s__%d" % [node_id, i + 1])
		var is_last: bool = i == speaker_lines.size() - 1
		var speaker_id: StringName = speaker_lines[i][0]
		var text_key: String = speaker_lines[i][1]
		var node_dict: Dictionary = { "line": [StringName(text_key), speaker_id, text_key] }
		if is_last:
			node_dict.merge(_tail_fields(choices, goto))
		else:
			node_dict["next"] = StringName("%s__%d" % [node_id, i + 2])
		nodes[this_id] = node_dict
		node_order.append(this_id)


static func _tail_fields(choices: Array, goto: Dictionary) -> Dictionary:
	if not choices.is_empty():
		return { "choices": choices }
	if not goto.is_empty():
		var fields: Dictionary = { "next": goto["next"] }
		if goto.get("auto", false):
			fields["advance"] = "auto"
		return fields
	return {}   # nem opções nem "=>": MemoryRunner trata como fim (mostra "Encerrar")


static func _parse_choice(trimmed: String, line_no: int, conversation_id: StringName, result: Result) -> Dictionary:
	var body: String = trimmed.substr(1).strip_edges()
	var arrow_at: int = body.rfind("=>")
	if arrow_at == -1:
		result.errors.append(ParseError.new(line_no, "opção sem \"=> destino\""))
		return {}
	var target: String = body.substr(arrow_at + 2).strip_edges()
	if target == "":
		result.errors.append(ParseError.new(line_no, "opção sem destino depois de \"=>\""))
		return {}
	var head: String = body.substr(0, arrow_at).strip_edges()

	var text: String = head
	var attrs: Dictionary = {}
	var bracket_at: int = head.rfind("[")
	if bracket_at != -1 and head.ends_with("]"):
		attrs = _parse_attrs(head.substr(bracket_at + 1, head.length() - bracket_at - 2))
		text = head.substr(0, bracket_at).strip_edges()
	if text == "":
		result.errors.append(ParseError.new(line_no, "opção sem texto"))
		return {}

	# Prefixado pela conversa: choice_id é a chave de "já escolhida antes" em DialogueState, que não
	# distingue conversa nenhuma — sem o prefixo, duas conversas reaproveitando a mesma chave de
	# texto (ex.: um "Sim." genérico) marcariam a escolha uma da outra como já feita.
	var choice: Dictionary = {
		"id": StringName("%s:%s" % [conversation_id, text]),
		"text": _validate_key(text, line_no, result),
		"next": StringName(target),
	}
	if attrs.has("tag"):
		choice["tag"] = _validate_attr_key(attrs["tag"], line_no, result)
	if attrs.has("if"):
		choice["if_flag"] = StringName(String(attrs["if"]))
	if attrs.has("show_disabled"):
		choice["show_disabled"] = true
	if attrs.has("reason"):
		choice["reason"] = _validate_attr_key(attrs["reason"], line_no, result)
	if attrs.has("grant"):
		choice["grant"] = StringName(String(attrs["grant"]))
	return choice


static func _parse_goto(trimmed: String, line_no: int, result: Result) -> Dictionary:
	var body: String = trimmed.substr(2).strip_edges()
	var attrs: Dictionary = {}
	var bracket_at: int = body.rfind("[")
	if bracket_at != -1 and body.ends_with("]"):
		attrs = _parse_attrs(body.substr(bracket_at + 1, body.length() - bracket_at - 2))
		body = body.substr(0, bracket_at).strip_edges()
	if body == "":
		result.errors.append(ParseError.new(line_no, "\"=>\" sem destino"))
		return {}
	return { "next": StringName(body), "auto": attrs.get("auto", false) }


# Fala, opção, tag e motivo são sempre chave do CSV (CAIXA_ALTA_COM_UNDERSCORE) — nunca texto
# literal. Pega aqui o erro mais comum (colar o texto direto) com uma mensagem que diz o que fazer,
# em vez de deixar a chave errada virar "texto estranho na tela" duas telas depois.
static func _validate_key(value: String, line_no: int, result: Result) -> String:
	var key_regex := RegEx.new()
	key_regex.compile(_KEY_REGEX_PATTERN)
	if key_regex.search(value) == null:
		result.errors.append(ParseError.new(line_no,
			"\"%s\" não parece uma chave de translations.csv (esperado CAIXA_ALTA_COM_UNDERSCORE) — cadastre o texto no CSV e use a chave aqui" % value))
	return value


static func _validate_attr_key(value: Variant, line_no: int, result: Result) -> String:
	if not (value is String):
		result.errors.append(ParseError.new(line_no, "atributo precisa de um valor (ex.: tag:ALGO)"))
		return ""
	return _validate_key(value, line_no, result)


# key:valor ou key:"valor com espaço", separados por espaço; key sozinha (sem ":") é uma bandeira
# (ex.: show_disabled). Não suporta aspas escapadas dentro do valor — não precisou até agora.
static func _parse_attrs(text: String) -> Dictionary:
	var attrs: Dictionary = {}
	var i: int = 0
	var n: int = text.length()
	while i < n:
		while i < n and text[i] == " ":
			i += 1
		if i >= n:
			break
		var key_start: int = i
		while i < n and text[i] != ":" and text[i] != " ":
			i += 1
		var key: String = text.substr(key_start, i - key_start)
		if i < n and text[i] == ":":
			i += 1
			if i < n and text[i] == "\"":
				i += 1
				var value_start: int = i
				while i < n and text[i] != "\"":
					i += 1
				attrs[key] = text.substr(value_start, i - value_start)
				i += 1
			else:
				var value_start: int = i
				while i < n and text[i] != " ":
					i += 1
				attrs[key] = text.substr(value_start, i - value_start)
		else:
			attrs[key] = true
	return attrs


static func _validate_targets(nodes: Dictionary, result: Result) -> void:
	for node_id: StringName in nodes.keys():
		var node: Dictionary = nodes[node_id]
		for choice: Dictionary in node.get("choices", []):
			var target: StringName = choice["next"]
			if target != &"END" and not nodes.has(target):
				result.errors.append(ParseError.new(0,
					"nó \"%s\": opção \"%s\" aponta para \"%s\", que não existe" % [node_id, choice["id"], target]))
		if node.has("next"):
			var target: StringName = node["next"]
			if target != &"END" and not nodes.has(target):
				result.errors.append(ParseError.new(0, "nó \"%s\" avança para \"%s\", que não existe" % [node_id, target]))
