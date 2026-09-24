shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Chama procedural para partículas (CPUParticles3D/GPUParticles3D): lança-chamas,
// bola de fogo das explosões e incêndio no chão. Antes era um disco de gradiente
// radial fixo (e, no chão, cilindros opacos): tudo lia como bolinha ou cone
// (relato do jogador em 2026-09-24). Aqui cada partícula é uma língua de fogo
// em gota, com contorno rasgado por ruído que sobe, núcleo claro e ponta
// avermelhada; a cor/transparência da partícula (COLOR) vem da rampa do emissor.
// Billboard feito no shader para respeitar a escala de cada partícula.
// Mistura com alfa, não aditiva: somada sobre concreto claro a chama sumia (a
// explosão do carro no pátio da delegacia não aparecia).

uniform float flicker_speed = 2.6;
uniform float ragged = 0.45;

varying float seed;

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

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 9.1) * 0.15;
}

void vertex() {
	seed = fract(float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 0.13);
	// Billboard com a escala da partícula preservada.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	// uv.y: -1 em cima (ponta da chama), +1 embaixo (base).
	vec2 uv = UV * 2.0 - 1.0;
	float t = TIME * flicker_speed + seed * 23.0;
	float n = fbm(vec2(uv.x * 1.8 + seed * 7.0, uv.y * 1.4 + t));
	float lick = fbm(vec2(uv.x * 3.5 - seed * 5.0, uv.y * 2.5 + t * 1.6));
	// Ondula de lado, mais na ponta.
	float x = uv.x + (n - 0.5) * ragged * (1.2 - uv.y) * 0.6;
	// Gota: larga embaixo, afina em cima.
	float width = mix(0.28, 0.85, smoothstep(-1.0, 0.55, uv.y));
	float r = length(vec2(x / width, (uv.y - 0.2) * 0.9));
	float edge = 0.62 + (lick - 0.5) * 0.55;
	float body = 1.0 - smoothstep(edge - 0.35, edge, r);
	float core = 1.0 - smoothstep(0.05, 0.55, r + (n - 0.5) * 0.35 + (0.3 - uv.y) * 0.12);
	vec3 outer = vec3(0.85, 0.16, 0.02);
	vec3 mid = vec3(1.0, 0.52, 0.08);
	vec3 hot = vec3(1.0, 0.92, 0.62);
	vec3 color = mix(outer, mid, smoothstep(0.1, 0.7, body));
	color = mix(color, hot, core);
	ALBEDO = color * COLOR.rgb;
	ALPHA = clamp(body * COLOR.a * 1.15, 0.0, 1.0);
}
