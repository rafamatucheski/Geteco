shader_type spatial;
// Gotas no vidro do veículo conduzido. Só a malha de vidro (cópia, sem tocar nos materiais do
// modelo), animada por TIME: nenhum script por quadro. O limpador apaga as gotas por onde passa
// (mesma fase de `VehicleWiper.gdshader`) e elas voltam a se formar depois.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform float rain : hint_range(0.0, 1.0) = 0.0;
// Amplitude do varrido (0 = estacionado/desligado, 1 = varrendo).
uniform float wiper_amp : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_period = 1.6;
// Pivôs (x,y no plano do para-brisa), comprimento e abertura angular do limpador.
uniform vec4 pivots = vec4(0.0);
uniform float wiper_length = 0.4;
uniform float wiper_sweep = 1.75;
uniform float wiper_park = 0.06;

varying vec3 mpos;
varying vec3 mnorm;
varying float is_front;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Uma camada de gotas: devolve máscara (x) e gradiente da superfície (yz).
vec3 layer(vec2 p, float cells, float density, float t, float seed) {
	vec2 q = p * cells;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash(id + seed);
	float h2 = hash(id * 1.7 + seed + 3.1);
	float h3 = hash(id * 2.3 + seed + 9.7);
	float life = fract(h3 + t * (0.035 + 0.05 * h2));
	// A gota só existe se a densidade da chuva a cobre; nasce, cresce e some no ciclo.
	float alive = step(h, density) * smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.88, 1.0, life));
	float slide = step(0.72, h2) * smoothstep(0.55, 1.0, life) * 0.32;
	vec2 c = (vec2(h, h2) - 0.5) * 0.36 - vec2(0.0, slide);
	float r = mix(0.10, 0.30, h2 * h2) * mix(0.5, 1.0, smoothstep(0.0, 0.5, life));
	vec2 d = (f - c) * vec2(1.0, 0.82);
	float dist = length(d);
	float m = smoothstep(r, r * 0.7, dist) * alive;
	return vec3(m, (f - c) / max(r, 0.01) * m);
}

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
	vec3 a = layer(p, 17.0, rain, t, 1.0);
	vec3 b = layer(p + vec2(0.37, 0.19), 7.5, rain * 0.85, t, 5.0);
	float mask = max(a.x, b.x);
	vec2 grad = a.yz * a.x + b.yz * b.x;
	// Garoa deixa só as gotas miúdas; a camada grande entra com chuva forte.
	// Limpador: tempo (em fase) desde que a lâmina passou por este ponto.
	float clear = 1.0;
	if (is_front > 0.5 && wiper_amp > 0.02) {
		float ph = fract(t / wiper_period);
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
	vec3 pn = normalize(n + (ax * grad.x + ay * grad.y) * 0.9);
	if (!FRONT_FACING) pn = -pn;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(pn, 0.0)).xyz);
	ALBEDO = vec3(0.62, 0.72, 0.8) * 0.45;
	ROUGHNESS = 0.06;
	SPECULAR = 0.95;
	METALLIC = 0.0;
	ALPHA = clamp(mask, 0.0, 1.0) * 0.5;
}
