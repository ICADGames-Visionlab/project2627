# Diary.gd — Autoload: protótipo de diário/livro navegável pelo jogador.
#
# Guarda as páginas do diário e decide quando ele está aberto ou fechado. Não desenha nada: quem
# monta a tela é a DiaryOverlay (res://scenes/ui/DiaryOverlay.tscn), instanciada sob demanda na
# primeira vez que o jogador aperta a tecla — enquanto ninguém abre o diário, a UI não existe e não
# custa nada (mesmo truque do DebugMenu com o menu de debug, ver _toggle_menu() em DebugMenu.gd).
#
# CONTEÚDO É CHAMADA DE FUNÇÃO, NÃO DADO ESTÁTICO: outros sistemas adicionam páginas chamando
# Diary.add_page() de qualquer lugar do projeto, sem precisar conhecer a UI nem esperar o diário
# estar aberto. É o gancho pensado pro dia em que o diário passar a guardar entradas de missão,
# lore, dicas etc. — ver docs/diary.md pro guia completo de como escalar isso (persistência,
# categorias, condições de desbloqueio).
#
# PÁGINA = CHAVE DE TRADUÇÃO, NUNCA TEXTO PRONTO: segue a mesma regra do resto do projeto (ver
# GUIDELINE_PROGRAMACAO.md, "Strings e Localização"). Quem chama add_page() passa a chave do CSV, e
# a DiaryOverlay resolve com tr() só na hora de desenhar.
#
# NÃO CONFUNDIR COM O InsightJournal: aquele autoload é apelidado de "diário" só nos comentários
# internos dele (scripts/singletons/InsightJournal.gd) e cuida de outra coisa — quais insights o
# jogador já leu, sem UI própria. Este Diary é a peça de UI navegável (livro com páginas) pedida na
# issue #30.
#
# O guia completo está em docs/diary.md.
extends Node

# Emitido quando uma página é adicionada, removida, ou o diário é limpo — qualquer mudança na lista
# de páginas. Só a DiaryOverlay escuta (relação direta e permanente entre um dono de estado e a
# tela que o mostra), por isso não é evento de bus — mesma decisão do journal_changed do
# InsightJournal (ver docs/event_bus.md, "Quando evitar").
signal pages_changed

# Emitidos quando o diário abre ou fecha. Separados de pages_changed porque quem cuida do cursor do
# mouse, de SFX de UI ou de um tutorial se importa com abrir/fechar, não com o conteúdo das páginas.
signal diary_opened
signal diary_closed

# Emitido quando a página atual muda (navegação). A DiaryOverlay usa isto pra redesenhar sem
# precisar reagir a pages_changed inteiro toda vez que o jogador aperta "próxima".
signal current_page_changed(index: int)

# Um item do diário: só dados, sem lógica. text_key/title_key são chaves de tradução (nunca texto
# pronto — ver cabeçalho do arquivo). format_args é opcional e aplicado com "%" na hora de desenhar,
# pro mesmo padrão do DYNAMIC_EXAMPLE do CSV funcionar numa página de diário (ex: nome de NPC,
# número de um item). Sem tipo definido em format_args de propósito: é o "%" do GDScript que decide
# o tipo esperado por página, e forçar um tipo único aqui quebraria a formatação mista.
class DiaryPage:
	extends RefCounted

	var title_key: StringName
	var text_key: StringName
	var format_args: Array


	func _init(p_title_key: StringName, p_text_key: StringName, p_format_args: Array = []) -> void:
		title_key = p_title_key
		text_key = p_text_key
		format_args = p_format_args


# Caminho da cena da UI, carregada sob demanda na primeira vez que o diário abre.
const OVERLAY_SCENE_PATH: String = "res://scenes/ui/DiaryOverlay.tscn"

const DEBUG_SECTION: StringName = &"Diário"

# Se abrir o diário também pausa a árvore (get_tree().paused). Ligado por padrão: ler o diário
# enquanto o mundo continua se movendo atrás normalmente não é o efeito desejado. É @export (e não
# uma const) porque é uma decisão de design que faz sentido revisitar por build/protótipo — ver
# docs/diary.md, "Como escalar".
@export var pause_game_on_open: bool = true

var _pages: Array[DiaryPage] = []
var _current_page: int = 0
var _is_open: bool = false
# Só true quando foi o PRÓPRIO Diary quem pausou a árvore. Evita que close_diary() despause o jogo
# se o menu de pausa (ou outra tela) também estiver empilhado por cima.
var _paused_by_diary: bool = false

var _overlay: DiaryOverlay = null


func _ready() -> void:
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Seção "Diário": ver docs/diary.md.
		DebugMenu.register_action(DEBUG_SECTION, "Abrir/fechar diário", toggle_diary)
		DebugMenu.register_action(DEBUG_SECTION, "Página seguinte", next_page)
		DebugMenu.register_action(DEBUG_SECTION, "Página anterior", previous_page)
		DebugMenu.register_action(DEBUG_SECTION, "Adicionar página de teste", _debug_add_test_page)
		DebugMenu.register_action(DEBUG_SECTION, "Limpar diário", clear, true)
		DebugMenu.register_action(DEBUG_SECTION, "Listar estado do diário", _print_diary)
		# [DEBUG] Duas páginas de exemplo pra ter algo pra folhear testando o protótipo, sem
		# depender de outro sistema chamar add_page() primeiro. Nunca aparece numa build de release
		# de verdade (is_debug_build() cobre isso), e o texto já nasce identificado como placeholder
		# — ver GUIDELINE_PROGRAMACAO.md, "Placeholders".
		add_page(&"PLACEHOLDER_DIARY_PAGE_1_TEXT", &"PLACEHOLDER_DIARY_PAGE_1_TITLE")
		add_page(&"PLACEHOLDER_DIARY_PAGE_2_TEXT", &"PLACEHOLDER_DIARY_PAGE_2_TITLE")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"diary_toggle"):
		toggle_diary()
		get_viewport().set_input_as_handled()


# --- API pública: conteúdo ---

# Adiciona uma página ao final do diário e devolve o índice dela. Não muda a página atual — quem
# está lendo não deve ser puxado pra outro lugar só porque um sistema qualquer registrou conteúdo
# novo em segundo plano.
func add_page(text_key: StringName, title_key: StringName = &"", format_args: Array = []) -> int:
	_pages.append(DiaryPage.new(title_key, text_key, format_args))
	var index: int = _pages.size() - 1
	print("[Diary] - Página \"%s\" adicionada (índice %d)" % [text_key, index])
	pages_changed.emit()
	return index


# Insere uma página numa posição específica, empurrando as seguintes. Existe pro dia em que o
# diário precisar de páginas fixas (ex: um índice/capa) com conteúdo dinâmico entrando depois.
func insert_page(index: int, text_key: StringName, title_key: StringName = &"", format_args: Array = []) -> void:
	index = clampi(index, 0, _pages.size())
	_pages.insert(index, DiaryPage.new(title_key, text_key, format_args))
	print("[Diary] - Página \"%s\" inserida no índice %d" % [text_key, index])
	pages_changed.emit()


# Remove a página do índice informado. Silencioso em índice inválido: o chamador não precisa validar
# antes, e um índice fora da faixa nunca é motivo pra travar o jogo.
func remove_page(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	_pages.remove_at(index)
	print("[Diary] - Página removida (índice %d)" % index)
	if _current_page >= _pages.size():
		_current_page = maxi(_pages.size() - 1, 0)
	pages_changed.emit()


# Esvazia o diário inteiro. Existe pro debug e pro dia em que "novo jogo" precisar zerar o diário
# sem reiniciar o autoload inteiro.
func clear() -> void:
	_pages.clear()
	_current_page = 0
	print("[Diary] - Diário zerado")
	pages_changed.emit()


func get_page_count() -> int:
	return _pages.size()


# Devolve a página no índice pedido, ou null se o diário estiver vazio / índice inválido. A
# DiaryOverlay decide o que fazer com null (mostra o estado "sem páginas").
func get_page(index: int) -> DiaryPage:
	if index < 0 or index >= _pages.size():
		return null
	return _pages[index]


func get_current_page_index() -> int:
	return _current_page


# --- API pública: navegação ---

func next_page() -> void:
	go_to_page(_current_page + 1)


func previous_page() -> void:
	go_to_page(_current_page - 1)


# Vai para a página pelo índice, sem dar a volta (a última página não avança pra primeira, nem a
# primeira volta pra última). Índice fora da faixa é ignorado: navegar demais não deve travar nem
# dar erro, só não faz nada — é o mesmo motivo de remove_page() não validar antes.
func go_to_page(index: int) -> void:
	if _pages.is_empty():
		return
	index = clampi(index, 0, _pages.size() - 1)
	if index == _current_page:
		return
	_current_page = index
	current_page_changed.emit(_current_page)


# --- API pública: abrir/fechar ---

func is_open() -> bool:
	return _is_open


func toggle_diary() -> void:
	if _is_open:
		close_diary()
	else:
		open_diary()


# Abre o diário, instanciando a DiaryOverlay na primeira vez (mesmo truque do DebugMenu: enquanto
# ninguém aperta a tecla, a UI não existe e não custa nada). Ignorado durante troca de cena, pelo
# mesmo motivo do PauseMenu.pause(): pausar no meio do fade trava a transição pela metade.
func open_diary() -> void:
	if _is_open or GameManager.in_transition:
		return

	if _overlay == null:
		var scene: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
		if scene == null:
			push_error("[Diary] - ERRO: cena da UI do diário não encontrada em %s" % OVERLAY_SCENE_PATH)
			return
		_overlay = scene.instantiate() as DiaryOverlay
		add_child(_overlay)

	_overlay.visible = true
	_overlay.refresh()

	if pause_game_on_open and not get_tree().paused:
		get_tree().paused = true
		_paused_by_diary = true

	_is_open = true
	diary_opened.emit()
	print("[Diary] - Diário aberto (%d página(s))" % _pages.size())


# Fecha o diário. Só despausa a árvore se foi o próprio diário quem pausou — não mexe no estado de
# pausa se o PauseMenu (ou outra tela) também estiver empilhado por cima.
func close_diary() -> void:
	if not _is_open:
		return

	_overlay.visible = false

	if _paused_by_diary:
		get_tree().paused = false
		_paused_by_diary = false

	_is_open = false
	diary_closed.emit()
	print("[Diary] - Diário fechado")


# --- Debug ---

# [DEBUG] Adiciona uma página numerada e pula pra ela, pra testar navegação/adição em runtime pelo
# menu ou console de debug sem precisar mexer em código.
func _debug_add_test_page() -> void:
	var index: int = add_page(&"DIARY_DEBUG_TEST_PAGE_TEXT", &"", [str(_pages.size() + 1)])
	go_to_page(index)


# [DEBUG] Imprime o estado do diário no log (visível no visualizador de log, F5).
func _print_diary() -> void:
	print("[Diary] - %d página(s), aberto: %s, página atual: %d" % [_pages.size(), _is_open, _current_page])
