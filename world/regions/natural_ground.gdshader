shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Chão pintado à mão no editor (terra, cascalho, grama, areia) e estradas de
// terra. Antes era cor lisa ou uma textura 64×64 de ruído fraco: vista de cima,
// no editor ou no jogo, lia como papel recortado sobre o terreno (relato de
// 2026-09-26). Aqui o detalhe vem em escalas de 6 m, 1,5 m e 0,3 m, com
// pedrinhas, sulcos de pisada, manchas úmidas e neve assentada nas bordas.
//
// `uv_origin` é subtraído no vértice: UV em metros de mundo passa de 600 e, no
// renderizador Mobile, o ruído vira blocos (mesmo problema do mar e do terreno).
#include "res://world/regions/mountain_ground.gdshaderinc"

// 0 terra, 1 cascalho, 2 grama, 3 areia.
uniform int kind = 0;
uniform vec3 base_color : source_color = vec3(0.54, 0.44, 0.33);
// Metros por unidade de UV da malha.
uniform float uv_meters = 2.0;
uniform bool edge_alpha = false;
instance uniform vec2 uv_origin = vec2(0.0);

varying vec2 q;
varying float mountain;

void vertex() {
	q = (UV - uv_origin) * uv_meters;
	mountain = ground_mountain_weight((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz);
}

// Pedrinhas: células de 0,25 m, algumas com uma pedra arredondada.
float pebbles(vec2 p, float density, out float tone) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = ground_hash(mod(cell, 512.0));
	tone = ground_hash(mod(cell + 17.0, 512.0));
	vec2 jitter = vec2(ground_hash(mod(cell + 3.0, 512.0)), ground_hash(mod(cell + 9.0, 512.0))) - 0.5;
	float r = 0.18 + tone * 0.2;
	return step(1.0 - density, h) * (1.0 - smoothstep(r * 0.7, r, length(f - jitter * 0.4)));
}

void fragment() {
	float macro = ground_noise(q / 6.0, 4096.0);
	float mid = ground_noise(q / 1.5, 4096.0);
	float fine = ground_noise(q * 3.3, 4096.0);
	float grain = ground_noise(q * 11.0, 8192.0);
	vec3 color = base_color;
	float rough = 0.95;
	float bump_scale = 0.06;

	if (kind == 0 || kind == 3) {
		// Terra/areia: manchas claras secas e escuras úmidas, sulcos de pisada.
		float damp = smoothstep(0.55, 0.8, macro * 0.7 + mid * 0.3);
		float dry = smoothstep(0.55, 0.85, 1.0 - macro * 0.6 - fine * 0.4);
		color *= 0.86 + mid * 0.2 + fine * 0.08 + grain * 0.05;
		color = mix(color, color * vec3(1.18, 1.12, 1.02), dry * 0.6);
		color = mix(color, color * vec3(0.55, 0.52, 0.5), damp * (kind == 0 ? 0.7 : 0.35));
		float ruts = sin(q.x * 1.1 + macro * 5.0) * 0.5 + 0.5;
		color *= 1.0 - smoothstep(0.85, 1.0, ruts) * 0.12 * (1.0 - float(kind == 3));
		float tone;
		float stone = pebbles(q * 3.0, kind == 0 ? 0.05 : 0.02, tone);
		color = mix(color, mix(vec3(0.36, 0.34, 0.31), vec3(0.58, 0.56, 0.52), tone), stone * 0.6);
		// Capim ralo invadindo a terra.
		float tuft = smoothstep(0.7, 0.85, ground_noise(q * 1.7 + 40.0, 4096.0)) * smoothstep(0.55, 0.8, grain);
		color = mix(color, vec3(0.22, 0.28, 0.15), tuft * (kind == 0 ? 0.7 : 0.25));
		rough = mix(0.96, 0.7, damp * 0.6);
		bump_scale = 0.08 + stone * 0.1;
	} else if (kind == 1) {
		// Cascalho: pedras de dois tamanhos sobre base escura.
		float t1;
		float t2;
		float big = pebbles(q * 3.0, 0.55, t1);
		float small = pebbles(q * 7.0 + 5.0, 0.7, t2);
		color *= 0.62 + mid * 0.2 + macro * 0.15;
		color = mix(color, base_color * (0.85 + t2 * 0.45), small * 0.8);
		color = mix(color, base_color * (0.8 + t1 * 0.5), big);
		bump_scale = 0.12 + (big + small) * 0.08;
	} else {
		// Grama: tons de capim, falhas de terra e tufos escuros.
		float dry = smoothstep(0.5, 0.8, macro);
		color = mix(color, vec3(0.52, 0.49, 0.3), dry * 0.45);
		color *= 0.7 + mid * 0.25 + fine * 0.18 + grain * 0.14;
		float bald = smoothstep(0.78, 0.9, mid * 0.6 + fine * 0.4);
		color = mix(color, vec3(0.36, 0.29, 0.21), bald * 0.7);
		float blade = smoothstep(0.6, 0.95, ground_noise(q * vec2(24.0, 6.0), 8192.0));
		color = mix(color, color * 1.3, blade * 0.35);
		bump_scale = 0.07;
	}

	// Neve assentada nas manchas altas, só em Mountain (mesma cobertura do terreno).
	float snow = smoothstep(0.62, 0.72, macro * 0.55 + mid * 0.3 + fine * 0.15) * mountain * (kind == 1 ? 0.55 : 0.8);
	color = mix(color, vec3(0.86, 0.89, 0.93) * (0.92 + grain * 0.08), snow);
	ALBEDO = color;
	if (edge_alpha) ALPHA = COLOR.a;
	ROUGHNESS = mix(rough, 0.6, snow);
	SPECULAR = 0.25;

	float e = 0.05;
	float h0 = ground_noise(q * 3.3, 4096.0) + ground_noise(q * 11.0, 8192.0) * 0.5;
	float hx = ground_noise((q + vec2(e, 0.0)) * 3.3, 4096.0) + ground_noise((q + vec2(e, 0.0)) * 11.0, 8192.0) * 0.5;
	float hz = ground_noise((q + vec2(0.0, e)) * 3.3, 4096.0) + ground_noise((q + vec2(0.0, e)) * 11.0, 8192.0) * 0.5;
	vec2 bump = vec2(hx - h0, hz - h0) / e * bump_scale;
	NORMAL_MAP = vec3(0.5 - bump.x, 0.5 - bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
