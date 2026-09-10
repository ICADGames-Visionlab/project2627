# InsightCatalog.gd — Varredura dos recursos do sistema de insights: todos os .tres de insight e de
# cabeça, e as chaves declaradas no CSV de localização.
#
# Existe porque três lugares diferentes precisam da mesma varredura e não podem divergir: o
# HeadRegistry (que monta o elenco), o aviso de configuração da fonte (que confere text_key e
# head_id dentro do editor) e a validação em lote do menu de debug (que procura id repetido e porta
# morta no projeto inteiro).
#
# A leitura do CSV é feita à mão, e não pelo TranslationServer, de propósito: dentro do editor as
# traduções do jogo não estão carregadas, e o aviso de "chave que não existe" precisa aparecer
# exatamente ali, antes de rodar o jogo.
class_name InsightCatalog
extends RefCounted

const INSIGHTS_DIR: String = "res://resources/insights/"
const HEADS_DIR: String = "res://resources/heads/"
const TRANSLATIONS_CSV: String = "res://translations/translations.csv"

# Cache das chaves do CSV: a varredura roda a cada aviso de configuração de cada fonte da cena, e
# reler o arquivo em todas seria lento o bastante para travar o editor numa cena cheia.
static var _translation_keys: Dictionary = {}
static var _translation_keys_loaded: bool = false


# Todos os insights do projeto, em ordem de id. Ordem estável importa: é ela que faz o relatório de
# validação em lote sair igual entre execuções e render diff legível quando alguém o cola num PR.
static func load_all_insights() -> Array[InsightData]:
	var result: Array[InsightData] = []
	for resource: Resource in _load_folder(INSIGHTS_DIR):
		var insight: InsightData = resource as InsightData
		if insight != null:
			result.append(insight)
	result.sort_custom(_compare_insight_ids)
	return result


# Todas as cabeças do projeto, em ordem de id. A ordem também define o slot canônico de cada cabeça
# na órbita do jogador (ver HeadOrbitLayer), então mexer nela move orbes de lugar.
static func load_all_heads() -> Array[HeadData]:
	var result: Array[HeadData] = []
	for resource: Resource in _load_folder(HEADS_DIR):
		var head: HeadData = resource as HeadData
		if head != null:
			result.append(head)
	result.sort_custom(_compare_head_ids)
	return result


# Diz se a chave existe no translations.csv. Chave vazia devolve false: campo em branco é erro de
# preenchimento, não "sem tradução".
static func has_translation_key(key: String) -> bool:
	if key.is_empty():
		return false
	_ensure_translation_keys()
	return _translation_keys.has(key)


# Descarta o cache das chaves do CSV. Chamado pela validação em lote para que editar o CSV e rodar
# a validação de novo, sem reabrir o editor, dê a resposta atual.
static func clear_cache() -> void:
	_translation_keys.clear()
	_translation_keys_loaded = false


# Carrega todo .tres/.res de uma pasta. O trim_suffix(".remap") existe porque a exportação renomeia
# os recursos convertidos para .tres.remap — sem ele a varredura funciona no editor e devolve lista
# vazia na build.
static func _load_folder(dir_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		push_warning("[Insights] - AVISO: pasta \"%s\" não existe" % dir_path)
		return result
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean_name: String = file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres") and not clean_name.ends_with(".res"):
			continue
		var resource: Resource = ResourceLoader.load(dir_path + clean_name)
		if resource == null:
			push_warning("[Insights] - AVISO: falha ao carregar \"%s\"" % (dir_path + clean_name))
			continue
		result.append(resource)
	return result


# Lê a primeira coluna do translations.csv para dentro do cache. get_csv_line() cuida de aspas e
# vírgulas dentro do texto, então a linha de cabeçalho e as traduções com vírgula não confundem a
# leitura.
static func _ensure_translation_keys() -> void:
	if _translation_keys_loaded:
		return
	_translation_keys_loaded = true
	var file: FileAccess = FileAccess.open(TRANSLATIONS_CSV, FileAccess.READ)
	if file == null:
		push_warning("[Insights] - AVISO: não foi possível abrir \"%s\"" % TRANSLATIONS_CSV)
		return
	while not file.eof_reached():
		var columns: PackedStringArray = file.get_csv_line()
		if columns.is_empty():
			continue
		var key: String = columns[0].strip_edges()
		if not key.is_empty():
			_translation_keys[key] = true
	file.close()


# Comparador de insights por id, usado na ordenação da varredura.
static func _compare_insight_ids(left: InsightData, right: InsightData) -> bool:
	return String(left.id) < String(right.id)


# Comparador de cabeças por id, usado na ordenação da varredura.
static func _compare_head_ids(left: HeadData, right: HeadData) -> bool:
	return String(left.id) < String(right.id)
