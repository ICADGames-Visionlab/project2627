# ProfilingJournal.gd — Autoload: tudo o que o jogador descobriu, preencheu, marcou e escolheu no
# profiling.
#
# É o dono do estado do sistema. A tela de profiling desenha o que está aqui e escreve aqui; ninguém
# guarda progresso por fora, e é isso que faz o GDD funcionar: o jogador pode preencher metade de uma
# página, sair do espírito, acordar, jogar um dia inteiro e voltar — as palavras continuam nas
# lacunas onde ele as deixou.
#
# O QUE MORA AQUI:
#
#   - palavras descobertas, por NPC (o "23" do "23/36" do glossário)
#   - as palavras que estão nas lacunas de cada história, mesmo incompletas
#   - quais histórias já foram resolvidas
#   - as marcas de lixo/estrela das palavras (a organização que o jogador faz do glossário)
#   - a emoção que o jogador escolheu pra cada NPC, e a partir de que dia ela vale
#   - se o jogador já encontrou o NPC no mundo real (hoje sempre sim — ver
#     ASSUME_MET_UNTIL_DIALOGUE_EXISTS)
#
# POR QUE É AUTOLOAD (o guideline pede justificar): este estado tem que atravessar troca de cena e
# de dia, e tem que estar no save. É a mesma situação do InsightJournal, e a decisão é a mesma —
# com a mesma ressalva: a criação de Autoload novo deve ser validada com o Lead de Programação.
#
# A EMOÇÃO VALE A PARTIR DO DIA SEGUINTE. Quem escolhe é o jogador, dentro do sonho; o efeito começa
# no próximo dia, então cada escolha é guardada com o dia em que passa a valer. Isso resolve dois
# problemas de uma vez: o jogador pode apertar FELICIDADE, TRISTEZA e RAIVA seguidas e acordar com a
# última (é só sobrescrever a escolha do mesmo dia), e o NPCDirector pode perguntar "qual é a emoção
# dele hoje?" a qualquer momento, sem depender de ordem de evento na virada de dia.
#
# ARMADILHA DO SAVE: o SaveManager serializa via JSON.stringify, e na volta todo StringName vira
# String e todo int vira float. Comparar StringName com String falha em silêncio (o jogador
# reencontraria palavras que já descobriu) e um slot de emoção que volta como 1.0 não casa com o
# enum, então as conversões na leitura (StringName(...) e int(...)) são obrigatórias, não estilo.
#
# ENQUANTO NÃO HÁ DONO DO SLOT ATIVO: igual ao InsightJournal — o jogo ainda não escolhe slot de
# save, então este diário carrega e salva sozinho no slot 1. No dia em que o slot ativo existir, quem
# for dono dele define save_slot_path e desliga o autosave; to_dict/from_dict já são a API desse
# fluxo.
#
# O guia completo está em docs/sistema_de_profiling.md.
extends Node

# Emitido quando qualquer coisa deste diário muda. Não é evento de bus: quem escuta é a tela de
# profiling aberta, que se redesenha — relação direta e permanente entre duas partes do mesmo
# sistema, que docs/event_bus.md manda resolver com signal direto em vez de engordar o bus.
signal journal_changed

# A marca que o jogador põe numa palavra com o botão direito (lixo é "essa não serve", estrela é
# "essa é importante", e as duas são filtro no glossário) é um GlossaryMark.Kind. O enum mora lá,
# e não aqui, pra poder ser tipo em assinatura de função — ver o topo de GlossaryMark.gd.

const DEBUG_SECTION: StringName = &"Profiling"

const SAVE_KEY: String = "profiling"
const DISCOVERED_KEY: String = "discovered"
const FILLS_KEY: String = "fills"
const SOLVED_KEY: String = "solved"
const MARKS_KEY: String = "marks"
const EMOTIONS_KEY: String = "emotions"
const MET_KEY: String = "met"
const SLOT_KEY: String = "slot"
const NEXT_SLOT_KEY: String = "next_slot"
const NEXT_DAY_KEY: String = "next_day"

# SUPORTE AO FUTURO: o GDD diz que o espírito de um NPC só aparece no sonho depois de o jogador ter
# conversado com ele no mundo real. O sistema de diálogo está sendo feito em outra branch e nada
# marca esse encontro ainda, então has_met() responde sim pra todo mundo enquanto esta constante
# estiver ligada. No dia em que o diálogo chamar mark_met(), desligar isto liga a regra do GDD
# inteira, sem mais nenhuma edição.
const ASSUME_MET_UNTIL_DIALOGUE_EXISTS: bool = true

# Slot em que o diário lê e grava. Público de propósito: é o gancho para o dia em que alguém for
# dono do slot ativo.
var save_slot_path: String = ""
# Grava o diário no slot a cada mudança. Ver o bloco "ENQUANTO NÃO HÁ DONO DO SLOT ATIVO" acima.
var autosave_enabled: bool = true

var _discovered: Dictionary = {}    # StringName(npc) -> { StringName(palavra): true }
var _fills: Dictionary = {}         # StringName(história) -> Array[String] (uma palavra por lacuna)
var _solved: Dictionary = {}        # StringName(história) -> true
var _marks: Dictionary = {}         # StringName(npc) -> { StringName(palavra): GlossaryMark.Kind }
var _emotions: Dictionary = {}      # StringName(npc) -> { slot: int, next_slot: int, next_day: int }
var _met: Dictionary = {}           # StringName(npc) -> true
# Evita gravar o arquivo N vezes quando uma ação muda várias coisas no mesmo frame (descobrir uma
# palavra em conjunto mexe em duas entradas).
var _autosave_queued: bool = false


func _ready() -> void:
	if save_slot_path.is_empty():
		save_slot_path = SaveManager.save_file_1
	load_from_slot()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Profiling" (ver docs/sistema_de_profiling.md).
		_register_debug_entries()


# ------------------------------------------------------------------------------------
# Palavras do glossário
# ------------------------------------------------------------------------------------

# Põe uma palavra no glossário de um NPC, com as palavras em conjunto que vêm junto com ela.
#
# npc_id vazio significa "o glossário de quem tiver essa palavra no pool": é o caso do mundo, em que
# o jogador clica numa palavra sublinhada no meio de um texto e ela vai pro NPC a que pertence, sem
# quem mostrou o texto precisar saber de quem é.
#
# É ESTA A PORTA DE ENTRADA DO SISTEMA DE INVENTÁRIO E DO DE DIÁLOGO: nenhum dos dois existe ainda
# (as evidências vêm do inventário, as falas vêm do diálogo, ambos em outra branch), e os dois vão
# chamar exatamente esta função quando existirem.
func discover_word(word_id: StringName, npc_id: StringName = &"") -> bool:
	if word_id == &"":
		return false

	var targets: Array[StringName] = []
	if npc_id != &"":
		targets.append(npc_id)
	else:
		for profile: NPCProfile in ProfilingCatalog.find_profiles_with_word(word_id):
			targets.append(profile.npc_id)

	if targets.is_empty():
		push_warning("[Profiling] - AVISO: a palavra \"%s\" não está no pool de nenhum NPC" % word_id)
		return false

	# Palavras em conjunto ([MARCOS]/[CASTRO]): clicar em uma traz todas as do grupo, nos dois
	# sentidos (ver ProfilingCatalog.find_pair_group).
	var group: Array[StringName] = ProfilingCatalog.find_pair_group(word_id)
	var discovered_anything: bool = false
	for target: StringName in targets:
		for member: StringName in group:
			discovered_anything = _discover_single(target, member) or discovered_anything

	return discovered_anything


# Diz se a palavra já está no glossário do NPC.
func is_word_discovered(npc_id: StringName, word_id: StringName) -> bool:
	var words: Dictionary = _discovered.get(npc_id, {}) as Dictionary
	return words.has(word_id)


# As palavras descobertas de um NPC, em ordem alfabética de id. Ordem estável pra o glossário não
# embaralhar sozinho entre aberturas (a ordenação de tela é escolha do jogador, pelos filtros).
func get_discovered_word_ids(npc_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var words: Dictionary = _discovered.get(npc_id, {}) as Dictionary
	for word_id: StringName in words.keys():
		result.append(word_id)
	result.sort_custom(_compare_names)
	return result


# Quantas palavras o jogador já descobriu deste NPC — o "23" do "23/36".
func count_discovered_words(npc_id: StringName) -> int:
	var words: Dictionary = _discovered.get(npc_id, {}) as Dictionary
	return words.size()


# ------------------------------------------------------------------------------------
# Marcas (lixo e estrela)
# ------------------------------------------------------------------------------------

# Marca (ou desmarca) uma palavra do glossário de um NPC. Marcar com a marca que já está posta
# remove: é o que o GDD descreve — clicar de novo no símbolo o tira.
func set_mark(npc_id: StringName, word_id: StringName, mark: GlossaryMark.Kind) -> void:
	var marks: Dictionary = _marks.get(npc_id, {}) as Dictionary
	var current: GlossaryMark.Kind = get_mark(npc_id, word_id)
	var next_mark: GlossaryMark.Kind = GlossaryMark.Kind.NONE if current == mark else mark

	if next_mark == GlossaryMark.Kind.NONE:
		marks.erase(word_id)
	else:
		marks[word_id] = next_mark
	_marks[npc_id] = marks

	print("[Profiling] - Palavra \"%s\" de \"%s\": %s" % [
		word_id, npc_id, GlossaryMark.get_debug_name(next_mark)])
	_notify_changed()


# A marca de uma palavra, ou NONE.
#
# A leitura passa por uma comparação explícita, e não por uma conversão de int pra enum, porque o
# valor pode vir do save: um arquivo editado à mão (ou de uma versão em que o enum tinha outra
# ordem) devolveria um número que não é marca nenhuma, e cair em NONE é melhor do que desenhar um
# símbolo que não existe.
func get_mark(npc_id: StringName, word_id: StringName) -> GlossaryMark.Kind:
	var marks: Dictionary = _marks.get(npc_id, {}) as Dictionary
	if not marks.has(word_id):
		return GlossaryMark.Kind.NONE
	var stored: int = int(marks[word_id])
	if stored == GlossaryMark.Kind.TRASH:
		return GlossaryMark.Kind.TRASH
	if stored == GlossaryMark.Kind.STAR:
		return GlossaryMark.Kind.STAR
	return GlossaryMark.Kind.NONE


# ------------------------------------------------------------------------------------
# Lacunas das histórias
# ------------------------------------------------------------------------------------

# As palavras que estão nas lacunas de uma história, uma por lacuna, com string vazia na lacuna
# vazia. Sempre devolve blank_count posições: é isso que deixa a tela e a correção tratarem uma
# história nova, um save antigo e uma história que ganhou lacunas do mesmo jeito.
func get_fills(story_id: StringName, blank_count: int) -> PackedStringArray:
	var stored: PackedStringArray = _fills.get(story_id, PackedStringArray()) as PackedStringArray
	var result: PackedStringArray = PackedStringArray()
	result.resize(blank_count)
	for index: int in blank_count:
		result[index] = stored[index] if index < stored.size() else ""
	return result


# Põe uma palavra numa lacuna. A MESMA PALAVRA SÓ PODE ESTAR EM UMA LACUNA: soltar uma palavra que
# já está em outra lacuna a MOVE, em vez de duplicá-la. Sem isso, o jogador preencheria oito lacunas
# com a mesma palavra e o glossário deixaria de dizer o que ainda está por usar.
func set_blank(story_id: StringName, index: int, word_id: StringName, blank_count: int) -> void:
	if index < 0 or index >= blank_count:
		push_warning("[Profiling] - AVISO: lacuna %d fora da história \"%s\"" % [index, story_id])
		return

	var fills: PackedStringArray = get_fills(story_id, blank_count)
	if word_id != &"":
		for other: int in blank_count:
			if other != index and fills[other] == String(word_id):
				fills[other] = ""
	fills[index] = String(word_id)
	_fills[story_id] = fills

	print("[Profiling] - História \"%s\": lacuna %d = \"%s\"" % [
		story_id, index, word_id if word_id != &"" else "(vazia)"])
	_notify_changed()


# Esvazia uma lacuna. Atalho de leitura pra quem lê a tela: clicar numa lacuna preenchida a limpa.
func clear_blank(story_id: StringName, index: int, blank_count: int) -> void:
	set_blank(story_id, index, &"", blank_count)


# A lacuna em que uma palavra está, ou -1. O glossário pergunta isto por palavra pra apagar da lista
# o que já está em uso na página.
func find_blank_with_word(story_id: StringName, word_id: StringName, blank_count: int) -> int:
	if word_id == &"":
		return -1
	var fills: PackedStringArray = get_fills(story_id, blank_count)
	for index: int in fills.size():
		if fills[index] == String(word_id):
			return index
	return -1


# ------------------------------------------------------------------------------------
# Histórias resolvidas
# ------------------------------------------------------------------------------------

# Diz se a história já foi acertada por inteiro.
func is_story_solved(story_id: StringName) -> bool:
	return _solved.has(story_id)


# Marca uma história como resolvida e anuncia o fato. Idempotente: marcar de novo não reemite nada,
# senão reabrir uma história resolvida tocaria a música e reescreveria o diário a cada visita.
#
# Quando esta foi a última história do NPC, sai também o npc_profiling_completed — é ele que faz o
# jogador acordar do sonho (ver ProfilingScreen).
func mark_story_solved(npc_id: StringName, story_id: StringName) -> void:
	if story_id == &"" or _solved.has(story_id):
		return

	_solved[story_id] = true
	print("[Profiling] - História \"%s\" de \"%s\" resolvida" % [story_id, npc_id])
	# É AQUI QUE O DIÁRIO, A MÚSICA E O DIÁLOGO ENTRAM. Os três ainda não existem, e por isso não há
	# evento de bus para eles: evento sem ouvinte é o erro comum que docs/event_bus.md manda evitar.
	# Quando o primeiro dos três existir, declarar profiling_story_solved(npc_id, story_id) no
	# EventBus e emitir nesta linha cobre todos — o texto da entrada do diário já está pronto, em
	# ProfilingStory.journal_entry_key.
	_notify_changed()

	if is_profile_complete(npc_id):
		print("[Profiling] - Profiling de \"%s\" completo: todas as emoções foram entendidas" % npc_id)
		EventBus.npc_profiling_completed.emit(npc_id)


# Diz se TODAS as histórias de um NPC estão resolvidas. NPC sem perfil, ou com perfil sem história,
# nunca está completo: senão o jogador acordaria do sonho por ter falado com um espírito vazio.
func is_profile_complete(npc_id: StringName) -> bool:
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile == null or profile.get_story_count() == 0:
		return false
	for story: ProfilingStory in profile.stories:
		if story != null and not is_story_solved(story.id):
			return false
	return true


# Quantas histórias de um NPC estão resolvidas. Usada no relatório de debug e no log.
func count_solved_stories(npc_id: StringName) -> int:
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile == null:
		return 0
	var count: int = 0
	for story: ProfilingStory in profile.stories:
		if story != null and is_story_solved(story.id):
			count += 1
	return count


# ------------------------------------------------------------------------------------
# Emoção escolhida no sonho
# ------------------------------------------------------------------------------------

# Registra a emoção que o jogador escolheu pra um NPC. Ela VALE A PARTIR DO DIA SEGUINTE, então o
# que fica guardado é o slot mais o dia em que ele passa a valer.
#
# Escolher de novo no mesmo sonho sobrescreve: é o "aperta FELICIDADE, depois TRISTEZA, depois RAIVA
# e amanhã ele acorda com RAIVA" do GDD.
func schedule_emotion_slot(npc_id: StringName, slot: int) -> void:
	var entry: Dictionary = _emotions.get(npc_id, {}) as Dictionary
	var effective_day: int = GameClock.time.get_day() + 1
	entry[NEXT_SLOT_KEY] = slot
	entry[NEXT_DAY_KEY] = effective_day
	_emotions[npc_id] = entry

	# Sem evento de bus: quem aplica a escolha é o NPCDirector, e ele PERGUNTA na virada de dia (ver
	# resolve_emotion_slot) em vez de escutar — assim nada depende de ordem de evento. A tela aberta
	# se redesenha pelo journal_changed logo abaixo.
	print("[Profiling] - \"%s\" vai acordar no slot de emoção %d no dia %d" % [
		npc_id, slot, effective_day])
	_notify_changed()


# A emoção vigente de um NPC hoje, já resolvendo a escolha que venceu.
#
# É ESTA A FUNÇÃO QUE O NPCDirector CHAMA na virada de dia. Ela promove a escolha quando o dia dela
# chega (o que grava o resultado e esvazia o agendamento) e devolve a emoção inicial do .tres quando
# o jogador nunca escolheu nada — é o que faz a cidade funcionar igual antes do profiling existir.
func resolve_emotion_slot(definition: NPCDefinition) -> int:
	if definition == null:
		return NPCDefinition.EmotionSlot.NEUTRAL

	var entry: Dictionary = _emotions.get(definition.id, {}) as Dictionary
	var today: int = GameClock.time.get_day()

	if entry.has(NEXT_SLOT_KEY) and today >= int(entry.get(NEXT_DAY_KEY, 0)):
		entry[SLOT_KEY] = int(entry[NEXT_SLOT_KEY])
		entry.erase(NEXT_SLOT_KEY)
		entry.erase(NEXT_DAY_KEY)
		_emotions[definition.id] = entry
		print("[Profiling] - \"%s\" acordou no slot de emoção %d" % [definition.id, int(entry[SLOT_KEY])])
		_notify_changed()

	if entry.has(SLOT_KEY):
		return int(entry[SLOT_KEY])
	return definition.starting_slot


# O slot que o jogador escolheu e que ainda não entrou em vigor, ou -1. A tela do espírito usa pra
# dizer "amanhã ele acorda assim" sem mentir sobre o estado de hoje.
func get_scheduled_slot(npc_id: StringName) -> int:
	var entry: Dictionary = _emotions.get(npc_id, {}) as Dictionary
	if not entry.has(NEXT_SLOT_KEY):
		return -1
	return int(entry[NEXT_SLOT_KEY])


# ------------------------------------------------------------------------------------
# Encontro no mundo real (suporte ao sistema de diálogo)
# ------------------------------------------------------------------------------------

# Diz se o jogador já encontrou este NPC no mundo real — o que, pelo GDD, é o que faz o espírito
# dele existir no sonho. Ver ASSUME_MET_UNTIL_DIALOGUE_EXISTS no topo do arquivo.
func has_met(npc_id: StringName) -> bool:
	if ASSUME_MET_UNTIL_DIALOGUE_EXISTS:
		return true
	return _met.has(npc_id)


# Marca que o jogador encontrou o NPC no mundo real. O sistema de diálogo vai chamar isto quando
# existir; hoje só o menu de debug chama.
func mark_met(npc_id: StringName) -> void:
	if npc_id == &"" or _met.has(npc_id):
		return
	_met[npc_id] = true
	print("[Profiling] - Jogador encontrou \"%s\" no mundo real" % npc_id)
	_notify_changed()


# ------------------------------------------------------------------------------------
# Save
# ------------------------------------------------------------------------------------

# Esquece tudo. Existe para o debug e para o dia em que "novo jogo" precisar zerar o profiling sem
# apagar o arquivo de save inteiro.
func reset() -> void:
	_discovered.clear()
	_fills.clear()
	_solved.clear()
	_marks.clear()
	_emotions.clear()
	_met.clear()
	print("[Profiling] - Diário de profiling zerado")
	_notify_changed()


# Estado do diário como Dictionary, no formato que o SaveManager sabe serializar: só String, int,
# bool e Array/Dictionary deles. Nada de StringName nem de PackedStringArray, que é o que o JSON não
# devolve igual.
func to_dict() -> Dictionary:
	var discovered: Dictionary = {}
	for npc_id: StringName in _discovered.keys():
		var words: Array[String] = []
		for word_id: StringName in get_discovered_word_ids(npc_id):
			words.append(String(word_id))
		discovered[String(npc_id)] = words

	var fills: Dictionary = {}
	for story_id: StringName in _fills.keys():
		var words: Array[String] = []
		for word: String in (_fills[story_id] as PackedStringArray):
			words.append(word)
		fills[String(story_id)] = words

	var solved: Array[String] = []
	for story_id: StringName in _solved.keys():
		solved.append(String(story_id))
	solved.sort()

	var marks: Dictionary = {}
	for npc_id: StringName in _marks.keys():
		var per_word: Dictionary = {}
		for word_id: StringName in (_marks[npc_id] as Dictionary).keys():
			per_word[String(word_id)] = int((_marks[npc_id] as Dictionary)[word_id])
		marks[String(npc_id)] = per_word

	var emotions: Dictionary = {}
	for npc_id: StringName in _emotions.keys():
		var entry: Dictionary = _emotions[npc_id] as Dictionary
		var stored: Dictionary = {}
		for key: String in [SLOT_KEY, NEXT_SLOT_KEY, NEXT_DAY_KEY]:
			if entry.has(key):
				stored[key] = int(entry[key])
		emotions[String(npc_id)] = stored

	var met: Array[String] = []
	for npc_id: StringName in _met.keys():
		met.append(String(npc_id))
	met.sort()

	return {
		DISCOVERED_KEY: discovered,
		FILLS_KEY: fills,
		SOLVED_KEY: solved,
		MARKS_KEY: marks,
		EMOTIONS_KEY: emotions,
		MET_KEY: met,
	}


# Recarrega o diário a partir de um Dictionary vindo do save. As conversões explícitas pra
# StringName e pra int são a armadilha documentada no topo deste arquivo.
func from_dict(data: Dictionary) -> void:
	_discovered.clear()
	_fills.clear()
	_solved.clear()
	_marks.clear()
	_emotions.clear()
	_met.clear()

	for raw_npc: Variant in (data.get(DISCOVERED_KEY, {}) as Dictionary).keys():
		var words: Dictionary = {}
		for raw_word: Variant in (data[DISCOVERED_KEY] as Dictionary)[raw_npc]:
			words[StringName(str(raw_word))] = true
		_discovered[StringName(str(raw_npc))] = words

	for raw_story: Variant in (data.get(FILLS_KEY, {}) as Dictionary).keys():
		var fills: PackedStringArray = PackedStringArray()
		for raw_word: Variant in (data[FILLS_KEY] as Dictionary)[raw_story]:
			fills.append(str(raw_word))
		_fills[StringName(str(raw_story))] = fills

	for raw_story: Variant in data.get(SOLVED_KEY, []):
		_solved[StringName(str(raw_story))] = true

	for raw_npc: Variant in (data.get(MARKS_KEY, {}) as Dictionary).keys():
		var per_word: Dictionary = {}
		var stored_marks: Dictionary = (data[MARKS_KEY] as Dictionary)[raw_npc] as Dictionary
		for raw_word: Variant in stored_marks.keys():
			per_word[StringName(str(raw_word))] = int(stored_marks[raw_word])
		_marks[StringName(str(raw_npc))] = per_word

	for raw_npc: Variant in (data.get(EMOTIONS_KEY, {}) as Dictionary).keys():
		var entry: Dictionary = {}
		var stored_entry: Dictionary = (data[EMOTIONS_KEY] as Dictionary)[raw_npc] as Dictionary
		for key: String in [SLOT_KEY, NEXT_SLOT_KEY, NEXT_DAY_KEY]:
			if stored_entry.has(key):
				entry[key] = int(stored_entry[key])
		_emotions[StringName(str(raw_npc))] = entry

	for raw_npc: Variant in data.get(MET_KEY, []):
		_met[StringName(str(raw_npc))] = true

	# Sem agendar gravação: carregar não é mudança, e salvar de volta o que se acabou de ler
	# reescreveria o arquivo a cada boot do jogo por nada.
	_notify_changed(false)


# Grava o profiling dentro do slot atual, preservando as outras chaves do arquivo: o save é de todos
# os sistemas, e reescrevê-lo inteiro apagaria o que os outros já tinham guardado.
func save_to_slot() -> void:
	var data: Dictionary = SaveManager.load_game(save_slot_path)
	data[SAVE_KEY] = to_dict()
	SaveManager.save_game(data, save_slot_path)
	print("[Profiling] - Diário salvo em \"%s\" (%d NPCs com palavras, %d histórias resolvidas)" % [
		save_slot_path, _discovered.size(), _solved.size()])


# Lê o profiling do slot atual. Slot sem a chave (save antigo, ou slot novo) devolve Dictionary
# vazio e o diário simplesmente começa zerado — nunca é erro.
func load_from_slot() -> void:
	var data: Dictionary = SaveManager.load_game(save_slot_path)
	from_dict(data.get(SAVE_KEY, {}) as Dictionary)
	print("[Profiling] - Diário carregado de \"%s\" (%d NPCs com palavras, %d histórias resolvidas)" % [
		save_slot_path, _discovered.size(), _solved.size()])


# ------------------------------------------------------------------------------------
# Interno
# ------------------------------------------------------------------------------------

# Põe uma palavra no glossário de um NPC. Devolve false quando nada mudou — é o que corta a recursão
# das palavras em conjunto e o que evita reemitir o evento (e reanimar a mensagem na tela) por uma
# palavra que o jogador já tinha.
func _discover_single(npc_id: StringName, word_id: StringName) -> bool:
	var words: Dictionary = _discovered.get(npc_id, {}) as Dictionary
	if words.has(word_id):
		return false

	# A palavra é guardada mesmo fora do pool do NPC (o save não é lugar de julgar conteúdo), mas o
	# glossário não tem como desenhá-la: ele só sabe desenhar o que está no pool. O aviso aponta o
	# erro de preenchimento antes de alguém procurar a palavra que "não apareceu".
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile != null and profile.find_word(word_id) == null:
		push_warning("[Profiling] - AVISO: \"%s\" não tem a palavra \"%s\" no pool; ela não vai "
			% [npc_id, word_id] + "aparecer no glossário dele")

	words[word_id] = true
	_discovered[npc_id] = words
	print("[Profiling] - Palavra \"%s\" adicionada ao glossário de \"%s\" (%d/%d)" % [
		word_id, npc_id, count_discovered_words(npc_id), _get_total_words(npc_id)])
	EventBus.glossary_word_discovered.emit(npc_id, word_id)
	_notify_changed()
	return true


# O total de palavras do glossário de um NPC, com zero pra NPC sem perfil. Só pra log: quem desenha
# o "23/36" pergunta ao perfil direto.
func _get_total_words(npc_id: StringName) -> int:
	var profile: NPCProfile = ProfilingCatalog.find_profile(npc_id)
	if profile == null:
		return 0
	return profile.get_total_word_count()


# Anuncia a mudança e agenda a gravação. A gravação é adiada para o fim do frame porque uma ação só
# costuma mexer em duas ou três entradas em sequência (descobrir uma palavra em conjunto, resolver
# uma história), e o arquivo não precisa ser escrito uma vez por entrada.
func _notify_changed(schedule_autosave: bool = true) -> void:
	journal_changed.emit()
	if not schedule_autosave or not autosave_enabled or _autosave_queued:
		return
	_autosave_queued = true
	_flush_autosave.call_deferred()


# Executa a gravação agendada por _notify_changed().
func _flush_autosave() -> void:
	_autosave_queued = false
	if autosave_enabled:
		save_to_slot()


# Ordena dois StringName em ordem alfabética de verdade. Existe pelo mesmo motivo do InsightJournal:
# a comparação nativa de StringName é por ponteiro interno, e sem a conversão para String a lista
# sai numa ordem diferente a cada execução.
func _compare_names(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


# ------------------------------------------------------------------------------------
# Debug
# ------------------------------------------------------------------------------------

# [DEBUG] Entradas da seção "Profiling". Não existem em build de release.
func _register_debug_entries() -> void:
	DebugMenu.register_input(DEBUG_SECTION, "Descobrir palavra", _debug_discover_word, [
		DebugParam.string_value("palavra", "", _debug_word_suggestions),
		DebugParam.string_value("npc", "", _debug_npc_suggestions)])
	DebugMenu.register_input(DEBUG_SECTION, "Descobrir todas as palavras", _debug_discover_all, [
		DebugParam.string_value("npc", "", _debug_npc_suggestions)])
	DebugMenu.register_input(DEBUG_SECTION, "Resolver história", _debug_solve_story, [
		DebugParam.string_value("historia", "", _debug_story_suggestions)])
	DebugMenu.register_input(DEBUG_SECTION, "Abrir espírito", _debug_open_spirit, [
		DebugParam.string_value("npc", "", _debug_npc_suggestions)])
	DebugMenu.register_action(DEBUG_SECTION, "Listar estado do profiling", _debug_print_state)
	DebugMenu.register_action(DEBUG_SECTION, "Validar conteúdo do profiling", _debug_validate)
	DebugMenu.register_action(DEBUG_SECTION, "Autoteste do profiling", _debug_run_self_test)
	DebugMenu.register_action(DEBUG_SECTION, "Recarregar catálogo", _debug_reload_catalog)
	DebugMenu.register_action(DEBUG_SECTION, "Resetar profiling", reset, true)
	DebugMenu.register_action(DEBUG_SECTION, "Salvar profiling", save_to_slot)
	DebugMenu.register_action(DEBUG_SECTION, "Carregar profiling", load_from_slot)
	DebugMenu.register_toggle(DEBUG_SECTION, "Salvar automático", _debug_set_autosave, autosave_enabled)


# [DEBUG] Põe uma palavra no glossário sem precisar achá-la no mundo. É o que torna o profiling
# jogável hoje: as palavras vêm de evidências e de diálogo, e nenhum dos dois sistemas existe.
func _debug_discover_word(word_id: String, npc_id: String) -> void:
	discover_word(StringName(word_id), StringName(npc_id))


# [DEBUG] Põe TODAS as palavras do pool de um NPC no glossário dele — atalho pra revisar uma página
# de profiling inteira sem caçar palavra por palavra. npc vazio faz isso pra todos os perfis.
func _debug_discover_all(npc_id: String) -> void:
	for profile: NPCProfile in ProfilingCatalog.load_all_profiles():
		if not npc_id.is_empty() and String(profile.npc_id) != npc_id:
			continue
		for word: GlossaryWord in profile.glossary_words:
			if word != null:
				discover_word(word.id, profile.npc_id)


# [DEBUG] Resolve uma história de uma vez, preenchendo as lacunas com a solução. Serve pra ver a
# tela de história resolvida (e o "acordar" do profiling completo) sem jogar a página inteira.
func _debug_solve_story(story_id: String) -> void:
	for profile: NPCProfile in ProfilingCatalog.load_all_profiles():
		var story: ProfilingStory = profile.find_story(StringName(story_id))
		if story == null:
			continue
		for index: int in story.get_blank_count():
			discover_word(story.get_expected_word_id(index), profile.npc_id)
			set_blank(story.id, index, story.get_expected_word_id(index), story.get_blank_count())
		mark_story_solved(profile.npc_id, story.id)
		return
	print("[Profiling] - Nenhuma história com o id \"%s\"" % story_id)


# [DEBUG] Abre a tela de profiling de um NPC sem precisar achar o espírito dele no sonho.
func _debug_open_spirit(npc_id: String) -> void:
	if ProfilingCatalog.find_profile(StringName(npc_id)) == null:
		print("[Profiling] - \"%s\" não tem perfil de profiling" % npc_id)
		return
	EventBus.profiling_requested.emit(StringName(npc_id))


# [DEBUG] Imprime o estado do diário no log do jogo (visível no visualizador de log, F5).
func _debug_print_state() -> void:
	for profile: NPCProfile in ProfilingCatalog.load_all_profiles():
		print("[Profiling] - \"%s\": %d/%d palavras, %d/%d histórias resolvidas, slot hoje: %s" % [
			profile.npc_id,
			count_discovered_words(profile.npc_id), profile.get_total_word_count(),
			count_solved_stories(profile.npc_id), profile.get_story_count(),
			_describe_slot(profile.npc_id)])
		for story: ProfilingStory in profile.stories:
			if story == null:
				continue
			var evaluation: ProfilingEvaluation = ProfilingEvaluation.evaluate(
				story, get_fills(story.id, story.get_blank_count()))
			print("[Profiling] -   história \"%s\": %s" % [story.id, evaluation])


# [DEBUG] Descreve o slot vigente e o agendado de um NPC, pro relatório de estado.
func _describe_slot(npc_id: StringName) -> String:
	var entry: Dictionary = _emotions.get(npc_id, {}) as Dictionary
	var current: String = str(entry.get(SLOT_KEY, "(inicial do .tres)"))
	if entry.has(NEXT_SLOT_KEY):
		return "%s (dia %d: %d)" % [current, int(entry[NEXT_DAY_KEY]), int(entry[NEXT_SLOT_KEY])]
	return current


# [DEBUG] Valida o conteúdo do profiling do projeto inteiro: preenchimento dos recursos, chaves que
# não existem no CSV e perfil de NPC que não está no roster.
func _debug_validate() -> void:
	ProfilingCatalog.clear_cache()
	var problems: int = 0
	var profiles: Array[NPCProfile] = ProfilingCatalog.load_all_profiles()

	print("[Profiling] - Validação de conteúdo: %d perfis" % profiles.size())
	for profile: NPCProfile in profiles:
		var issues: PackedStringArray = profile.collect_issues()
		for issue: String in issues:
			print("[Profiling] -   \"%s\": %s" % [profile.npc_id, issue])
		problems += issues.size()

		for story: ProfilingStory in profile.stories:
			if story == null:
				continue
			for key: String in [story.template_key, story.resolved_text_key, story.journal_entry_key]:
				if not key.is_empty() and not ProfilingCatalog.has_translation_key(key):
					print("[Profiling] -   \"%s\": chave \"%s\" não existe no translations.csv" % [
						profile.npc_id, key])
					problems += 1

		for word: GlossaryWord in profile.glossary_words:
			if word != null and not word.text_key.is_empty() \
					and not ProfilingCatalog.has_translation_key(word.text_key):
				print("[Profiling] -   \"%s\": a palavra \"%s\" usa a chave \"%s\", que não existe no "
					% [profile.npc_id, word.id, word.text_key] + "translations.csv")
				problems += 1

		problems += _validate_against_roster(profile)

	print("[Profiling] - Validação de conteúdo: %s" % (
		"nenhum problema" if problems == 0 else "%d problema(s)" % problems))


# [DEBUG] Confere um perfil contra o roster de NPCs: perfil de NPC que não existe, e história numa
# emoção que o NPC não tem (ela nunca apareceria na tela do espírito).
func _validate_against_roster(profile: NPCProfile) -> int:
	var director: NPCDirector = get_tree().get_first_node_in_group(NPCDirector.GROUP) as NPCDirector
	if director == null or director.roster == null:
		return 0

	var definition: NPCDefinition = director.roster.find(profile.npc_id)
	if definition == null:
		print("[Profiling] -   \"%s\": não há NPC com este id no roster" % profile.npc_id)
		return 1

	var problems: int = 0
	for story: ProfilingStory in profile.stories:
		if story == null or story.emotion == null:
			continue
		var found: bool = false
		for slot: int in NPCDefinition.EmotionSlot.values():
			var emotion: EmotionDefinition = definition.get_emotion(slot)
			if emotion != null and emotion.id == story.emotion.id:
				found = true
				break
		if not found:
			print("[Profiling] -   \"%s\": a história \"%s\" é da emoção \"%s\", que este NPC não tem"
				% [profile.npc_id, story.id, story.emotion.id])
			problems += 1
	return problems


# [DEBUG] Roda o autoteste da lógica do profiling e imprime o relatório.
func _debug_run_self_test() -> void:
	var self_test: ProfilingSelfTest = ProfilingSelfTest.new()
	self_test.run()
	print(self_test.report())


# [DEBUG] Descarta a varredura do catálogo, pra editar um .tres e ver o resultado sem reabrir o jogo.
func _debug_reload_catalog() -> void:
	ProfilingCatalog.clear_cache()
	print("[Profiling] - Catálogo descartado; a próxima consulta relê os arquivos")
	_notify_changed(false)


# [DEBUG] Sugere ao autocomplete do console as palavras do projeto.
func _debug_word_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for word: GlossaryWord in ProfilingCatalog.load_all_words():
		result.append(String(word.id))
	return result


# [DEBUG] Sugere ao autocomplete do console os NPCs que têm perfil de profiling.
func _debug_npc_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for profile: NPCProfile in ProfilingCatalog.load_all_profiles():
		result.append(String(profile.npc_id))
	return result


# [DEBUG] Sugere ao autocomplete do console as histórias do projeto.
func _debug_story_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for profile: NPCProfile in ProfilingCatalog.load_all_profiles():
		for story: ProfilingStory in profile.stories:
			if story != null:
				result.append(String(story.id))
	return result


# [DEBUG] Liga/desliga a gravação automática do diário.
func _debug_set_autosave(enabled: bool) -> void:
	autosave_enabled = enabled
	print("[Profiling] - Salvamento automático do profiling %s" % ("ligado" if enabled else "desligado"))
