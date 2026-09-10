# InsightRevealedEvent.gd — Fotografia de uma leitura de insight.
#
# Classe de payload porque o fato tem seis campos, e docs/event_bus.md manda parar de empilhar
# parâmetros a partir do quarto: assim acrescentar um campo novo não quebra a assinatura de todos
# os ouvintes.
#
# Guarda ids, nunca nós: source_id é o instance id da fonte, e quem quiser o nó de volta usa
# instance_from_id() aceitando que ele pode não existir mais quando o payload for lido.
class_name InsightRevealedEvent
extends RefCounted

var insight_id: StringName
var channel: InsightData.Channel
var head_id: StringName
var text_key: String
var source_id: int
# Falso quando o jogador está relendo algo que já leu. É o que separa "descobriu" de "voltou a
# olhar" para quem for contabilizar progresso, tocar som ou registrar conquista.
var first_time: bool


func _init(p_insight_id: StringName, p_channel: InsightData.Channel, p_head_id: StringName,
		p_text_key: String, p_source_id: int, p_first_time: bool) -> void:
	insight_id = p_insight_id
	channel = p_channel
	head_id = p_head_id
	text_key = p_text_key
	source_id = p_source_id
	first_time = p_first_time


# Sem isso o log de eventos imprime "<RefCounted#...>" e não ajuda em nada.
func _to_string() -> String:
	return "InsightRevealedEvent(id=%s, canal=%s, cabeça=%s, primeira_vez=%s)" % [
		insight_id, "personagem" if channel == InsightData.Channel.CHARACTER else "ambiente",
		head_id if head_id != &"" else "-", first_time
	]
