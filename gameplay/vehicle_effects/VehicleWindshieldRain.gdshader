shader_type spatial;
// Gotas no vidro do veículo conduzido. Só a malha de vidro (cópia, sem tocar nos materiais do
// modelo), animada por TIME: nenhum script por quadro. O limpador apaga as gotas por onde passa
// (mesma fase de `VehicleWiper.gdshader`) e elas voltam a se formar depois.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform float rain : hint_range(0.0, 1.0) = 0.0;
// Amplitude do varrido (0 = estacionado/desligado, 1 = varrendo).
uniform float wiper_amp : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_period = 1.6;
uniform float wiper_phase = 0.0;
uniform float falling = 0.0;
uniform float pattern_seed = 0.0;
// Pivôs (x,y no plano do para-brisa), comprimento e abertura angular do limpador.
uniform vec4 pivots = vec4(0.0);
uniform float wiper_length = 0.4;
uniform float wiper_sweep = 1.75;
uniform float wiper_park = 0.06;

varying vec3 mpos;
varying vec3 mnorm;
varying float is_front;

#include "res://gameplay/vehicle_effects/VehicleRainDrops.gdshaderinc"

void vertex() {
	mpos = VERTEX;
	mnorm = NORMAL;
	is_front = COLOR.r;
}

void fragment() {
	vec3 n = normalize(mnorm);
	vec2 p;
	vec3 ax; vec3 ay;
	if (is_front > 0.5) { p = mpos.xy; ax = vec3(1.0, 0.0, 0.0); ay = vec3(0.0, 1.0, 0.0); }
	else if (abs(n.x) > abs(n.y) && abs(n.x) > abs(n.z)) { p = mpos.zy; ax = vec3(0.0, 0.0, 1.0); ay = vec3(0.0, 1.0, 0.0); }
	else if (abs(n.y) > abs(n.z)) { p = mpos.xz; ax = vec3(1.0, 0.0, 0.0); ay = vec3(0.0, 0.0, 1.0); }
	else { p = mpos.xy; ax = vec3(1.0, 0.0, 0.0); ay = vec3(0.0, 1.0, 0.0); }
	float t = TIME;
	float density = rain * mix(0.24, 0.90, falling);
	vec3 a = rain_beads(p, 65.0, density, falling, 1.0 - abs(n.y), t, pattern_seed);
	vec3 b = rain_beads(p + vec2(0.37, 0.19), 33.0, density * smoothstep(0.25, 0.95, falling) * 0.65, falling, 1.0 - abs(n.y), t, pattern_seed + 5.0);
	float mask = max(a.x, b.x);
	vec2 grad = a.yz * a.x + b.yz * b.x;
	// Garoa deixa só as gotas miúdas; a camada grande entra com chuva forte.
	// Limpador: tempo (em fase) desde que a lâmina passou por este ponto.
	float clear = 1.0;
	if (is_front > 0.5 && wiper_amp > 0.02) {
		float ph = fract(wiper_phase);
		float best = 1.0;
		for (int i = 0; i < 2; i++) {
			vec2 pv = i == 0 ? pivots.xy : pivots.zw;
			vec2 rel = p - pv;
			float rad = length(rel);
			float ang = atan(rel.y, rel.x);
			float f = clamp((ang - wiper_park) / wiper_sweep, 0.0, 1.0);
			float inside = step(0.0, ang - wiper_park + 0.05) * step(ang - wiper_park, wiper_sweep + 0.05) * step(rad, wiper_length * 1.04);
			float d = min(fract(ph - f * 0.5), fract(ph - (1.0 - f * 0.5)));
			best = min(best, mix(1.0, smoothstep(0.0, 0.45, d), inside));
		}
		clear = mix(1.0, best, wiper_amp);
	}
	mask *= clear;
	vec3 pn = normalize(n + (ax * grad.x + ay * grad.y) * 0.4);
	if (!FRONT_FACING) pn = -pn;
	NORMAL = normalize(mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX * pn);
	ALBEDO = vec3(0.62, 0.72, 0.8) * 0.45;
	ROUGHNESS = 0.22;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	ALPHA = clamp(mask, 0.0, 1.0) * 0.3;
}
