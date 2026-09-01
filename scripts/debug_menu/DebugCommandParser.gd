# DebugCommandParser.gd — Converte uma linha digitada no Debug Console em tokens e valores
# tipados, usando os DebugParam declarados no registro. Função pura sobre texto: não sabe nada de
# DebugMenu, de UI ou de onde a linha veio.
class_name DebugCommandParser
extends RefCounted


# Resultado de bind_arguments(): ok indica sucesso; em erro, message explica o quê e values fica
# vazio.
class Result:
	var ok: bool = false
	var message: String = ""
	var values: Array = []


# Quebra a linha em tokens, respeitando aspas duplas para valores com espaço:
#   dar_item "semente de trigo" 5  →  ["dar_item", "semente de trigo", "5"]
static func tokenize(line: String) -> PackedStringArray:
	var tokens: PackedStringArray = PackedStringArray()
	var current: String = ""
	var has_current: bool = false
	var inside_quotes: bool = false
	for character: String in line:
		if character == "\"":
			inside_quotes = not inside_quotes
			has_current = true
			continue
		if character == " " and not inside_quotes:
			if has_current:
				tokens.append(current)
				current = ""
				has_current = false
			continue
		current += character
		has_current = true
	if has_current:
		tokens.append(current)
	return tokens


# Converte os tokens para os tipos declarados. Devolve um Result com ok/message/values.
static func bind_arguments(params: Array[DebugParam], tokens: PackedStringArray) -> Result:
	var result: Result = Result.new()
	if tokens.size() != params.size():
		result.message = "Esperado %d argumento(s), recebido %d." % [params.size(), tokens.size()]
		return result
	var values: Array = []
	for index: int in params.size():
		var param: DebugParam = params[index]
		var value: Variant = param.coerce(tokens[index])
		if value == null:
			result.message = "\"%s\" não é um %s válido para <%s>." % [tokens[index], param.type_name(), param.name]
			return result
		values.append(value)
	result.ok = true
	result.values = values
	return result


# Linha de uso, montada a partir dos DebugParam: "dar_ouro <quantidade:int>". Sai de graça do
# descritor, e não tem como ficar desatualizada porque é a mesma declaração que a UI usa.
static func usage_line(command: StringName, params: Array[DebugParam]) -> String:
	var parts: PackedStringArray = PackedStringArray([String(command)])
	for param: DebugParam in params:
		parts.append(param.usage_text())
	return " ".join(parts)
