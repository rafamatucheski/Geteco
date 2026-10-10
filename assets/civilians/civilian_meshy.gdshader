shader_type spatial;
render_mode cull_back;
// Corpo de pedestre importado do Meshy: cor base em textura única, sem mapas PBR.
// Variedade barata por instância: gira o matiz só das peças saturadas e fora da faixa de pele
// (roupas coloridas), preservando pele, cabelo, sapatos e tecidos neutros.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
instance uniform float hue_shift : hint_range(-0.5, 0.5) = 0.0;
instance uniform float brightness : hint_range(0.5, 1.5) = 1.0;
// `BurningActor.char_body` escreve fuligem aqui (alfa 1) em todos os corpos civis.
instance uniform vec4 skin_color : source_color = vec4(0.0);

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	vec3 hsv = rgb2hsv(base);
	// Pele ocupa o laranja/rosado de saturação média; abaixo disso é neutro (cabelo, sapato, jeans claro).
	float skin = smoothstep(0.0, 0.015, hsv.x + 0.03) * (1.0 - smoothstep(0.10, 0.14, hsv.x)) * smoothstep(0.12, 0.2, hsv.y) * (1.0 - smoothstep(0.65, 0.8, hsv.y));
	float cloth = smoothstep(0.16, 0.30, hsv.y) * (1.0 - skin);
	hsv.x = fract(hsv.x + hue_shift * cloth);
	vec3 color = hsv2rgb(hsv) * mix(1.0, brightness, cloth);
	color = mix(color, skin_color.rgb, step(0.5, skin_color.a));
	ALBEDO = color;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
