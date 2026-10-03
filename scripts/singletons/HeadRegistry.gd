# HeadRegistry.gd — Autoload: o elenco de cabeças e quais delas o jogador já tem.
#
# É o único lugar que responde "de que cor é a cabeça X" e "o jogador já tem a cabeça X". O elenco é
# a cabeça do jogador (.tres em res://resources/heads/) mais uma cabeça por NPC do roster, montada
# da definição dele (ver InsightCatalog.load_all_heads): NPC novo no roster já tem cabeça.
#
# DERROTA DE NPC: derrotar um NPC é completar o profiling dele, e é isso que dá ao jogador a cabeça
# desse NPC. Este registro não guarda quem foi derrotado: ele PERGUNTA ao ProfilingJournal
# (is_profile_complete), que já é o dono do fato e já está no save. Guardar uma cópia aqui criaria
# duas verdades sobre o mesmo fato, e a cópia teria que ser salva à parte.
#
# O guia completo está em docs/insights.md.
extends Node

# Emitido quando o conjunto de cabeças do jogador muda: um profiling completo, um save carregado ou
# o debug. Não é evento de bus: o único interessado é o InsightDirector, que reavalia os orbes — ver
# a mesma justificativa em InsightJournal.journal_changed.
signal heads_changed

const DEBUG_SECTION: StringName = &"Insights"

var _heads: Dictionary = {}          # StringName(id) -> HeadData
# Ordem canônica das cabeças (ids em ordem alfabética). É ela que define o slot fixo de cada cabeça
# na órbita do jogador, então mexer nela move orbes de lugar.
var _order: Array[StringName] = []
# Cabeças disponíveis na última conferência. O ProfilingJournal avisa toda mudança (palavra
# descoberta, marca no glossário...), e comparar com isto é o que faz só a mudança de cabeça
# reavaliar os orbes.
var _last_unlocked: Array[StringName] = []
# [DEBUG] Cabeças destravadas à mão pelo menu, sem completar o profiling. Não vai para o save: é
# atalho de teste, não progresso do jogador.
var _debug_unlocked: Dictionary = {}  # StringName(id) -> true
# [DEBUG] Destrava tudo sem desbloquear de verdade: serve para ver o conteúdo de uma cena inteira
# sem antes derrotar ninguém.
var _unlock_all: bool = false


func _ready() -> void:
	_load_heads()
	# Adiado de propósito: o ProfilingJournal é declarado depois deste Autoload e ainda não existe
	# quando este _ready() roda. A chamada adiada cai no fim do frame, com todos os Autoloads prontos
	# (mesmo cuidado do InsightDirector._connect_state_sources).
	_connect_profiling.call_deferred()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": atalho para a derrota de NPC (ver docs/insights.md).
		DebugMenu.register_input(DEBUG_SECTION, "Desbloquear cabeça", _debug_unlock_head, [
			DebugParam.string_value("head_id", "", _debug_head_suggestions)
		])
		DebugMenu.register_toggle(DEBUG_SECTION, "Desbloquear todas as cabeças", _debug_set_unlock_all, _unlock_all)


# Diz se o jogador pode ouvir esta cabeça agora. É a porta do canal de personagem: cabeça bloqueada
# não gera orbe nenhum. A do jogador vem de fábrica; a de um NPC, com o profiling completo dele.
func has_head(head_id: StringName) -> bool:
	var head: HeadData = get_head(head_id)
	if head == null:
		return false
	if _unlock_all or head.starts_unlocked() or _debug_unlocked.has(head_id):
		return true
	return ProfilingJournal.is_profile_complete(head_id)


# Devolve a cabeça, ou null quando o id não corresponde a nenhuma (nem ao jogador, nem a um NPC do
# roster). Quem chama trata o null: id errado num .tres de insight é erro de conteúdo, e o sistema
# precisa continuar de pé para o aviso de configuração poder apontá-lo.
func get_head(head_id: StringName) -> HeadData:
	return _heads.get(head_id, null) as HeadData


# Cor do orbe desta cabeça. Cabeça desconhecida devolve magenta: cor que ninguém escolheria de
# propósito, então aparece na tela como o erro que é.
func get_color(head_id: StringName) -> Color:
	var head: HeadData = get_head(head_id)
	return head.color if head != null else Color.MAGENTA


# Glifo desenhado dentro do orbe desta cabeça. Cabeça desconhecida devolve "?" pelo mesmo motivo de
# get_color().
func get_glyph(head_id: StringName) -> String:
	var head: HeadData = get_head(head_id)
	return head.glyph if head != null else "?"


# Chave de localização do nome exibido da cabeça, usada pela tela de diálogo.
func get_display_name_key(head_id: StringName) -> String:
	var head: HeadData = get_head(head_id)
	return head.display_name_key if head != null else ""


# Posição canônica da cabeça na lista de elenco. É o slot preferido dela na órbita do jogador: com
# slot derivado do id (e não da ordem de chegada), uma cabeça sumir não faz as outras pularem de
# lugar e o jogador clicar na errada.
func get_slot_index(head_id: StringName) -> int:
	return _order.find(head_id)


# Todo o elenco, em ordem canônica. Usado pela validação em lote e pelos relatórios de debug.
func get_all_heads() -> Array[HeadData]:
	var result: Array[HeadData] = []
	for head_id: StringName in _order:
		result.append(_heads[head_id])
	return result


# Ids das cabeças disponíveis agora, em ordem canônica.
func get_unlocked_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for head_id: StringName in _order:
		if has_head(head_id):
			result.append(head_id)
	return result


# Carrega o elenco: a cabeça do jogador e a de cada NPC do roster.
func _load_heads() -> void:
	_heads.clear()
	_order.clear()
	for head: HeadData in InsightCatalog.load_all_heads():
		if head.id == &"":
			push_warning("[Insights] - AVISO: cabeça sem id em \"%s\"" % head.resource_path)
			continue
		if _heads.has(head.id):
			push_warning("[Insights] - AVISO: id de cabeça repetido: \"%s\"" % head.id)
			continue
		_heads[head.id] = head
		_order.append(head.id)
	print("[Insights] - %d cabeça(s) no elenco" % _heads.size())


# Passa a ouvir o ProfilingJournal e tira a primeira foto das cabeças disponíveis, já com o save
# carregado.
func _connect_profiling() -> void:
	ProfilingJournal.journal_changed.connect(_on_profiling_changed)
	_last_unlocked = get_unlocked_ids()
	print("[Insights] - %d cabeça(s) disponível(is): %s" % [_last_unlocked.size(), _last_unlocked])


# Reage a qualquer mudança do profiling, mas só avisa quando o conjunto de cabeças mudou: é assim
# que um profiling completo (ou um save carregado) faz o orbe da cabeça nova aparecer na hora.
func _on_profiling_changed() -> void:
	var unlocked: Array[StringName] = get_unlocked_ids()
	if unlocked == _last_unlocked:
		return
	for head_id: StringName in unlocked:
		if not _last_unlocked.has(head_id):
			print("[Insights] - Cabeça \"%s\" desbloqueada: profiling completo" % head_id)
	_last_unlocked = unlocked
	heads_changed.emit()


# [DEBUG] Desbloqueia uma cabeça pelo menu/console sem completar o profiling do NPC — testar conteúdo
# sem precisar derrotar ninguém.
func _debug_unlock_head(head_id: String) -> void:
	var id: StringName = StringName(head_id)
	if not _heads.has(id):
		push_warning("[Insights] - AVISO: cabeça \"%s\" não existe (nem jogador, nem NPC do roster)" % id)
		return
	if _debug_unlocked.has(id):
		return
	_debug_unlocked[id] = true
	_last_unlocked = get_unlocked_ids()
	print("[Insights] - Cabeça \"%s\" desbloqueada pelo debug" % id)
	heads_changed.emit()


# [DEBUG] Sugere ao autocomplete do console os ids de cabeça que existem no projeto.
func _debug_head_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for head_id: StringName in _order:
		result.append(String(head_id))
	return result


# [DEBUG] Destrava (ou volta a trancar) o elenco inteiro de uma vez.
func _debug_set_unlock_all(enabled: bool) -> void:
	_unlock_all = enabled
	_last_unlocked = get_unlocked_ids()
	print("[Insights] - Desbloqueio total de cabeças %s" % ("ligado" if enabled else "desligado"))
	heads_changed.emit()
