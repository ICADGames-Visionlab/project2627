# DialoguePortraitLayout.gd — Onde fica o retrato do NPC: à esquerda da coluna de diálogo, alinhado
# ao topo dela. Puro (só números), para o autoteste cobrir sem abrir cena.
class_name DialoguePortraitLayout
extends RefCounted


# Retângulo do retrato em coordenadas da tela, ou um Rect2 vazio quando não sobra espaço. Em tela
# estreita ou baixa o retrato encolhe, mantendo a proporção do slot, até portrait_min_scale do
# tamanho cheio; abaixo disso é melhor não mostrar do que mostrar um selo.
static func compute_rect(panel_left: float, panel_top: float, viewport_size: Vector2,
		style: DialogueStyle) -> Rect2:
	var slot: Vector2 = style.portrait_slot_size
	if slot.x <= 0.0 or slot.y <= 0.0:
		return Rect2()
	var top: float = panel_top + style.portrait_offset_top
	var available_width: float = panel_left - style.portrait_gap - style.portrait_margin_left
	var available_height: float = viewport_size.y - style.panel_margin_bottom - top
	var fit: float = minf(1.0, minf(available_width / slot.x, available_height / slot.y))
	if fit < style.portrait_min_scale:
		return Rect2()
	var size: Vector2 = slot * fit
	return Rect2(Vector2(panel_left - style.portrait_gap - size.x, top), size)
