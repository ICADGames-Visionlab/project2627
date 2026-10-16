// Transição para o mundo dos sonhos: a tela ondula, perde a cor, puxa para um vermelho de sangue
// velho e é engolida por uma vinheta que pulsa como um coração até fechar no preto.
//
// Tudo é guiado por "progress" (0 = tela normal, 1 = preto total), que o DreamTransition.gd anima.
// Os outros uniforms são o que o design ajusta no Inspector do material.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// 0 = efeito desligado, 1 = tela toda preta.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Cor para onde a imagem é puxada enquanto some.
uniform vec4 tint : source_color = vec4(0.45, 0.02, 0.06, 1.0);

// Quanto a imagem ondula no auge do efeito, em fração da tela.
uniform float wobble_strength : hint_range(0.0, 0.1) = 0.025;

// Batidas por segundo do pulso da vinheta, e quanto ela pulsa.
uniform float heartbeat_speed = 7.0;
uniform float heartbeat_strength : hint_range(0.0, 0.2) = 0.05;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Ondulação que só existe durante a transição: cresce com o progresso.
	float t = TIME * 3.0;
	uv.x += sin(uv.y * 25.0 + t) * wobble_strength * progress;
	uv.y += cos(uv.x * 18.0 + t * 1.3) * wobble_strength * progress;

	vec3 color = texture(screen_texture, uv).rgb;

	// Tira a cor e tinge: a cidade vira uma lembrança manchada antes de sumir.
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, luminance * tint.rgb * 2.5, progress);

	// Vinheta que fecha do canto para o centro e pulsa. Em progress = 1 o raio é negativo e a tela
	// inteira fica preta, que é o instante em que o mundo troca por trás.
	float heartbeat = sin(TIME * heartbeat_speed) * heartbeat_strength * progress;
	float radius = mix(1.2, -0.4, progress) + heartbeat;
	float dist = distance(SCREEN_UV, vec2(0.5));
	color *= 1.0 - smoothstep(radius - 0.35, radius, dist);

	COLOR = vec4(color, 1.0);
}
