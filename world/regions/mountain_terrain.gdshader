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
	vec3 ground = mix(earth_dark, grass, smoothstep(0.45, 0.55, mid));
	ground = mix(ground, base, 0.25);
	ground *= 0.85 + macro * 0.3;
	// Neve do inverno cobre o chão baixo em manchas; o alto fica todo branco.
	// Borda de neve nítida: com transição larga as manchas pareciam nuvem borrada
	// (relato do jogador em 2026-09-24). O grão entra na borda para ela não ser lisa.
	float drift = smoothstep(0.50, 0.53, macro * 0.6 + mid * 0.4 + (fine - 0.5) * 0.05);
	float cover = clamp(max(snow_amount, drift * 0.85), 0.0, 1.0);
	// Terra aparecendo pela neve em pontos (pegadas, pedras, tufos).
	cover *= 1.0 - smoothstep(0.70, 0.73, mid + (fine - 0.5) * 0.06) * 0.8;
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
	// Encosta da bacia dos lagos (terreno abaixo de 0): lama molhada na beira da
	// água, sem neve, para a margem não ser uma linha seca cortando o capim.
	// smoothstep com limites em ordem crescente: invertidos, o GLSL não define o
	// resultado e a lama não aparecia sob a água rasa.
	// Margem úmida começa acima da linha d'água (-0,2) e vira lama plena logo abaixo.
	float wet = 1.0 - smoothstep(-0.3, 0.02, height + (fine - 0.5) * 0.06);
	// Bem mais escura que o capim: a luz de inverno clareia ~2,5x e lama clara lia
	// como capim sob a água.
	vec3 mud = mix(vec3(0.085, 0.066, 0.045), vec3(0.05, 0.045, 0.035), smoothstep(0.1, 0.4, -height));
	color = mix(color, mud * (0.9 + fine * 0.2), wet * 0.92);
	ALBEDO = color;
	// Relevo fino na iluminação: sem ele o chão é um plano liso e sem textura.
	float e = 0.15;
	float h0 = noise(local_xz * 1.5, 96.0) + noise(local_xz * 4.0, 256.0) * 0.5;
	float hx = noise((local_xz + vec2(e, 0.0)) * 1.5, 96.0) + noise((local_xz + vec2(e, 0.0)) * 4.0, 256.0) * 0.5;
	float hz = noise((local_xz + vec2(0.0, e)) * 1.5, 96.0) + noise((local_xz + vec2(0.0, e)) * 4.0, 256.0) * 0.5;
	vec2 bump = vec2(hx - h0, hz - h0) / e * 0.08;
	NORMAL_MAP = vec3(0.5 - bump.x, 0.5 - bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	float snowy = cover * (1.0 - cliff);
	ROUGHNESS = mix(mix(0.95, 0.6, snowy), 0.35, wet);
	SPECULAR = mix(0.2, 0.4, snowy);
	// Cintilado de cristal de gelo: pontos minúsculos, só na neve.
	float glitter = step(0.985, hash(floor(local_xz * 9.0))) * snowy;
	EMISSION = vec3(glitter * 0.12);
}
