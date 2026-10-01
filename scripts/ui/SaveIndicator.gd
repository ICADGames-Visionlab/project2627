# SaveIndicator.gd — O aviso discreto de "jogo salvo" ou "falha ao salvar" no canto inferior direito.
#
# É filho do SaveManager (instanciado no _ready() dele), e não de uma cena de jogo: o save grava na
# troca de cena, ao sair para o menu e ao fechar a janela, e o aviso precisa sobreviver a tudo isso.
# Por ser filho, o SaveManager chama show_saved()/show_failed() direto — relação fixa entre dois nós,
# sem evento no EventBus.
#
# A gravação é síncrona (começa e termina no mesmo frame), então não existe um "gravando..." que dê
# para ver: o aviso só aparece depois, já com o resultado. É o aviso de gravado e de falha na forma mais simples.
#
# PROVISÓRIO: Label sem arte, o mesmo caso do ClockHud e do ActionPrompt. Quando o HUD de verdade
# existir, o que importa manter é a porta de entrada (show_saved/show_failed), não o visual.
class_name SaveIndicator
extends CanvasLayer

## Espaço para variáveis exportadas

## Por quanto tempo (em segundos) "Jogo salvo" fica na tela.
@export var saved_seconds: float = 1.5

## Por quanto tempo (em segundos) o aviso de falha fica na tela. Bem mais longo que o de sucesso de
## propósito: é o único aviso que pede atenção do jogador (o save anterior ficou, o progresso recente
## ainda não).
@export var failed_seconds: float = 6.0

## Espaço para variáveis onready

@onready var _label: Label = $Label
@onready var _hide_timer: Timer = $HideTimer

## Espaço para funções nativas

func _ready() -> void:
	# ALWAYS: "Salvar e sair para o menu" grava com o jogo pausado (o menu de pausa está aberto), e um
	# indicador pausável ficaria congelado na tela, com o timer parado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_timer.timeout.connect(_label.hide)
	_label.hide()

## Espaço para funções personalizadas

# Mostra "Jogo salvo" por saved_seconds. Chamado pelo SaveManager a cada gravação bem-sucedida.
func show_saved() -> void:
	_show_message("SAVE_INDICATOR_SAVED", saved_seconds)


# Mostra o aviso de falha por failed_seconds. Chamado pelo SaveManager quando a gravação falha (disco
# cheio, sem permissão): o save anterior ficou intacto e a próxima gravação tenta de novo.
func show_failed() -> void:
	_show_message("SAVE_INDICATOR_FAILED", failed_seconds)


# Troca o texto e reinicia a contagem para esconder. Um aviso novo substitui o anterior na hora: o
# resultado que vale é o da última gravação, então uma falha seguida de um sucesso some com a falha.
func _show_message(text_key: String, seconds: float) -> void:
	_label.text = tr(text_key)
	_label.show()
	_hide_timer.start(seconds)
