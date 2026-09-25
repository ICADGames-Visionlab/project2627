# DialoguePortraitLayout.gd — Onde ficam os retratos dos NPCs: numa coluna à esquerda da coluna de
# diálogo, empilhados de cima pra baixo e alinhados ao topo dela. Puro (só números), para o
# autoteste cobrir sem abrir cena.
class_name DialoguePortraitLayout
extends RefCounted


# Um Rect2 por retrato, em coordenadas da tela, ou uma lista vazia quando não sobra espaço. Em tela
# estreita ou baixa os retratos encolhem JUNTOS, mantendo a proporção do slot, até
# portrait_min_scale do tamanho cheio; abaixo disso é melhor não mostrar do que mostrar um selo.
# Com dois retratos, a altura disponível é dividida entre os dois mais o portrait_stack_gap — é por
# isso que a conta é feita sobre a pilha inteira, e não retrato por retrato.
static func compute_rects(count: int, panel_left: float, panel_top: float, viewport_size: Vector2,
		style: DialogueStyle) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var slot: Vector2 = style.portrait_slot_size
	if count <= 0 or slot.x <= 0.0 or slot.y <= 0.0:
		return rects

	var top: float = panel_top + style.portrait_offset_top
	var gaps: float = style.portrait_stack_gap * float(count - 1)
	var stack_height: float = slot.y * float(count) + gaps
	var available_width: float = panel_left - style.portrait_gap - style.portrait_margin_left
	var available_height: float = viewport_size.y - style.panel_margin_bottom - top
	var fit: float = minf(1.0, minf(available_width / slot.x, available_height / stack_height))
	if fit < style.portrait_min_scale:
		return rects

	var size: Vector2 = slot * fit
	var left: float = panel_left - style.portrait_gap - size.x
	for i: int in count:
		rects.append(Rect2(Vector2(left, top + float(i) * (size.y + style.portrait_stack_gap * fit)), size))
	return rects
