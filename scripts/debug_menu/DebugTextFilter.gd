# DebugTextFilter.gd — Casador de texto usado pelo filtro do Debug Menu e pelo autocomplete do
# Debug Console. Um casador só, dois consumidores: é o mesmo princípio de "um registro, N
# front-ends" aplicado a busca.
class_name DebugTextFilter
extends RefCounted

const _ACCENTED: String = "áàâãäéèêëíìîïóòôõöúùûüçñ"
const _PLAIN: String = "aaaaaeeeeiiiiooooouuuucn"


# Normaliza para comparação: minúsculas e sem acento. O sem-acento não é capricho: os rótulos
# deste projeto são em português, e "camera" precisa achar "Câmera lenta" — quem está filtrando
# não vai parar para compor o circunflexo.
static func normalize(text: String) -> String:
	var lowered: String = text.to_lower()
	var result: String = ""
	for character: String in lowered:
		var accent_index: int = _ACCENTED.find(character)
		result += _PLAIN[accent_index] if accent_index >= 0 else character
	return result


# Pontua o quão bem needle casa com haystack (ambos já normalizados). -1 quando não casa.
static func score(haystack: String, needle: String) -> int:
	if needle.is_empty():
		return 0
	if haystack == needle:
		return 1000
	if haystack.begins_with(needle):
		return 800
	var substring_index: int = haystack.find(needle)
	if substring_index >= 0:
		var preceding: String = haystack[substring_index - 1] if substring_index > 0 else " "
		if preceding == " " or preceding == "_" or preceding == ".":
			return 600
		return 400
	return _score_subsequence(haystack, needle)


# Pontua como subsequência na ordem, penalizando buracos entre os caracteres casados. O piso em 0
# evita colidir com o -1 que sinaliza "não casa" em score().
static func _score_subsequence(haystack: String, needle: String) -> int:
	var search_from: int = 0
	var last_match_index: int = -1
	var gaps: int = 0
	for character: String in needle:
		var found_index: int = -1
		for index: int in range(search_from, haystack.length()):
			if haystack[index] == character:
				found_index = index
				break
		if found_index == -1:
			return -1
		if last_match_index >= 0:
			gaps += found_index - last_match_index - 1
		last_match_index = found_index
		search_from = found_index + 1
	return maxi(200 - gaps, 0)
