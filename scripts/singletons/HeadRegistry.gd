# HeadRegistry.gd — Autoload: o elenco de cabeças e quais delas o jogador já tem.
#
# É o único lugar que responde "de que cor é a cabeça X" e "o jogador já tem a cabeça X". Uma cabeça
# nova é um .tres novo em res://resources/heads/, sem tocar em código de marcador nenhum.
#
# COSTURA COM A DERROTA DE NPC: o sistema de derrota ainda não existe, e declarar npc_defeated no
# EventBus agora seria criar evento sem ouvinte de verdade — o que docs/event_bus.md desaconselha
# explicitamente. Então, por enquanto, unlock_head() é chamada só por uma ação de debug. No dia em
# que a derrota existir, ela declara npc_defeated(npc_id) no bus e este registro passa a escutar: a
# mudança aqui é uma linha de connect() no _ready(), e nada mais do sistema de insights muda.
#
# O desbloqueio ainda não é salvo: quem for dono da derrota de NPC é quem sabe persistir "este NPC
# foi derrotado", e duplicar isso aqui criaria duas verdades sobre o mesmo fato.
#
# O guia completo está em docs/insights.md.
extends Node

# Emitido quando uma cabeça é desbloqueada (ou quando o debug destrava todas). Não é evento de bus:
# o único interessado é o InsightDirector, que reavalia os orbes — ver a mesma justificativa em
# InsightJournal.journal_changed.
signal heads_changed

const DEBUG_SECTION: StringName = &"Insights"

var _heads: Dictionary = {}          # StringName(id) -> HeadData
# Ordem canônica das cabeças (ids em ordem alfabética). É ela que define o slot fixo de cada cabeça
# na órbita do jogador, então mexer nela move orbes de lugar.
var _order: Array[StringName] = []
var _unlocked: Dictionary = {}       # StringName(id) -> true
# [DEBUG] Destrava tudo sem desbloquear de verdade: serve para ver o conteúdo de uma cena inteira
# sem antes derrotar ninguém.
var _unlock_all: bool = false


func _ready() -> void:
	_load_heads()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Insights": substituto da derrota de NPC (ver docs/insights.md).
		DebugMenu.register_input(DEBUG_SECTION, "Desbloquear cabeça", _debug_unlock_head, [
			DebugParam.string_value("head_id", "", _debug_head_suggestions)
		])
		DebugMenu.register_toggle(DEBUG_SECTION, "Desbloquear todas as cabeças", _debug_set_unlock_all, _unlock_all)


# Diz se o jogador pode ouvir esta cabeça agora. É a porta do canal de personagem: cabeça bloqueada
# não gera orbe nenhum.
func has_head(head_id: StringName) -> bool:
	if _unlock_all:
		return _heads.has(head_id)
	return _unlocked.has(head_id)


# Devolve o recurso da cabeça, ou null quando o id não corresponde a nenhum .tres. Quem chama trata
# o null: id errado num .tres de insight é erro de conteúdo, e o sistema precisa continuar de pé
# para o aviso de configuração poder apontá-lo.
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


# Desbloqueia uma cabeça para o jogador. Hoje só o debug chama; amanhã, quem tratar npc_defeated.
func unlock_head(head_id: StringName) -> void:
	if not _heads.has(head_id):
		push_warning("[Insights] - AVISO: cabeça \"%s\" não existe em %s" % [head_id, InsightCatalog.HEADS_DIR])
		return
	if _unlocked.has(head_id):
		return
	_unlocked[head_id] = true
	print("[Insights] - Cabeça \"%s\" desbloqueada" % head_id)
	heads_changed.emit()


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


# Carrega o elenco de res://resources/heads/ e já destrava as cabeças que nascem com o jogador (a
# dele mesmo). Sem isso o canal de personagem só existiria depois da primeira derrota, e não haveria
# como testar nada.
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
		if head.starts_unlocked():
			_unlocked[head.id] = true
	print("[Insights] - %d cabeça(s) no elenco, %d disponível(is) de início"
		% [_heads.size(), _unlocked.size()])


# [DEBUG] Desbloqueia uma cabeça pelo menu/console — o substituto da derrota de NPC enquanto ela não
# existe. Continua útil depois: testar conteúdo sem precisar derrotar ninguém.
func _debug_unlock_head(head_id: String) -> void:
	unlock_head(StringName(head_id))


# [DEBUG] Sugere ao autocomplete do console os ids de cabeça que existem no projeto.
func _debug_head_suggestions() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for head_id: StringName in _order:
		result.append(String(head_id))
	return result


# [DEBUG] Destrava (ou volta a trancar) o elenco inteiro de uma vez.
func _debug_set_unlock_all(enabled: bool) -> void:
	_unlock_all = enabled
	print("[Insights] - Desbloqueio total de cabeças %s" % ("ligado" if enabled else "desligado"))
	heads_changed.emit()
