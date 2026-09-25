# ProfilingCatalog.gd — Varredura dos recursos do profiling: os perfis dos NPCs, as palavras e as
# categorias do glossário.
#
# Existe pelo mesmo motivo do InsightCatalog: três lugares precisam da mesma varredura e não podem
# divergir — a tela do espírito (que acha o perfil pelo id do NPC), o glossário (que reconstrói uma
# palavra a partir do id que veio do save) e a validação em lote do menu de debug (que procura id
# repetido, chave inexistente no CSV e perfil de NPC que não está no roster).
#
# O CACHE: um perfil é lido a cada abertura de espírito e a cada consulta do glossário. Varrer a
# pasta toda vez seria relê-la dezenas de vezes por sonho, então a varredura acontece uma vez e fica
# guardada. "Recarregar catálogo" no menu de debug (F4) descarta o cache, pra editar um .tres e ver
# o resultado sem reabrir o jogo.
#
# A checagem de chave do CSV é emprestada do InsightCatalog: é a mesma leitura, do mesmo arquivo,
# pelo mesmo motivo (dentro do editor as traduções não estão carregadas). Duplicá-la aqui só criaria
# dois caches do mesmo arquivo pra alguém esquecer de limpar.
#
# O guia completo está em docs/sistema_de_profiling.md.
class_name ProfilingCatalog
extends RefCounted

const PROFILES_DIR: String = "res://resources/profiling/npcs/"
const WORDS_DIR: String = "res://resources/profiling/palavras/"
const CATEGORIES_DIR: String = "res://resources/profiling/categorias/"

static var _profiles: Array[NPCProfile] = []
static var _words: Array[GlossaryWord] = []
static var _categories: Array[GlossaryCategory] = []
static var _loaded: bool = false


# Todos os perfis do projeto, em ordem de id de NPC. Ordem estável importa: é ela que faz o relatório
# da validação em lote sair igual entre execuções e render diff legível quando alguém o cola num PR.
static func load_all_profiles() -> Array[NPCProfile]:
	_ensure_loaded()
	return _profiles


# Todas as palavras do projeto, em ordem de id. Inclui as palavras soltas da pasta e as que só
# aparecem no pool de algum perfil — o glossário precisa achar qualquer uma pelo id do save.
static func load_all_words() -> Array[GlossaryWord]:
	_ensure_loaded()
	return _words


# Todas as categorias do projeto, na ordem de exibição (sort_order, e o id como desempate).
static func load_all_categories() -> Array[GlossaryCategory]:
	_ensure_loaded()
	return _categories


# O perfil de um NPC, ou null se ele não tem profiling. Null não é erro: NPC sem perfil é NPC que
# ainda não tem história escrita, e o espírito dele simplesmente não abre.
static func find_profile(npc_id: StringName) -> NPCProfile:
	_ensure_loaded()
	for profile: NPCProfile in _profiles:
		if profile.npc_id == npc_id:
			return profile
	return null


# A palavra de um id, de qualquer perfil, ou null.
static func find_word(word_id: StringName) -> GlossaryWord:
	_ensure_loaded()
	for word: GlossaryWord in _words:
		if word.id == word_id:
			return word
	return null


# Os perfis em que uma palavra aparece. É o que resolve "essa palavra vai pro glossário de quem?"
# quando a descoberta não diz o NPC (ver ProfilingJournal.discover_word).
static func find_profiles_with_word(word_id: StringName) -> Array[NPCProfile]:
	var result: Array[NPCProfile] = []
	for profile: NPCProfile in load_all_profiles():
		if profile.find_word(word_id) != null:
			result.append(profile)
	return result


# Todas as palavras que vêm junto com uma, incluindo ela mesma: o grupo das palavras em conjunto
# ("[MARCOS]/[CASTRO]", ver GlossaryWord).
#
# O GRUPO É RESOLVIDO NOS DOIS SENTIDOS, e é por isso que ele mora aqui, e não dentro da palavra:
# marcar CASTRO em "Paired Words" de MARCOS liga os dois, e descobrir CASTRO precisa trazer MARCOS
# igual. A alternativa seria pedir ao design que apontasse o par nos dois arquivos — o que criaria
# referência circular entre dois .tres, que é exatamente o que o Godot não carrega bem.
#
# O fechamento é transitivo: se A aponta B e B aponta C, descobrir qualquer um dos três traz os três.
static func find_pair_group(word_id: StringName) -> Array[StringName]:
	var group: Array[StringName] = [word_id]
	var pending: Array[StringName] = [word_id]

	while not pending.is_empty():
		var current: StringName = pending.pop_back()
		for word: GlossaryWord in load_all_words():
			var links_to_current: bool = false
			for paired: GlossaryWord in word.paired_words:
				if paired != null and paired.id == current:
					links_to_current = true
					break

			# Os dois sentidos: a palavra que APONTA a atual e as que a atual aponta.
			var candidates: Array[StringName] = []
			if links_to_current:
				candidates.append(word.id)
			if word.id == current:
				for paired: GlossaryWord in word.paired_words:
					if paired != null:
						candidates.append(paired.id)

			for candidate: StringName in candidates:
				if candidate != &"" and not group.has(candidate):
					group.append(candidate)
					pending.append(candidate)

	return group


# Diz se a chave existe no translations.csv. Chave vazia devolve false: campo em branco é erro de
# preenchimento, não "sem tradução".
static func has_translation_key(key: String) -> bool:
	return InsightCatalog.has_translation_key(key)


# Descarta a varredura guardada. Chamado pela ação "Recarregar catálogo" do menu de debug e pela
# validação em lote, pra que editar um .tres (ou o CSV) e validar de novo dê a resposta atual.
static func clear_cache() -> void:
	_profiles.clear()
	_words.clear()
	_categories.clear()
	_loaded = false
	InsightCatalog.clear_cache()


# Faz a varredura na primeira consulta. As palavras são juntadas da pasta E dos pools dos perfis
# porque nada obriga uma palavra a morar na pasta: uma palavra criada direto dentro do perfil
# funciona, e o glossário ainda precisa achá-la pelo id.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	for resource: Resource in _load_folder(PROFILES_DIR):
		var profile: NPCProfile = resource as NPCProfile
		if profile != null:
			_profiles.append(profile)
	_profiles.sort_custom(_compare_profiles)

	var word_ids: Dictionary = {}
	for resource: Resource in _load_folder(WORDS_DIR):
		var word: GlossaryWord = resource as GlossaryWord
		if word != null and not word_ids.has(word.id):
			word_ids[word.id] = true
			_words.append(word)
	for profile: NPCProfile in _profiles:
		for word: GlossaryWord in profile.glossary_words:
			if word != null and not word_ids.has(word.id):
				word_ids[word.id] = true
				_words.append(word)
	_words.sort_custom(_compare_words)

	for resource: Resource in _load_folder(CATEGORIES_DIR):
		var category: GlossaryCategory = resource as GlossaryCategory
		if category != null:
			_categories.append(category)
	_categories.sort_custom(_compare_categories)

	print("[Profiling] - Catálogo carregado: %d perfis, %d palavras, %d categorias" % [
		_profiles.size(), _words.size(), _categories.size()])


# Carrega todo .tres/.res de uma pasta. O trim_suffix(".remap") existe pelo mesmo motivo do
# InsightCatalog: a exportação renomeia os recursos convertidos para .tres.remap, e sem ele a
# varredura funciona no editor e devolve lista vazia na build.
static func _load_folder(dir_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		push_warning("[Profiling] - AVISO: pasta \"%s\" não existe" % dir_path)
		return result
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean_name: String = file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres") and not clean_name.ends_with(".res"):
			continue
		var resource: Resource = ResourceLoader.load(dir_path + clean_name)
		if resource == null:
			push_warning("[Profiling] - AVISO: falha ao carregar \"%s\"" % (dir_path + clean_name))
			continue
		result.append(resource)
	return result


static func _compare_profiles(left: NPCProfile, right: NPCProfile) -> bool:
	return String(left.npc_id) < String(right.npc_id)


static func _compare_words(left: GlossaryWord, right: GlossaryWord) -> bool:
	return String(left.id) < String(right.id)


# Ordem de exibição das categorias: sort_order primeiro, id como desempate. Sem o desempate, duas
# categorias com o mesmo sort_order sairiam em ordem diferente a cada execução.
static func _compare_categories(left: GlossaryCategory, right: GlossaryCategory) -> bool:
	if left.sort_order != right.sort_order:
		return left.sort_order < right.sort_order
	return String(left.id) < String(right.id)
