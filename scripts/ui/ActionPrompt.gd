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
## PROVISÓRIO: Label dentro de um Panel, sem arte — o mesmo caso do ClockHud. Quando o HUD de
## verdade existir, o que importa é manter a porta de entrada (o sinal do EventBus), não o visual.
extends CanvasLayer

## Espaço para variáveis onready

@onready var _label: Label = $Label

## Espaço para funções nativas

func _ready() -> void:
	EventBus.action_prompt_changed.connect(_on_action_prompt_changed)
	_label.hide()

## Espaço para funções personalizadas

# Mostra ou esconde o aviso. A tradução acontece aqui, e não em quem pede: o emissor manda a
# chave, e o idioma é problema da tela.
func _on_action_prompt_changed(text_key: String) -> void:
	if text_key.is_empty():
		_label.hide()
		return

	_label.text = tr(text_key)
	_label.show()
