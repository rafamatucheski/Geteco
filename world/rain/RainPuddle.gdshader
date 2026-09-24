shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// Poça de chuva: uma única malha/material compartilhado por todas as poças.
// `fill` (0..1) é a umidade da cidade; cada poça cresce e seca pela borda,
// com contorno irregular vindo do `seed` por instância.
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float rain : hint_range(0.0, 1.0) = 1.0;
// Câmera quase vertical não pega reflexo de céu de verdade: como na V1, a água é
// pintada no tom do céu (0.16, 0.22, 0.30) com um brilho quebrado por cima.
uniform vec3 tint : source_color = vec3(0.30, 0.38, 0.46);
uniform vec3 sheen : source_color = vec3(0.70, 0.82, 0.92);
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Anéis de gota: uma gota por célula, em fase própria. Devolve a inclinação radial.
vec2 ripples(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	vec2 cell = floor(p);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = hash(c + seed * 7.13);
			vec2 center = c + vec2(hash(c + 3.1), hash(c + 5.7));
			float phase = fract(t * (0.9 + h * 0.6) + h);
			vec2 d = p - center;
			float r = length(d);
			float ring = phase * 0.85;
			float band = exp(-pow((r - ring) * 18.0, 2.0)) * (1.0 - phase);
			slope += normalize(d + 1e-4) * band * sin((r - ring) * 40.0);
		}
	}
	return slope;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float wobble = noise(p * 2.2 + seed * 13.0) - 0.5;
	wobble += (noise(p * 5.1 - seed * 3.0) - 0.5) * 0.45;
	float d = length(p) + wobble * 0.42;
	// Cada poça tem seu próprio atraso: as rasas somem primeiro ao secar.
	float local_fill = clamp(fill * 1.2 - fract(seed * 3.7) * 0.2, 0.0, 1.0);
	float edge = mix(0.0, 0.9, local_fill);
	float body = 1.0 - smoothstep(edge - 0.1, edge, d);
	// Faixa de asfalto encharcado em volta da água: mais escura, menos lisa.
	float damp = (1.0 - smoothstep(edge, edge + 0.22, d)) * local_fill;
	float alpha = max(body * 0.8, damp * 0.3);
	if (alpha < 0.01) discard;

	vec2 slope = ripples(UV * vec2(9.0, 5.0), TIME) * rain * body;
	float ring_light = clamp(length(slope) * 1.6, 0.0, 1.0);
	// Reflexo quebrado em arco, como os draw_arc de Puddle.gd.
	float arc = exp(-pow((length(p - vec2(-0.25, -0.1)) - 0.45) * 9.0, 2.0)) * step(p.y, 0.05);
	arc *= 0.5 + 0.5 * noise(p * 6.0 + seed * 5.0);
	NORMAL_MAP = vec3(0.5 + slope.x * 0.18, 0.5 + slope.y * 0.18, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	vec3 water = mix(tint, sheen, clamp(arc * 0.55 + ring_light * 0.5, 0.0, 1.0));
	ALBEDO = mix(tint * 0.45, water, body);
	ROUGHNESS = mix(0.45, 0.02, body);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 1.0, body);
	ALPHA = alpha;
}
