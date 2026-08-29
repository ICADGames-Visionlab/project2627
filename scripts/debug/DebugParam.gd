# DebugParam.gd — Descritor de um parâmetro de uma ação de debug.
#
# Guarda o QUE o parâmetro é (tipo, faixa, opções, valor atual), nunca COMO ele é exibido. É essa
# separação que permite o menu escolher um SpinBox e o console escolher uma conversão de texto a
# partir da mesma declaração — e é o que garante que os dois nunca divirjam.
class_name DebugParam
extends RefCounted

enum Type { INT, FLOAT, STRING, BOOL, ENUM }

var name: String = ""
var type: Type = Type.INT
# Valor atual. Vive aqui (no registro, que é do Autoload) e não no widget, para sobreviver a
# fechar e reabrir o menu: o "500" que o operador acabou de digitar continua lá.
var value: Variant = 0
var min_value: float = 0.0
var max_value: float = 0.0
var step: float = 1.0
# Desenha um HSlider ao lado do campo. Só faz sentido com faixa finita; útil para ajuste contínuo
# (velocidade, escala de tempo), atrapalha para quantidade discreta.
var use_slider: bool = false
# Opções do tipo ENUM. O Callable recebe o ÍNDICE selecionado, não o texto — o índice mapeia
# direto para um enum de GDScript do lado do sistema.
var options: PackedStringArray = PackedStringArray()
# Callable sem argumento que devolve PackedStringArray com os valores válidos no momento. Existe
# para o caso em que a lista só é conhecida em runtime (ids de item, nomes de cena): assar a lista
# no registro faria ela apodrecer na primeira vez que o catálogo mudasse.
var suggestions_provider: Callable = Callable()


static func int_value(p_name: String, p_default: int, p_min: int = -999999, p_max: int = 999999, p_step: int = 1) -> DebugParam:
	var param: DebugParam = DebugParam.new()
	param.name = p_name
	param.type = Type.INT
	param.value = p_default
	param.min_value = p_min
	param.max_value = p_max
	param.step = p_step
	return param


static func float_value(p_name: String, p_default: float, p_min: float = 0.0, p_max: float = 100.0, p_step: float = 0.1) -> DebugParam:
	var param: DebugParam = DebugParam.new()
	param.name = p_name
	param.type = Type.FLOAT
	param.value = p_default
	param.min_value = p_min
	param.max_value = p_max
	param.step = p_step
	return param


static func string_value(p_name: String, p_default: String = "", p_suggestions: Callable = Callable()) -> DebugParam:
	var param: DebugParam = DebugParam.new()
	param.name = p_name
	param.type = Type.STRING
	param.value = p_default
	param.suggestions_provider = p_suggestions
	return param


static func bool_value(p_name: String, p_default: bool = false) -> DebugParam:
	var param: DebugParam = DebugParam.new()
	param.name = p_name
	param.type = Type.BOOL
	param.value = p_default
	return param


static func enum_value(p_name: String, p_options: PackedStringArray, p_default_index: int = 0) -> DebugParam:
	var param: DebugParam = DebugParam.new()
	param.name = p_name
	param.type = Type.ENUM
	param.options = p_options
	param.value = p_default_index
	return param


# Converte um token de texto do console para o tipo declarado. Devolve null quando o token não
# serve — assim o chamador distingue "token inválido" de "valor válido que por acaso é 0 ou false".
func coerce(token: String) -> Variant:
	match type:
		Type.INT:
			return token.to_int() if token.is_valid_int() else null
		Type.FLOAT:
			return token.to_float() if token.is_valid_float() else null
		Type.STRING:
			return token
		Type.BOOL:
			var lowered: String = token.to_lower()
			if lowered in ["1", "true", "sim", "on"]:
				return true
			if lowered in ["0", "false", "nao", "não", "off"]:
				return false
			return null
		Type.ENUM:
			for index: int in options.size():
				if options[index].nocasecmp_to(token) == 0:
					return index
			return null
	return null


# Nome legível do tipo, usado nas mensagens de erro do parser e do console.
func type_name() -> String:
	return ["int", "float", "string", "bool", "enum"][type]


# Assinatura legível do parâmetro, usada na linha de uso do console: "<quantidade:int>".
func usage_text() -> String:
	return "<%s:%s>" % [name, type_name()]


# Lista de valores sugeridos agora: options para ENUM, suggestions_provider para o resto.
func get_suggestions() -> PackedStringArray:
	if type == Type.ENUM:
		return options
	if suggestions_provider.is_valid():
		return suggestions_provider.call()
	return PackedStringArray()
