# SaveManager.gd — Autoload: dono da partida ativa e único escritor dos arquivos de save.
#
# Cada sistema com fatos a guardar se REGISTRA aqui com uma chave e um par de Callables (o seu
# to_dict/from_dict). Quem muda estado só PEDE gravação (request_save), e o SaveManager junta os
# pedidos numa escrita só, no começo do frame seguinte. O arquivo é um retrato de fatos: cada
# participante devolve ids e números, nunca texto traduzido nem objeto da engine.
#
# SEM PARTIDA ATIVA, NADA GRAVA: no menu principal e numa cena rodada direto pelo editor (F6) não
# existe slot, então request_save() e save_now() não criam arquivo nenhum. Quem abre a
# partida é o menu de slots (start_new_game/continue_game) ou o debug (F4 -> Save).
#
# REGISTRO TARDIO RECEBE A SEÇÃO NA HORA: com partida ativa, register_participant() já chama o
# load_callable com a seção guardada. É o que deixa participante static (DialogueState, que registra
# na primeira consulta) e participante de cena (GameSession) entrarem sem caso especial.
#
# GRAVAÇÃO ATÔMICA: o texto vai inteiro para saveN.json.tmp e só depois vira o principal; o principal
# anterior vira saveN.json.bak. A Godot no Windows não troca arquivo de forma atômica (rename com
# destino existente apaga o destino antes de mover), então NUNCA se renomeia por cima do principal —
# ver _write_atomically().
#
# LER NUNCA MUDA O DISCO: get_slot_info() só lê, com fallback principal -> .tmp -> .bak. Save ilegível
# vira DAMAGED, nunca EMPTY; save de versão mais nova (NEWER) não é aberto, apagado nem sobrescrito por
# caminho nenhum. Save antigo migra na leitura, e o disco só muda na próxima gravação.
#
# O guia de uso está em docs/SaveManager.md.
extends Node

## Espaço para sinais

# Emitido quando uma partida abre (novo jogo ou continuar), depois de TODOS os participantes
# receberem a sua seção. É para quem não guarda nada no save mas não pode levar estado de uma
# partida para a outra (o Diary): ele recomeça aqui, já com os fatos da partida nova carregados.
# Não é evento de bus: é a relação direta e permanente entre o dono da sessão e quem depende dela,
# que docs/event_bus.md manda resolver com signal direto.
signal session_opened(slot: int)

## Espaço para constantes

const SLOT_COUNT: int = 3
# Valor de _active_slot sem partida ativa. Os slots de verdade são 1..SLOT_COUNT.
const NO_SLOT: int = 0
# Versão do FORMATO do arquivo, não do jogo. Só sobe junto com um passo _migrate_vN_to_vN1 novo.
const FORMAT_VERSION: int = 1
# Mesmo nome de arquivo de antes do envelope: o save1.json de desenvolvimento abre como versão 0.
const FILE_NAME_FORMAT: String = "save%d.json"
const TEMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const VERSION_KEY: String = "version"
const SAVED_AT_KEY: String = "saved_at"
const DATA_KEY: String = "data"
const INDICATOR_SCENE_PATH: String = "res://scenes/ui/SaveIndicator.tscn"
const DEBUG_SECTION: StringName = &"Save"
# Quantos caracteres de cada seção o "Listar slots" do debug imprime. Uma seção de profiling inteira
# numa linha só afogaria o log.
const DEBUG_SUMMARY_LENGTH: int = 160

## Espaço para variáveis

# Pasta dos slots; sempre termina em "/".
var save_directory: String = "user://"
# Liga os pedidos (request_save). save_now() grava sempre. Autotestes e debug desligam.
var autosave_enabled: bool = true

var _active_slot: int = NO_SLOT
# Seções da partida ativa, por chave de participante. Guarda também chave que ninguém registrou
# (outra branch, sistema removido, participante de cena descarregado): ela volta ao disco intacta a
# cada gravação, em vez de sumir na primeira.
var _sections: Dictionary = {}
var _savers: Dictionary[String, Callable] = {}
var _loaders: Dictionary[String, Callable] = {}
# Há um pedido de gravação esperando o próximo frame. É o que junta vários pedidos numa escrita.
var _save_pending: bool = false
# O principal do slot ativo é uma cópia boa? Decide o que a próxima gravação faz com ele: se é bom,
# vira .bak; se a sessão veio do .tmp/.bak (principal podre), é apagado — senão empurraria o último
# .bak bom para fora. true depois de gravar ou de abrir pelo principal; false no resto.
var _main_known_good: bool = false
# Gravações bem-sucedidas desde o boot. Só o "Estado da sessão" do debug lê.
var _write_count: int = 0
var _indicator: SaveIndicator

## Espaço para funções nativas

func _ready() -> void:
	# Virada de dia é gesto de progresso. O pedido cai no frame seguinte, com o dia novo já em
	# vigor e as emoções já promovidas pelo NPCDirector no mesmo frame da virada.
	EventBus.day_changed.connect(_on_day_changed)
	_indicator = _create_indicator()
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Save" do menu (F4) e do console (F1). Adiado porque o SaveManager é o primeiro
		# Autoload: registrar agora poria "Save" antes de "Sistema", que o DebugMenu promete ser a
		# primeira seção (ver docs/debug_menu.md).
		_register_debug_entries.call_deferred()


# Fechar a janela (X, Alt+F4) grava antes de a Godot sair. Não se mexe em auto_accept_quit: a
# notificação chega com o padrão true, e a gravação síncrona termina antes do quit. get_tree().quit()
# NÃO emite esta notificação, por isso todo botão de sair do jogo passa por end_session() antes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and has_active_session():
		print("[Save] - Janela fechando, gravando o slot %d" % _active_slot)
		save_now()

## Espaço para funções personalizadas

# --- Sessão ---

# Partida do zero: fecha a sessão anterior gravando, apaga os arquivos do slot, zera todos os
# participantes e grava na hora. Recusa DAMAGED (ERR_FILE_CORRUPT) e NEWER (ERR_FILE_UNRECOGNIZED):
# save ilegível só sai pelo Apagar e save de versão mais nova nunca é sobrescrito. A confirmação de
# substituir um slot ocupado é da UI, antes de chamar.
# Devolve OK sempre que a partida abriu, mesmo se a primeira gravação falhar: o indicador já avisou, a
# sessão segue e a próxima gravação tenta de novo. Erro = partida NÃO aberta.
func start_new_game(slot: int) -> Error:
	if not _is_valid_slot(slot):
		return ERR_PARAMETER_RANGE_ERROR
	var info: SaveSlotInfo = get_slot_info(slot)
	if info.state == SaveSlotInfo.State.DAMAGED or info.state == SaveSlotInfo.State.NEWER:
		push_warning("[Save] - AVISO: novo jogo recusado no slot %d (%s)" % [slot, _state_name(info.state)])
		return _state_error(info.state)
	end_session()
	var removed: Error = _remove_slot_files(slot)
	if removed != OK:
		push_error("[Save] - ERRO: não foi possível limpar o slot %d para o novo jogo (%s)"
			% [slot, error_string(removed)])
		return removed
	print("[Save] - Novo jogo no slot %d" % slot)
	_open_session(slot, {}, false)
	save_now()
	return OK


# Abre a partida do slot: lê com fallback (principal -> .tmp -> .bak), migra e entrega cada seção ao
# seu participante — a TODOS os registrados, então nada da partida anterior sobra na memória.
# Não grava nada: o disco só muda (e só vira v1) na próxima gravação. Se já havia partida ativa, ela
# é fechada gravando antes; a validação vem primeiro para um slot vazio não derrubar a sessão atual.
func continue_game(slot: int) -> Error:
	if not _is_valid_slot(slot):
		return ERR_PARAMETER_RANGE_ERROR
	var info: SaveSlotInfo = get_slot_info(slot)
	if not info.can_continue():
		push_warning("[Save] - AVISO: slot %d não pode ser aberto (%s)" % [slot, _state_name(info.state)])
		return _state_error(info.state)
	if has_active_session():
		end_session()
		# A gravação de saída pode ter reescrito este mesmo slot: relê para abrir o que acabou de ir
		# para o disco, e não o retrato de antes dela.
		info = get_slot_info(slot)
		if not info.can_continue():
			return _state_error(info.state)
	if info.state == SaveSlotInfo.State.RECOVERED:
		push_warning("[Save] - AVISO: slot %d aberto por uma cópia (.tmp ou .bak); o principal estava danificado ou incompleto" % slot)
	if info.version < FORMAT_VERSION:
		print("[Save] - Slot %d migrado da versão %d para a %d (o arquivo muda na próxima gravação)"
			% [slot, info.version, FORMAT_VERSION])
	_open_session(slot, info.sections, info.loaded_from_main)
	print("[Save] - Slot %d aberto (%s, %d seções)" % [slot, _state_name(info.state), _sections.size()])
	return OK


# Grava (save_now) e fecha a partida ativa. Sem partida ativa, não faz nada — é por isso que o menu
# principal pode chamar isto no _ready() como rede de segurança. Fecha mesmo se a gravação falhar:
# o indicador já avisou, e manter a sessão aberta no menu só deixaria um slot preso.
func end_session() -> void:
	if not has_active_session():
		return
	var slot: int = _active_slot
	save_now()
	_close_session()
	print("[Save] - Sessão do slot %d encerrada" % slot)


# Apaga principal, .tmp e .bak do slot. Se for a partida ativa, fecha a sessão SEM gravar e zera o
# pedido pendente: senão o próximo flush recriaria o arquivo que o jogador acabou de apagar.
# Recusa NEWER (ERR_FILE_UNRECOGNIZED). Slot vazio devolve OK: não há o que apagar.
func delete_slot(slot: int) -> Error:
	if not _is_valid_slot(slot):
		return ERR_PARAMETER_RANGE_ERROR
	var info: SaveSlotInfo = get_slot_info(slot)
	if info.state == SaveSlotInfo.State.NEWER:
		push_warning("[Save] - AVISO: slot %d é de uma versão mais nova do jogo; não será apagado" % slot)
		return ERR_FILE_UNRECOGNIZED
	if _active_slot == slot:
		_close_session()
		print("[Save] - Slot %d era a partida ativa: sessão fechada sem gravar" % slot)
	var removed: Error = _remove_slot_files(slot)
	if removed != OK:
		push_error("[Save] - ERRO: não foi possível apagar o slot %d (%s)" % [slot, error_string(removed)])
		return removed
	print("[Save] - Slot %d apagado" % slot)
	return OK


# Estado do slot para o menu. Só lê: nunca cria, move nem apaga arquivo. A ordem é principal
# -> .tmp -> .bak: um .tmp completo nunca é mais velho que o .bak, porque toda gravação reescreve o
# .tmp antes de mexer no resto. Achar uma versão mais nova para tudo na hora, sem olhar os outros.
func get_slot_info(slot: int) -> SaveSlotInfo:
	var info: SaveSlotInfo = SaveSlotInfo.new()
	info.slot = slot
	if not _is_valid_slot(slot):
		return info
	var candidates: PackedStringArray = _slot_files(slot)
	var found_damaged: bool = false
	for index: int in candidates.size():
		var path: String = candidates[index]
		if not FileAccess.file_exists(path):
			continue
		if not _read_candidate(path, info):
			found_damaged = true
			continue
		if info.version > FORMAT_VERSION:
			info.state = SaveSlotInfo.State.NEWER
			return info
		info.sections = _migrate(info.sections, info.version)
		info.loaded_from_main = index == 0
		info.state = SaveSlotInfo.State.OCCUPIED if index == 0 else SaveSlotInfo.State.RECOVERED
		return info
	info.state = SaveSlotInfo.State.DAMAGED if found_damaged else SaveSlotInfo.State.EMPTY
	return info


# Existe algum arquivo de slot, em qualquer estado? É o que habilita o "Continuar" do menu principal.
# Só file_exists, sem abrir nada: um slot danificado também conta, porque o jogador precisa chegar
# nele para apagar.
func has_any_save() -> bool:
	for slot: int in range(1, SLOT_COUNT + 1):
		for path: String in _slot_files(slot):
			if FileAccess.file_exists(path):
				return true
	return false


# Há partida ativa? É false no menu e numa cena rodada direto pelo editor.
func has_active_session() -> bool:
	return _active_slot != NO_SLOT


# Slot da partida ativa, ou NO_SLOT.
func get_active_slot() -> int:
	return _active_slot


# Cópia da seção da partida ativa ({} sem sessão, ou se a chave faltar). Cópia funda de propósito:
# quem lê (o menu escolhe a cena pela seção "world") não pode mexer por fora no que vai para o disco.
func get_section(key: String) -> Dictionary:
	var section: Variant = _sections.get(key, {})
	if section is Dictionary:
		return (section as Dictionary).duplicate(true)
	return {}

# --- Participantes ---

# Registra (ou substitui) o dono de uma chave. Com partida ativa, chama load_callable na hora com a
# seção guardada: é o registro tardio que resolve participante static e de cena sem caso especial.
# Sem partida ativa (Autoloads no boot), só guarda: quem entrega a seção é o continue_game.
func register_participant(key: String, save_callable: Callable, load_callable: Callable) -> void:
	if key.is_empty() or not save_callable.is_valid() or not load_callable.is_valid():
		push_error("[Save] - ERRO: registro de participante inválido (chave \"%s\")" % key)
		return
	_savers[key] = save_callable
	_loaders[key] = load_callable
	if has_active_session():
		print("[Save] - Participante \"%s\" registrado com a partida aberta; seção entregue na hora" % key)
		load_callable.call(get_section(key))
	else:
		print("[Save] - Participante \"%s\" registrado" % key)


# Tira o participante. A seção fica em _sections, e a próxima gravação a preserva: participante de
# cena que sai (troca de cena) não pode apagar o que gravou.
func unregister_participant(key: String) -> void:
	if not _savers.has(key):
		return
	_savers.erase(key)
	_loaders.erase(key)
	print("[Save] - Participante \"%s\" saiu do save" % key)

# --- Gravação ---

# Marca o pedido e agenda uma escrita para o começo do próximo frame. Pedidos até lá viram uma
# escrita só. Sem sessão, ou com o autosave desligado, não faz nada.
func request_save() -> void:
	if not autosave_enabled or not has_active_session() or _save_pending:
		return
	_save_pending = true
	_schedule_flush()


# Grava já, de forma síncrona. É o caminho de sair para o menu e de fechar a janela. Zera o pedido
# pendente: o flush agendado sai sem fazer nada, e o gesto não vira uma segunda escrita.
func save_now() -> Error:
	if not has_active_session():
		return ERR_UNAVAILABLE
	_save_pending = false
	return _save_active_session()


# Conecta o flush ao process_frame do próximo frame. process_frame, e não call_deferred: um flush
# adiado rodaria no meio da fila de deferreds, e um call_deferred de outro sistema (o DialogueRunner
# entrega o passo assim) cairia depois dele, com segunda escrita. O process_frame seguinte vem depois
# de toda a cascata do gesto. ONE_SHOT com is_connected(): na Godot 4.7 a conexão ONE_SHOT já está
# desfeita quando o callback roda, então reagendar de dentro do flush funciona.
func _schedule_flush() -> void:
	if not get_tree().process_frame.is_connected(_flush_pending_save):
		get_tree().process_frame.connect(_flush_pending_save, CONNECT_ONE_SHOT)


# Executa o pedido. Durante troca de cena espera o fade acabar: no meio da troca a cena velha
# já saiu e a nova ainda não registrou, e o retrato sairia sem o participante de cena.
func _flush_pending_save() -> void:
	if not _save_pending:
		return
	if GameManager.in_transition:
		_schedule_flush()
		return
	_save_pending = false
	_save_active_session()


# Recolhe as seções dos participantes, monta o envelope e grava. Participante com Callable inválido
# (nó liberado sem unregister) é descartado com aviso; a seção dele fica como estava.
func _save_active_session() -> Error:
	var started_usec: int = Time.get_ticks_usec()
	for key: String in _savers.keys():
		var saver: Callable = _savers[key]
		if not saver.is_valid():
			_drop_invalid_participant(key)
			continue
		var section: Variant = saver.call()
		if section is Dictionary:
			_sections[key] = section
		else:
			push_warning("[Save] - AVISO: participante \"%s\" não devolveu Dictionary; seção anterior mantida" % key)
	var envelope: Dictionary = {
		VERSION_KEY: FORMAT_VERSION,
		SAVED_AT_KEY: int(Time.get_unix_time_from_system()),
		DATA_KEY: _sections,
	}
	# Tab e chaves ordenadas (padrão do stringify): o arquivo fica legível e comparável à mão.
	var text: String = JSON.stringify(envelope, "\t")
	var result: Error = _write_atomically(_active_slot, text)
	var elapsed_ms: int = roundi((Time.get_ticks_usec() - started_usec) / 1000.0)
	if result != OK:
		push_error("[Save] - ERRO: falha ao gravar o slot %d (%s); o save anterior ficou intacto"
			% [_active_slot, error_string(result)])
		if _indicator != null:
			_indicator.show_failed()
		return result
	_write_count += 1
	print("[Save] - Slot %d gravado (%d bytes, %d ms)" % [_active_slot, text.to_utf8_buffer().size(), elapsed_ms])
	if _indicator != null:
		_indicator.show_saved()
	return OK


# Grava o texto no slot sem nunca deixar só um arquivo pela metade. Em qualquer ponto de
# queda, a leitura (principal -> .tmp -> .bak) acha o save anterior ou o novo inteiro.
func _write_atomically(slot: int, text: String) -> Error:
	var main_path: String = _slot_path(slot)
	var temp_path: String = main_path + TEMP_SUFFIX
	# 1. O texto inteiro vai para o .tmp. Principal e .bak intocados.
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored: bool = file.store_string(text)
	file.close()
	if not stored:
		DirAccess.remove_absolute(temp_path)
		return ERR_FILE_CANT_WRITE
	# 2. O principal sai do caminho: vira .bak se era bom; se estava podre, é apagado, senão
	#    empurraria o último .bak bom para fora.
	if FileAccess.file_exists(main_path):
		var moved: Error = DirAccess.rename_absolute(main_path, main_path + BACKUP_SUFFIX) \
			if _main_known_good else DirAccess.remove_absolute(main_path)
		if moved != OK:
			return moved
	# 3. O .tmp vira principal. O destino não existe, então nada é apagado no caminho.
	var promoted: Error = DirAccess.rename_absolute(temp_path, main_path)
	if promoted == OK:
		_main_known_good = true
	return promoted


# Lê e valida um arquivo candidato do slot, preenchendo versão, data e seções em info. Devolve false
# se o arquivo for inválido: vazio, não parseia, não é objeto, versão sem sentido, ou v1+ sem "data"
# objeto. Não migra nem decide o estado: isso é de get_slot_info().
func _read_candidate(path: String, info: SaveSlotInfo) -> bool:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	# JSON.new().parse(), e não JSON.parse_string(): o segundo imprime erro a cada arquivo podre, e
	# achar um slot danificado é caminho previsto (o menu relê os três slots a cada abertura).
	if text.is_empty() or json.parse(text) != OK or json.data is not Dictionary:
		return false
	var envelope: Dictionary = json.data
	if not envelope.has(VERSION_KEY):
		# v0: save de desenvolvimento, sem envelope. O objeto inteiro vira "data", e a data da
		# gravação sai do próprio arquivo, o único registro que existe.
		info.version = 0
		info.saved_at = FileAccess.get_modified_time(path)
		info.sections = envelope
		return true
	var raw_version: Variant = envelope[VERSION_KEY]
	if not (raw_version is float or raw_version is int) or int(raw_version) < 1:
		return false
	if int(raw_version) > FORMAT_VERSION:
		# Formato desconhecido: além da versão, nada deste arquivo é confiável para ler.
		info.version = int(raw_version)
		return true
	var data: Variant = envelope.get(DATA_KEY)
	if data is not Dictionary:
		return false
	var raw_saved_at: Variant = envelope.get(SAVED_AT_KEY, 0)
	info.version = int(raw_version)
	info.saved_at = int(raw_saved_at) if (raw_saved_at is float or raw_saved_at is int) else 0
	info.sections = data
	return true


# Leva as seções da versão lida até FORMAT_VERSION, um passo por versão. Aplicada na leitura: o disco
# só muda na próxima gravação, já no formato atual.
func _migrate(sections: Dictionary, from_version: int) -> Dictionary:
	var migrated: Dictionary = sections
	if from_version < 1:
		migrated = _migrate_v0_to_v1(migrated)
	return migrated


# v0 -> v1: o antigo GameClock.write_to_save gravava total_minutes no topo; no envelope o relógio é a
# seção "clock". Literais, e não GameClock.SAVE_KEY: migração é história congelada, e o dono pode
# renomear a própria constante depois sem mudar o que um save v0 significa.
func _migrate_v0_to_v1(sections: Dictionary) -> Dictionary:
	if sections.has("total_minutes"):
		sections["clock"] = { "total_minutes": sections["total_minutes"] }
		sections.erase("total_minutes")
	return sections


# Abre a sessão em memória e entrega a seção de cada participante registrado. Um participante que não
# tem seção recebe {}, que é o novo jogo dele. Só depois avisa session_opened, para quem recomeça ali
# já encontrar os fatos da partida nova.
func _open_session(slot: int, sections: Dictionary, from_main: bool) -> void:
	_active_slot = slot
	_sections = sections
	_main_known_good = from_main
	_save_pending = false
	for key: String in _loaders.keys():
		# Um loader que já rodou pode ter tirado outro participante (uma cena reagindo ao load).
		if not _loaders.has(key):
			continue
		var loader: Callable = _loaders[key]
		if not loader.is_valid():
			_drop_invalid_participant(key)
			continue
		loader.call(get_section(key))
	session_opened.emit(slot)


# Fecha a sessão sem gravar. Zera o pedido pendente junto: o flush já agendado sai sem fazer nada.
func _close_session() -> void:
	_active_slot = NO_SLOT
	_sections = {}
	_save_pending = false
	_main_known_good = false


# Descarta um participante cujo Callable morreu (o nó saiu da árvore sem unregister_participant). É
# rede de segurança, não caminho: participante de cena deve sair no _exit_tree().
func _drop_invalid_participant(key: String) -> void:
	push_warning("[Save] - AVISO: participante \"%s\" com Callable inválido descartado (faltou unregister_participant?)" % key)
	_savers.erase(key)
	_loaders.erase(key)


# Apaga principal, .tmp e .bak do slot. Tenta os três mesmo se um falhar e devolve o primeiro erro.
func _remove_slot_files(slot: int) -> Error:
	var first_error: Error = OK
	for path: String in _slot_files(slot):
		if not FileAccess.file_exists(path):
			continue
		var removed: Error = DirAccess.remove_absolute(path)
		if removed != OK and first_error == OK:
			first_error = removed
	return first_error


# Caminho do arquivo principal do slot, dentro de save_directory.
func _slot_path(slot: int) -> String:
	return save_directory.path_join(FILE_NAME_FORMAT % slot)


# Os três arquivos do slot, na ordem de leitura: principal, .tmp e .bak.
func _slot_files(slot: int) -> PackedStringArray:
	var main_path: String = _slot_path(slot)
	return PackedStringArray([main_path, main_path + TEMP_SUFFIX, main_path + BACKUP_SUFFIX])


# Confere se o slot está em 1..SLOT_COUNT, com erro no console quando não está: slot fora da faixa é
# bug de quem chamou, e não pode virar um arquivo save0.json ou save4.json no disco.
func _is_valid_slot(slot: int) -> bool:
	if slot >= 1 and slot <= SLOT_COUNT:
		return true
	push_error("[Save] - ERRO: slot %d fora de 1..%d" % [slot, SLOT_COUNT])
	return false


# Erro que a API devolve para um slot que não dá para abrir, conforme o estado dele.
func _state_error(state: SaveSlotInfo.State) -> Error:
	match state:
		SaveSlotInfo.State.EMPTY:
			return ERR_FILE_NOT_FOUND
		SaveSlotInfo.State.DAMAGED:
			return ERR_FILE_CORRUPT
		SaveSlotInfo.State.NEWER:
			return ERR_FILE_UNRECOGNIZED
	return OK


# Nome do estado para os prints (OCCUPIED, DAMAGED...).
func _state_name(state: SaveSlotInfo.State) -> String:
	return SaveSlotInfo.State.keys()[state]


# Instancia o indicador de gravado/falha como filho. Filho do SaveManager, e não da cena de jogo, para
# sobreviver à troca de cena. Sem a cena, o save continua funcionando, só que sem aviso visual.
func _create_indicator() -> SaveIndicator:
	var scene: PackedScene = load(INDICATOR_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Save] - ERRO: cena do indicador não encontrada em %s" % INDICATOR_SCENE_PATH)
		return null
	var indicator: SaveIndicator = scene.instantiate() as SaveIndicator
	add_child(indicator)
	return indicator


# Pedido de gravação na virada de dia.
func _on_day_changed(_day: int) -> void:
	request_save()


# [DEBUG] Entradas da seção "Save". Operam na partida ativa; "Salvar automático" substitui os
# toggles que cada diário tinha. Não existem em build de release.
func _register_debug_entries() -> void:
	DebugMenu.register_action(DEBUG_SECTION, "Estado da sessão", _debug_print_session)
	DebugMenu.register_action(DEBUG_SECTION, "Listar slots", _debug_list_slots)
	DebugMenu.register_action(DEBUG_SECTION, "Salvar agora", _debug_save_now)
	DebugMenu.register_input(DEBUG_SECTION, "Continuar slot", _debug_continue_slot,
		[DebugParam.int_value("slot", 1, 1, SLOT_COUNT)])
	DebugMenu.register_input(DEBUG_SECTION, "Novo jogo no slot", _debug_start_new_game,
		[DebugParam.int_value("slot", 1, 1, SLOT_COUNT)], true)
	DebugMenu.register_input(DEBUG_SECTION, "Apagar slot", _debug_delete_slot,
		[DebugParam.int_value("slot", 1, 1, SLOT_COUNT)], true)
	DebugMenu.register_toggle(DEBUG_SECTION, "Salvar automático", _debug_set_autosave, autosave_enabled)


# [DEBUG] Imprime slot ativo, pendência, contador e quem está registrado.
func _debug_print_session() -> void:
	var session_text: String = ("slot %d" % _active_slot) if has_active_session() else "nenhuma"
	print("[Save] - Sessão: %s | pedido pendente: %s | gravações: %d | autosave: %s"
		% [session_text, _save_pending, _write_count, "ligado" if autosave_enabled else "desligado"])
	print("[Save] - Participantes: %s | seções na memória: %s" % [_savers.keys(), _sections.keys()])


# [DEBUG] Imprime estado, versão, data e um resumo cru das seções dos três slots.
func _debug_list_slots() -> void:
	for slot: int in range(1, SLOT_COUNT + 1):
		var info: SaveSlotInfo = get_slot_info(slot)
		var saved_at_text: String = "desconhecida" if info.saved_at == 0 \
			else Time.get_datetime_string_from_unix_time(info.saved_at, true) + " UTC"
		print("[Save] - Slot %d: %s, versão %d, gravado em %s"
			% [slot, _state_name(info.state), info.version, saved_at_text])
		for key: String in info.sections.keys():
			print("[Save] -     %s: %s" % [key, JSON.stringify(info.sections[key]).left(DEBUG_SUMMARY_LENGTH)])


# [DEBUG] Grava a partida ativa agora.
func _debug_save_now() -> void:
	if not has_active_session():
		print("[Save] - Sem partida ativa: nada a gravar")
		return
	save_now()


# [DEBUG] Abre o slot e recarrega a cena atual, para a cena montar já com a partida aberta. É o jeito
# de jogar com progresso depois de rodar uma cena direto pelo editor (F6), que não abre sessão.
func _debug_continue_slot(slot: int) -> void:
	var result: Error = continue_game(slot)
	if result != OK:
		print("[Save] - Continuar slot %d falhou: %s" % [slot, error_string(result)])
		return
	_debug_reload_current_scene()


# [DEBUG] Novo jogo no slot e recarrega a cena atual.
func _debug_start_new_game(slot: int) -> void:
	var result: Error = start_new_game(slot)
	if result != OK:
		print("[Save] - Novo jogo no slot %d falhou: %s" % [slot, error_string(result)])
		return
	_debug_reload_current_scene()


# [DEBUG] Apaga o slot. Se for a partida ativa, a sessão fecha sem gravar e nada recria o arquivo.
func _debug_delete_slot(slot: int) -> void:
	var result: Error = delete_slot(slot)
	if result != OK:
		print("[Save] - Apagar slot %d falhou: %s" % [slot, error_string(result)])


# [DEBUG] Liga/desliga os pedidos de gravação (save_now continua gravando).
func _debug_set_autosave(enabled: bool) -> void:
	autosave_enabled = enabled
	print("[Save] - Salvamento automático %s" % ("ligado" if enabled else "desligado"))


# [DEBUG] Recarrega a cena atual pelo GameManager (com fade, e o relógio congelado na troca). Tira a
# pausa antes, como o "Recarregar cena" do DebugMenu: com a árvore pausada o fade nunca terminaria.
func _debug_reload_current_scene() -> void:
	var current: Node = get_tree().current_scene
	if current == null or current.scene_file_path.is_empty():
		print("[Save] - Sem cena para recarregar; a partida do slot %d está aberta" % _active_slot)
		return
	get_tree().paused = false
	GameManager.change_scene(current.scene_file_path)
