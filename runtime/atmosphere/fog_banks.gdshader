shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Bancos de névoa rasteira (FogBanks): plano horizontal que segue o foco, com o desenho
// preso ao mundo e arrastado pelo vento do clima. Sem textura de profundidade (proibida no
// jogo); paredes cortam o plano, então cada camada é fraca e as alturas são diferentes.
// Ruído por hash inteiro e periódico: o arrasto chega em `drift` já reduzido ao período
// (CELL*PERIOD m), e o desenho não pula na volta nem perde precisão depois de horas de vento.
const float CELL = 18.0;
const float PERIOD = 64.0;

uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.9, 1.0);
// 0 sem névoa; 1 bancos largos que tomam quase todo o chão.
uniform float coverage = 0.0;
uniform vec2 drift = vec2(0.0);
uniform vec2 center = vec2(0.0);
uniform float radius = 70.0;
instance uniform float layer = 0.0;
instance uniform float opacity = 0.0;
varying vec3 world;

float hash(vec2 cell, float seed) {
	uvec2 c = uvec2(cell) + uvec2(uint(seed) * 97u, uint(seed) * 61u);
	uint h = (c.x * 1597334677u) ^ (c.y * 3812015801u);
	h ^= h >> 16u;
	h *= 0x7feb352du;
	h ^= h >> 15u;
	h *= 0x846ca68bu;
	h ^= h >> 16u;
	return float(h) * (1.0 / 4294967295.0);
}

float value_noise(vec2 p, float period, float seed) {
	vec2 i = mod(floor(p), period);
	vec2 j = mod(i + 1.0, period);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i, seed);
	float b = hash(vec2(j.x, i.y), seed);
	float c = hash(vec2(i.x, j.y), seed);
	float d = hash(j, seed);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (world.xz + drift) / CELL;
	// As duas oitavas largas são as mesmas nas três camadas: o banco é um bolo só, com vão
	// limpo entre um e outro (sementes diferentes somavam um véu uniforme no chão todo).
	// Só o fiapo fino muda por camada.
	float n = value_noise(p, PERIOD, 0.0) * 0.55
		+ value_noise(p * 2.0, PERIOD * 2.0, 3.0) * 0.30
		+ value_noise(p * 4.0, PERIOD * 4.0, layer * 11.0 + 7.0) * 0.15;
	// Pouca cobertura = só os picos do ruído viram banco; muita = boa parte do chão, sempre
	// com vãos. A camada de cima afina antes: o banco fica mais baixo na borda.
	float threshold = mix(0.70, 0.47, coverage) + layer * 0.035;
	float bank = smoothstep(threshold - 0.04, threshold + 0.14, n);
	float dist = length(world.xz - center);
	// Borda do plano fora da tela; perto de quem joga a névoa abre um pouco para o corpo ler.
	float edge = 1.0 - smoothstep(radius * 0.72, radius, dist);
	float clear = mix(0.55, 1.0, smoothstep(2.5, 9.0, dist));
	ALBEDO = tint.rgb * (0.94 + 0.12 * n);
	ALPHA = bank * opacity * edge * clear;
}
