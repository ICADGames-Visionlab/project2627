## ActionPrompt - O aviso de ação no rodapé da tela ("Aperte ESPAÇO para dormir").
##
## COMO USAR: instancie ActionPrompt.tscn uma vez na cena de jogo. Objetos interativos não
## conhecem esta cena — eles pedem o aviso pelo EventBus:
##
##     EventBus.action_prompt_changed.emit("PROMPT_SLEEP")   # mostrar
##     EventBus.action_prompt_changed.emit("")               # esconder
##
## É um aviso só, compartilhado: o último pedido vence. Quem mostra é responsável por esconder.
##
## A TECLA NÃO ESTÁ NO TEXTO: o CSV cita a ação ("Aperte {sleep} para dormir") e o InputGlyphs troca
## pela tecla ou pelo botão do controle, conforme o que o jogador está usando. Quando ele troca de
## dispositivo com o aviso na tela, o aviso é reescrito na hora (ver docs/suporte_a_controle.md).
##
## PROVISÓRIO: Label dentro de um Panel, sem arte — o mesmo caso do ClockHud. Quando o HUD de
## verdade existir, o que importa é manter a porta de entrada (o sinal do EventBus), não o visual.
extends CanvasLayer

## Espaço para variáveis

# Chave do aviso na tela agora, ou vazio. Guardada para reescrever o aviso quando o dispositivo muda.
var _text_key: String = ""

## Espaço para variáveis onready

@onready var _label: Label = $Label

## Espaço para funções nativas

func _ready() -> void:
	EventBus.action_prompt_changed.connect(_on_action_prompt_changed)
	EventBus.input_device_changed.connect(_on_input_device_changed)
	# O texto já chega pronto (traduzido e com a tecla no lugar): a tradução automática procuraria a
	# frase inteira como chave do CSV.
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.hide()


# O aviso é montado em código, então não se retraduz sozinho quando o idioma muda.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _text_key.is_empty():
		_label.text = InputGlyphs.tr_prompt(_text_key)


## Espaço para funções personalizadas

# Mostra ou esconde o aviso. A tradução acontece aqui, e não em quem pede: o emissor manda a
# chave, e o idioma (e a tecla do dispositivo em uso) é problema da tela.
func _on_action_prompt_changed(text_key: String) -> void:
	_text_key = text_key
	if text_key.is_empty():
		_label.hide()
		return

	_label.text = InputGlyphs.tr_prompt(text_key)
	_label.show()


# O jogador pegou o controle (ou largou) com o aviso na tela: a tecla escrita nele muda junto.
func _on_input_device_changed(_device: int) -> void:
	if not _text_key.is_empty():
		_label.text = InputGlyphs.tr_prompt(_text_key)
