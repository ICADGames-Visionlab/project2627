# DialogueContrast.gd — Contraste WCAG no pior caso (fundo branco -> degradê -> painel na
# opacidade mínima). Usado pelo resumo do DialogueSpeaker, pelo aviso do NPCDefinition e pela
# validação de estilo (§9.7, §15.3).
class_name DialogueContrast
extends RefCounted


static func relative_luminance(color: Color) -> float:
	var r: float = _linearize(color.r)
	var g: float = _linearize(color.g)
	var b: float = _linearize(color.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


static func _linearize(channel: float) -> float:
	if channel <= 0.03928:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


static func ratio(a: Color, b: Color) -> float:
	var la: float = relative_luminance(a) + 0.05
	var lb: float = relative_luminance(b) + 0.05
	return maxf(la, lb) / minf(la, lb)


# Composição "over" em espaço sRGB, como o 2D do Compatibility renderiza.
static func blend(top: Color, bottom: Color) -> Color:
	var out_alpha: float = top.a + bottom.a * (1.0 - top.a)
	if out_alpha <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var r: float = (top.r * top.a + bottom.r * bottom.a * (1.0 - top.a)) / out_alpha
	var g: float = (top.g * top.a + bottom.g * bottom.a * (1.0 - top.a)) / out_alpha
	var b: float = (top.b * top.a + bottom.b * bottom.a * (1.0 - top.a)) / out_alpha
	return Color(r, g, b, out_alpha)


static func worst_case_background(style: DialogueStyle, min_panel_alpha: float) -> Color:
	var dimmed_white: Color = blend(Color(0.0, 0.0, 0.0, style.backdrop_dim_alpha), Color.WHITE)
	var panel: Color = Color(style.panel_color.r, style.panel_color.g, style.panel_color.b, min_panel_alpha)
	return blend(panel, dimmed_white)


static func worst_case_ratio(text: Color, text_alpha: float, style: DialogueStyle,
		min_panel_alpha: float) -> float:
	var background: Color = worst_case_background(style, min_panel_alpha)
	var foreground: Color = blend(Color(text.r, text.g, text.b, text_alpha), background)
	return ratio(foreground, background)
