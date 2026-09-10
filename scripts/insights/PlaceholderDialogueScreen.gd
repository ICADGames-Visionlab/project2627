# PlaceholderDialogueScreen.gd — Substituto da tela de diálogo enquanto ela não existe.
#
# PLACEHOLDER: painel de tela cheia com o nome da cabeça, o texto e um botão de fechar, identificado
# como placeholder na própria tela. Ele atende dialogue_requested; no dia em que a tela real existir,
# ela passa a atender o mesmo pedido e esta cena sai da main.tscn — nenhum arquivo de
# scripts/insights/ precisa ser editado.
#
# O EventBusLogger acusa no console quando um pedido _requested tem zero ou dois ouvintes, então
# esquecer de tirar este placeholder no dia da troca vira erro visível, e não duas telas abrindo
# juntas.
#
# O guia completo está em docs/insights.md.
class_name PlaceholderDialogueScreen
extends CanvasLayer

@onready var _root: Control = $Root
@onready var _head_name_label: Label = $Root/Panel/Margin/Content/HeadName
@onready var _text_label: Label = $Root/Panel/Margin/Content/Text
@onready var _close_button: Button = $Root/Panel/Margin/Content/CloseButton


func _ready() -> void:
	# A tela de diálogo para o jogo, então ela precisa continuar processando enquanto ele está
	# pausado — senão o botão de fechar não responde e o jogador fica preso.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	_close_button.pressed.connect(close)
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Abre a tela com a fala pedida. Recebe chaves, nunca texto: tr() é chamado aqui, na exibição.
func _on_dialogue_requested(head_id: StringName, text_key: String) -> void:
	_head_name_label.text = tr(HeadRegistry.get_display_name_key(head_id))
	_text_label.text = tr(text_key)
	_root.show()
	get_tree().paused = true
	print("[Insights] - Tela de diálogo (placeholder) aberta para a cabeça \"%s\"" % head_id)


# Fecha a tela e devolve o jogo ao movimento.
func close() -> void:
	if not _root.visible:
		return
	_root.hide()
	get_tree().paused = false
	print("[Insights] - Tela de diálogo (placeholder) fechada")
