## SaveSlotMenu - Tela de escolha de slot: continuar, começar um jogo novo ou apagar um dos 3 saves.
##
## COMO USAR: instancie SaveSlotMenu.tscn escondido dentro de uma tela (o MainMenu faz isso, do
## mesmo jeito que instancia o Settings), conecte o sinal "closed" e chame open(modo) quando o
## jogador pedir. A tela se esconde sozinha ao voltar e emite "closed" para o pai devolver os botões.
##
## A TELA NÃO GUARDA ESTADO DE SAVE: a cada open() (e depois de cada apagar) ela relê os três slots
## do SaveManager e redesenha. Quem sabe se um slot está vazio, recuperado, danificado ou é de uma
## versão mais nova é o SaveManager.get_slot_info(); aqui só se decide quais botões aparecem.
##
## QUAIS BOTÕES APARECEM: o botão principal do slot é "Continuar" ou "Novo jogo"
## conforme o estado e o modo em que a tela foi aberta; "Apagar" existe para todo slot que tem
## arquivo, exceto o de versão mais nova, que nunca é apagado nem sobrescrito. Slot danificado só
## oferece Apagar, e nunca "Novo jogo" por cima: save ilegível não vira estado novo sozinho.
##
## O RESUMO DO SLOT É DERIVADO, NUNCA GRAVADO: "Dia 5, Sexta, 14:20 — Cidade" sai do minuto do
## relógio e do local que o save guarda, montados na hora de desenhar. Por isso troca de idioma com
## os slots cheios reescreve os rótulos sem tocar no arquivo.
class_name SaveSlotMenu
extends Control

## Espaço para sinais

# Emitido pelo botão Voltar, com a tela já escondida. Signal direto, e não evento do EventBus: o único
# ouvinte é o MainMenu, pai desta tela, numa relação fixa (ver docs/event_bus.md).
signal closed

## Espaço para enums

# CONTINUE: aberta pelo "Continuar" do menu principal, e o botão principal de um slot com jogo é
# "Continuar". NEW_GAME: aberta pelo "Novo jogo", e o botão principal de um slot com jogo é "Novo
# jogo" (com confirmação). Um slot vazio oferece "Novo jogo" nos dois modos.
enum Mode { CONTINUE, NEW_GAME }

# O que o botão principal de um slot faz agora. É decidido ao desenhar o slot e guardado, para o clique
# fazer exatamente o que o texto do botão prometeu.
enum PrimaryAction { NONE, CONTINUE, NEW_GAME }

# O que o diálogo de confirmação está pedindo, para o "Sim" saber o que executar.
enum PendingAction { NONE, NEW_GAME, DELETE }

# Referências dos nós de uma linha de slot, guardadas juntas para o redesenho não buscar por caminho.
class SlotRow:
	var title: Label
	var summary: Label
	var status: Label
	var primary: Button
	var delete_button: Button

## Espaço para constantes

# Caminho de cada linha de slot, a partir da raiz da cena, e dos nós dentro de uma linha.
const SLOT_NODE_PATH_FORMAT: String = "Content/Column/Rows/Slot%d"
const TITLE_PATH: NodePath = ^"Margin/Row/Info/Title"
const SUMMARY_PATH: NodePath = ^"Margin/Row/Info/Summary"
const STATUS_PATH: NodePath = ^"Margin/Row/Info/Status"
const PRIMARY_PATH: NodePath = ^"Margin/Row/Buttons/Primary"
const DELETE_PATH: NodePath = ^"Margin/Row/Buttons/Delete"

# Largura mínima do diálogo de confirmação. A altura é 0 para o diálogo se ajustar ao texto.
const CONFIRM_DIALOG_MIN_SIZE: Vector2i = Vector2i(560, 0)

## Espaço para variáveis exportadas

## Cor do aviso de slot recuperado do backup: o jogo abre, mas o jogador deve saber.
@export var warning_color: Color = Color(1.0, 0.8, 0.3)

## Cor dos avisos de slot danificado, de versão mais nova e de erro ao abrir.
@export var error_color: Color = Color(1.0, 0.45, 0.4)

## Cor do texto "Vazio", discreto de propósito: não é aviso, só a ausência de jogo.
@export var muted_color: Color = Color(0.75, 0.75, 0.75)

## Tamanho da fonte do diálogo de confirmação. O diálogo padrão da Godot usa a fonte pequena do tema
## padrão, que numa tela de 1920x1080 ficaria ilegível ao lado do resto desta tela.
@export var confirm_font_size: int = 24

## Tamanho mínimo dos botões Sim e Não do diálogo de confirmação.
@export var confirm_button_size: Vector2 = Vector2(150.0, 56.0)

## Espaço para variáveis

var _mode: Mode = Mode.CONTINUE
var _rows: Array[SlotRow] = []
# Ação do botão principal de cada slot; o índice é o slot - 1.
var _primary_actions: Array[PrimaryAction] = []
var _pending_action: PendingAction = PendingAction.NONE
var _pending_slot: int = 0
# Botão que abriu a confirmação: recebe o foco de volta se o jogador disser "Não".
var _pending_opener: Button

## Espaço para variáveis onready

@onready var _back_button: Button = $Back
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

## Espaço para funções nativas

func _ready() -> void:
	_collect_rows()
	_style_confirm_dialog()
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirm_dialog.canceled.connect(_on_confirmation_canceled)


# Texto montado em código (título do slot, resumo, botão principal) não se retraduz sozinho quando o
# idioma muda; redesenhar refaz todos os tr(). Só faz sentido com a tela aberta: escondida, o open()
# seguinte já desenha no idioma novo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_refresh_slots()

## Espaço para funções personalizadas

# Mostra a tela no modo pedido e relê os 3 slots do disco. Relê sempre, e não só na primeira vez: o
# jogador pode ter apagado um save, ou o jogo ter gravado, desde a última abertura.
func open(mode: Mode) -> void:
	_mode = mode
	show()
	_refresh_slots()
	_focus_first_enabled_button()
	print("[SaveSlotMenu] - Tela de slots aberta no modo %s" % Mode.keys()[mode])


# Guarda as referências dos nós de cada linha de slot. Feito uma vez, no _ready(), para o redesenho não
# procurar nó por caminho a cada vez. Os três slots são montados na cena, e SLOT_COUNT precisa bater.
func _collect_rows() -> void:
	for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
		var slot_node: Node = get_node(SLOT_NODE_PATH_FORMAT % slot)
		var row: SlotRow = SlotRow.new()
		row.title = slot_node.get_node(TITLE_PATH) as Label
		row.summary = slot_node.get_node(SUMMARY_PATH) as Label
		row.status = slot_node.get_node(STATUS_PATH) as Label
		row.primary = slot_node.get_node(PRIMARY_PATH) as Button
		row.delete_button = slot_node.get_node(DELETE_PATH) as Button
		# .bind(slot) e não lambda: o botão avisa de qual slot é o clique sem uma função anônima por botão.
		row.primary.pressed.connect(_on_primary_pressed.bind(slot))
		row.delete_button.pressed.connect(_on_delete_pressed.bind(slot))
		_rows.append(row)
		_primary_actions.append(PrimaryAction.NONE)


# Aumenta a fonte e os botões do diálogo de confirmação, que por padrão saem no tamanho do tema da
# Godot. Feito por código porque os nós internos do diálogo (texto e botões) não aparecem na cena. O
# tamanho dos botões é constante de tema do diálogo (buttons_min_*): um custom_minimum_size direto
# nos botões é sobrescrito pelo próprio AcceptDialog.
func _style_confirm_dialog() -> void:
	_confirm_dialog.get_label().add_theme_font_size_override(&"font_size", confirm_font_size)
	_confirm_dialog.add_theme_font_size_override(&"title_font_size", confirm_font_size)
	_confirm_dialog.add_theme_constant_override(&"title_height", confirm_font_size + 20)
	_confirm_dialog.add_theme_constant_override(&"buttons_min_width", roundi(confirm_button_size.x))
	_confirm_dialog.add_theme_constant_override(&"buttons_min_height", roundi(confirm_button_size.y))
	var buttons: Array[Button] = [_confirm_dialog.get_ok_button(), _confirm_dialog.get_cancel_button()]
	for button: Button in buttons:
		button.add_theme_font_size_override(&"font_size", confirm_font_size)


# Relê os 3 slots e redesenha cada linha. Não mexe no foco: quem abre a tela ou apaga um slot decide.
func _refresh_slots() -> void:
	for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
		_refresh_slot(slot, SaveManager.get_slot_info(slot))


# Desenha uma linha: título, resumo e data (só se der para continuar), aviso de estado e os botões que
# o estado permite no modo atual.
func _refresh_slot(slot: int, info: SaveSlotInfo) -> void:
	var row: SlotRow = _rows[slot - 1]
	row.title.text = tr("SAVE_SLOT_TITLE") % slot

	var summary_text: String = _build_summary(info)
	row.summary.text = summary_text
	row.summary.visible = not summary_text.is_empty()

	var status_key: String = _get_status_key(info.state)
	row.status.text = tr(status_key) if not status_key.is_empty() else ""
	row.status.visible = not status_key.is_empty()
	row.status.add_theme_color_override(&"font_color", _get_status_color(info.state))

	var action: PrimaryAction = _get_primary_action(info.state)
	_primary_actions[slot - 1] = action
	row.primary.visible = action != PrimaryAction.NONE
	row.primary.text = tr("MENU_CONTINUE") if action == PrimaryAction.CONTINUE else tr("MENU_NEWGAME")
	row.delete_button.visible = _can_delete(info.state)


# Monta o resumo do slot: "Dia 5, Sexta, 14:20 — Cidade" e, na linha de baixo, a data real da gravação.
# Vazio quando não há jogo a continuar (slot vazio, danificado ou de versão mais nova): aí só o aviso
# de estado aparece. O relógio é um GameTime descartável, só para converter minutos em dia e hora.
func _build_summary(info: SaveSlotInfo) -> String:
	if not info.can_continue():
		return ""
	var game_time: GameTime = GameTime.new(GameClock.settings)
	game_time.total_minutes = _read_total_minutes(info)
	var world: Dictionary = info.get_section(GameSession.SAVE_KEY)
	# Placeholders nomeados, e não %s: cada idioma pode reordenar dia, hora e local sem mexer no código.
	var summary: String = tr("SAVE_SLOT_SUMMARY").format({
		"day": tr("DAY_LABEL") % game_time.get_day(),
		"weekday": game_time.format_weekday(),
		"time": game_time.format_clock(),
		"location": tr(GameSession.location_label_key(world)),
	})
	var saved_at_text: String = _format_saved_at(info.saved_at)
	if saved_at_text.is_empty():
		return summary
	return summary + "\n" + saved_at_text


# Lê o minuto do relógio gravado na seção "clock". Save sem a seção (v0 sem relógio) ou com valor de
# outro tipo vale 0, o dia 1 às 06:00: é o novo jogo do relógio, nunca um erro na tela de slots.
func _read_total_minutes(info: SaveSlotInfo) -> int:
	var raw_minutes: Variant = info.get_section(GameClock.SAVE_KEY).get(GameClock.MINUTES_KEY, 0)
	if raw_minutes is int or raw_minutes is float:
		return maxi(int(raw_minutes), 0)
	return 0


# Converte o Unix UTC da gravação para a data e hora locais do jogador, no formato do idioma (a ordem de
# dia e mês vem do CSV). Vazio se a data for desconhecida (saved_at = 0). O fuso é o do sistema no
# momento de desenhar, o que basta para o menu: não é um registro, é uma referência para o jogador.
func _format_saved_at(saved_at: int) -> String:
	if saved_at <= 0:
		return ""
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(saved_at + bias_minutes * 60)
	return tr("SAVE_SLOT_SAVED_AT").format({
		"month": "%02d" % int(local.get("month", 1)),
		"day": "%02d" % int(local.get("day", 1)),
		"year": "%04d" % int(local.get("year", 1970)),
		"hour": "%02d" % int(local.get("hour", 0)),
		"minute": "%02d" % int(local.get("minute", 0)),
	})


# Chave de tradução do aviso de cada estado. OCCUPIED não tem: um slot normal não precisa de aviso.
func _get_status_key(state: SaveSlotInfo.State) -> String:
	match state:
		SaveSlotInfo.State.EMPTY:
			return "SAVE_SLOT_EMPTY"
		SaveSlotInfo.State.RECOVERED:
			return "SAVE_SLOT_RECOVERED"
		SaveSlotInfo.State.DAMAGED:
			return "SAVE_SLOT_DAMAGED"
		SaveSlotInfo.State.NEWER:
			return "SAVE_SLOT_NEWER"
	return ""


# Cor do aviso: discreta para vazio, amarela para "recuperado" (abre, mas merece atenção) e vermelha
# para o que o jogador não consegue abrir.
func _get_status_color(state: SaveSlotInfo.State) -> Color:
	match state:
		SaveSlotInfo.State.RECOVERED:
			return warning_color
		SaveSlotInfo.State.DAMAGED, SaveSlotInfo.State.NEWER:
			return error_color
	return muted_color


# O que o botão principal faz: vazio sempre oferece "Novo jogo"; slot com jogo (normal ou recuperado)
# oferece "Continuar" no modo CONTINUE e "Novo jogo" no modo NEW_GAME; danificado e de versão mais
# nova não têm botão principal (o primeiro só apaga, o segundo não pode nada).
func _get_primary_action(state: SaveSlotInfo.State) -> PrimaryAction:
	match state:
		SaveSlotInfo.State.EMPTY:
			return PrimaryAction.NEW_GAME
		SaveSlotInfo.State.OCCUPIED, SaveSlotInfo.State.RECOVERED:
			return PrimaryAction.CONTINUE if _mode == Mode.CONTINUE else PrimaryAction.NEW_GAME
	return PrimaryAction.NONE


# Todo slot com arquivo pode ser apagado, exceto o de versão mais nova (o SaveManager também recusa).
func _can_delete(state: SaveSlotInfo.State) -> bool:
	return state == SaveSlotInfo.State.OCCUPIED \
		or state == SaveSlotInfo.State.RECOVERED \
		or state == SaveSlotInfo.State.DAMAGED


# Dá o foco ao primeiro botão de slot visível, na ordem da tela, e cai no Voltar se nenhum aparece
# (todos vazios de versão mais nova, por exemplo). Sem isso teclado e controle abririam a tela sem cursor.
func _focus_first_enabled_button() -> void:
	for row: SlotRow in _rows:
		var buttons: Array[Button] = [row.primary, row.delete_button]
		for button: Button in buttons:
			if button.visible and not button.disabled:
				button.grab_focus()
				return
	_back_button.grab_focus()


# Continua a partida do slot. Em erro (o save mudou ou apodreceu desde que a tela foi desenhada) a
# tela não troca de cena: relê os slots e marca o slot com o aviso de erro.
func _continue_slot(slot: int) -> void:
	var result: Error = SaveManager.continue_game(slot)
	if result != OK:
		print("[SaveSlotMenu] - Não foi possível continuar o slot %d (%s)" % [slot, error_string(result)])
		_refresh_slots()
		_show_open_error(slot)
		return
	# A cena vem do local gravado (seção "world"), não de uma constante: o menu não conhece cenas.
	var scene_path: String = GameSession.scene_path_for(SaveManager.get_section(GameSession.SAVE_KEY))
	print("[SaveSlotMenu] - Slot %d aberto, carregando \"%s\"" % [slot, scene_path])
	GameManager.change_scene(scene_path)


# Pede um jogo novo no slot. Slot vazio vai direto; slot com jogo pede confirmação antes. O
# estado é relido porque a tela pode estar desatualizada: se o slot virou danificado ou de versão mais
# nova, o SaveManager recusaria, então só se redesenha.
func _request_new_game(slot: int) -> void:
	var info: SaveSlotInfo = SaveManager.get_slot_info(slot)
	match info.state:
		SaveSlotInfo.State.EMPTY:
			_start_new_game(slot)
		SaveSlotInfo.State.OCCUPIED, SaveSlotInfo.State.RECOVERED:
			_ask_confirmation(PendingAction.NEW_GAME, slot, _rows[slot - 1].primary)
		_:
			_refresh_slots()
			_focus_first_enabled_button()


# Começa a partida do zero e vai para a cena inicial. start_new_game devolve OK sempre que a partida
# abriu, mesmo se a primeira gravação falhou: o indicador do SaveManager já avisou, o jogo segue.
func _start_new_game(slot: int) -> void:
	var result: Error = SaveManager.start_new_game(slot)
	if result != OK:
		print("[SaveSlotMenu] - Não foi possível começar um jogo novo no slot %d (%s)" % [slot, error_string(result)])
		_refresh_slots()
		_show_open_error(slot)
		return
	# {} é o "novo jogo" da seção world: a GameSession devolve a cena padrão, e nenhuma cena fica escrita aqui.
	var scene_path: String = GameSession.scene_path_for({})
	print("[SaveSlotMenu] - Jogo novo no slot %d, carregando \"%s\"" % [slot, scene_path])
	GameManager.change_scene(scene_path)


# Apaga os arquivos do slot e redesenha a tela. O foco volta ao primeiro botão: o botão Apagar que
# acabou de ser clicado some junto com o save.
func _delete_slot(slot: int) -> void:
	var result: Error = SaveManager.delete_slot(slot)
	if result != OK:
		print("[SaveSlotMenu] - Não foi possível apagar o slot %d (%s)" % [slot, error_string(result)])
	else:
		print("[SaveSlotMenu] - Slot %d apagado pelo jogador" % slot)
	_refresh_slots()
	_focus_first_enabled_button()


# Troca o aviso do slot pelo erro ao abrir. Vem depois do _refresh_slots(), que escreveria por cima.
func _show_open_error(slot: int) -> void:
	var row: SlotRow = _rows[slot - 1]
	row.status.text = tr("SAVE_ERROR_OPEN")
	row.status.add_theme_color_override(&"font_color", error_color)
	row.status.show()


# Abre o diálogo de confirmação para a ação destrutiva. O título é o nome do slot ("Slot 2") porque o
# título padrão do diálogo da Godot é um texto em inglês que não passa pelo CSV. Os botões Sim e Não
# são atribuídos a cada abertura, para acompanharem o idioma atual. O foco inicial é o "Não": Enter ou
# o botão de confirmar do controle não podem apagar um save por reflexo.
func _ask_confirmation(action: PendingAction, slot: int, opener: Button) -> void:
	_pending_action = action
	_pending_slot = slot
	_pending_opener = opener
	var text_key: String = "SAVE_CONFIRM_OVERWRITE" if action == PendingAction.NEW_GAME else "SAVE_CONFIRM_DELETE"
	_confirm_dialog.title = tr("SAVE_SLOT_TITLE") % slot
	_confirm_dialog.dialog_text = tr(text_key) % slot
	_confirm_dialog.ok_button_text = tr("SAVE_CONFIRM_YES")
	_confirm_dialog.cancel_button_text = tr("SAVE_CONFIRM_NO")
	_confirm_dialog.popup_centered(CONFIRM_DIALOG_MIN_SIZE)
	_confirm_dialog.get_cancel_button().grab_focus()
	print("[SaveSlotMenu] - Confirmação pedida (%s) para o slot %d" % [PendingAction.keys()[action], slot])


# Esquece a confirmação pendente. Chamado antes de executar ou de descartar, para o próximo diálogo
# nunca herdar a ação do anterior.
func _clear_pending() -> void:
	_pending_action = PendingAction.NONE
	_pending_slot = 0
	_pending_opener = null


# Clique no botão principal do slot. A ação vem do que foi desenhado (_primary_actions), para o clique
# fazer o que o texto do botão dizia. Ignorado durante troca de cena: um segundo clique no fade chamaria
# continue_game e change_scene duas vezes.
func _on_primary_pressed(slot: int) -> void:
	if GameManager.in_transition:
		return
	match _primary_actions[slot - 1]:
		PrimaryAction.CONTINUE:
			_continue_slot(slot)
		PrimaryAction.NEW_GAME:
			_request_new_game(slot)


# Clique em Apagar. Relê o estado antes de perguntar: se o slot já não tem o que apagar, só redesenha.
func _on_delete_pressed(slot: int) -> void:
	if GameManager.in_transition:
		return
	if not _can_delete(SaveManager.get_slot_info(slot).state):
		_refresh_slots()
		_focus_first_enabled_button()
		return
	_ask_confirmation(PendingAction.DELETE, slot, _rows[slot - 1].delete_button)


# "Sim" no diálogo: executa a ação guardada. A confirmação é limpa primeiro, antes de qualquer troca de
# cena ou redesenho, para não sobrar pendência se a ação falhar.
func _on_confirmation_confirmed() -> void:
	var action: PendingAction = _pending_action
	var slot: int = _pending_slot
	_clear_pending()
	if GameManager.in_transition:
		return
	match action:
		PendingAction.NEW_GAME:
			_start_new_game(slot)
		PendingAction.DELETE:
			_delete_slot(slot)


# "Não", Esc ou o X da janela: descarta a ação e devolve o foco ao botão que abriu o diálogo. O
# canceled também chega quando a janela fecha por fora do fluxo normal, então a checagem de opener
# não é decoração.
func _on_confirmation_canceled() -> void:
	var opener: Button = _pending_opener
	var slot: int = _pending_slot
	_clear_pending()
	print("[SaveSlotMenu] - Confirmação do slot %d cancelada" % slot)
	if opener != null and opener.is_visible_in_tree():
		opener.grab_focus()


# Voltar: esconde a tela e avisa o pai, que devolve os botões do menu principal.
func _on_back_pressed() -> void:
	if GameManager.in_transition:
		return
	hide()
	closed.emit()
	print("[SaveSlotMenu] - Tela de slots fechada")
