// backdrop_blur.gdshader — Desfoque opcional atrás do painel de diálogo (SPEC §7.2, §16 Fase 5).
// Precisa de um BackBufferCopy antes dele na árvore (copia o que já foi desenhado; sem ele o
// screen_texture fica vazio). Caixa de 3x3, um passe só: mais barato que Gaussian de dois passes,
// à custa de um desfoque menos suave — suficiente para o painel translúcido por cima. Desligado por
// padrão (DialogueStyle.backdrop_blur_enabled = false); medir no Compatibility antes de ligar.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_radius : hint_range(0.0, 8.0) = 3.0;

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE * blur_radius;
	vec4 sum = vec4(0.0);
	sum += texture(screen_texture, SCREEN_UV + vec2(-texel.x, -texel.y));
	sum += texture(screen_texture, SCREEN_UV + vec2(0.0, -texel.y));
	sum += texture(screen_texture, SCREEN_UV + vec2(texel.x, -texel.y));
	sum += texture(screen_texture, SCREEN_UV + vec2(-texel.x, 0.0));
	sum += texture(screen_texture, SCREEN_UV);
	sum += texture(screen_texture, SCREEN_UV + vec2(texel.x, 0.0));
	sum += texture(screen_texture, SCREEN_UV + vec2(-texel.x, texel.y));
	sum += texture(screen_texture, SCREEN_UV + vec2(0.0, texel.y));
	sum += texture(screen_texture, SCREEN_UV + vec2(texel.x, texel.y));
	COLOR = sum / 9.0;
}
