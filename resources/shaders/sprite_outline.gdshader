// sprite_outline.gdshader — Contorno sólido em volta do desenho do sprite (silhueta, não caixa),
// pela alfa dos texels vizinhos. outline_width em texels da textura de origem, não em pixels de
// tela: multiplicar pela escala do nó dá a espessura visível.
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (outline_width > 0.0 && tex_color.a <= 0.5) {
		vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;
		float neighbor_alpha = 0.0;
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(texel.x, 0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-texel.x, 0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0, texel.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0, -texel.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(texel.x, texel.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a);
		tex_color = vec4(outline_color.rgb, outline_color.a * neighbor_alpha);
	}
	COLOR = tex_color;
}
