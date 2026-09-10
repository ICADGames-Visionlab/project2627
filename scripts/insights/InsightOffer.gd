# InsightOffer.gd — Um insight de cabeça disponível agora, junto do que o orbe precisa saber para
# se desenhar: de quem é a cabeça, se ainda é novidade e de que fonte ele veio.
#
# Existe porque a órbita do jogador mostra no máximo um orbe por cabeça, e não um por insight: o
# InsightDirector reduz tudo que está ao alcance a uma oferta por cabeça, e o HeadOrbitLayer só
# arruma o que recebeu.
class_name InsightOffer
extends RefCounted

var head_id: StringName
var insight: InsightData
# A fonte que ofereceu este insight. É o único campo que guarda um nó: a oferta vive um frame (o
# Director a remonta a cada reavaliação), e é ela que diz para onde o clique volta.
var source: Node
var is_new: bool


func _init(p_head_id: StringName, p_insight: InsightData, p_source: Node, p_is_new: bool) -> void:
	head_id = p_head_id
	insight = p_insight
	source = p_source
	is_new = p_is_new


# Descrição curta para os relatórios do menu de debug.
func _to_string() -> String:
	return "InsightOffer(cabeça=%s, insight=%s, novo=%s)" % [head_id, insight.id, is_new]
