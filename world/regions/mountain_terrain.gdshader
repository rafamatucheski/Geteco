shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Chão de Mountain. Antes era só a cor do vértice (a cada 4 m) e, com a luz de
// inverno, lia como uma placa creme lisa (captura de 2026-09-24). Aqui a cor do
// vértice vira base e ganha: variação em três escalas, terra/capim aparecendo
// pela neve, rocha nas encostas, azul frio nos baixios e cintilado na neve.
//
// `origin` é o canto do chunk de 64 m, por instância: no renderizador Mobile a
// coordenada de mundo (x > 600 m) perde precisão no fragmento e o ruído vira
// blocos, como aconteceu no mar. O ruído usa coordenada local ao chunk + origem
// reduzida a um período, sem emenda entre chunks.
instance uniform vec2 origin = vec2(0.0);
uniform vec3 earth_dark : source_color = vec3(0.17, 0.19, 0.13);
uniform vec3 grass : source_color = vec3(0.24, 0.31, 0.18);
uniform vec3 rock : source_color = vec3(0.42, 0.43, 0.43);
uniform vec3 snow_shade : source_color = vec3(0.60, 0.70, 0.84);
uniform vec3 snow_lit : source_color = vec3(0.94, 0.95, 0.96);

varying vec2 local_xz;
varying vec3 world_normal;
varying float height;

const float PERIOD = 256.0;

void vertex() {
	local_xz = VERTEX.xz - origin;
	world_normal = NORMAL;
	height = VERTEX.y;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ruído de valor periódico em `cells` células; `p` já em células.
float noise(vec2 p, float cells) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(mod(i, cells)), hash(mod(i + vec2(1.0, 0.0), cells)), u.x),
		mix(hash(mod(i + vec2(0.0, 1.0), cells)), hash(mod(i + vec2(1.0, 1.0), cells)), u.x), u.y);
}

// Soma de oitavas; `scale` em metros por célula, período de 256 m.
float fbm(vec2 p, float scale) {
	float cells = PERIOD / scale;
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += noise(p / scale, cells) * amp;
		scale *= 0.5;
		cells *= 2.0;
		amp *= 0.5;
	}
	return v / 0.875;
}

void fragment() {
	// Coordenada contínua entre chunks dentro do período (origem reduzida a 256 m).
	vec2 p = local_xz + mod(origin, PERIOD);
	vec3 base = COLOR.rgb;
	float snow_amount = smoothstep(0.55, 0.8, dot(base, vec3(0.333)));
	float macro = fbm(p, 32.0);
	float mid = fbm(p + 91.0, 8.0);
	// Grão fino só na coordenada local (0..64 m): longe da origem até p perde precisão.
	float fine = noise(local_xz * 1.5, 96.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	// Chão sem neve: terra e capim em manchas, com o tom de altura do vértice.
	vec3 ground = mix(earth_dark, grass, smoothstep(0.35, 0.7, mid));
	ground = mix(ground, base, 0.25);
	ground *= 0.85 + macro * 0.3;
	// Neve do inverno cobre o chão baixo em manchas; o alto fica todo branco.
	float drift = smoothstep(0.42, 0.62, macro * 0.6 + mid * 0.4);
	float cover = clamp(max(snow_amount, drift * 0.85), 0.0, 1.0);
	// Terra aparecendo pela neve em pontos (pegadas, pedras, tufos).
	cover *= 1.0 - smoothstep(0.66, 0.8, mid) * 0.7;
	// Luz de inverno estoura a neve para quase branco; o contraste vem de manchas de
	// sombra fria largas e de ondulações de vento (sastrugi) numa direção só.
	vec3 snow = mix(snow_shade, snow_lit, smoothstep(0.3, 0.75, macro));
	vec2 wind = vec2(0.8, 0.6);
	float ripple = sin(dot(p, wind) * 2.4 + mid * 9.0) * 0.5 + 0.5;
	ripple = smoothstep(0.55, 1.0, ripple) * smoothstep(0.35, 0.65, fbm(p + 37.0, 16.0));
	snow = mix(snow, snow_shade * 0.95, ripple * 0.45);
	// Baixios ficam em sombra fria.
	snow = mix(snow_shade * 0.92, snow, smoothstep(0.5, 4.0, height));
	snow *= 0.97 + fine * 0.05;
	vec3 color = mix(ground, snow, cover);
	// Encosta íngreme: neve não para, aparece rocha.
	float cliff = smoothstep(0.12, 0.28, slope + (mid - 0.5) * 0.12);
	color = mix(color, rock * (0.85 + fine * 0.25), cliff);
	color *= 0.94 + fine * 0.08;
	ALBEDO = color;
	float snowy = cover * (1.0 - cliff);
	ROUGHNESS = mix(0.95, 0.6, snowy);
	SPECULAR = mix(0.2, 0.4, snowy);
	// Cintilado de cristal de gelo: pontos minúsculos, só na neve.
	float glitter = step(0.985, hash(floor(local_xz * 9.0))) * snowy;
	EMISSION = vec3(glitter * 0.12);
}
