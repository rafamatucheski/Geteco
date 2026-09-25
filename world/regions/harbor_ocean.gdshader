shader_type spatial;
render_mode specular_schlick_ggx;

// Mar de Harbor visto quase de cima. Com essa câmera o reflexo real quase não
// aparece e a água lia como chão pintado (análise de 2026-09-24): onda de ±6,5% na
// cor, rugosidade 0,48 e sombra da ponte com borda dura como em concreto.
// Aqui: ondas em três escalas, céu refletido falso nas faces das ondas (como nas
// poças da V1), brilho de sol em pontos e sombra recebida suavizada.
uniform vec3 shallow_color : source_color = vec3(0.055, 0.36, 0.37);
uniform vec3 deep_color : source_color = vec3(0.035, 0.14, 0.22);
uniform vec3 foam_color : source_color = vec3(0.56, 0.73, 0.70);
uniform vec3 sky_color : source_color = vec3(0.50, 0.66, 0.76);
// Quanto da sombra recebida sobrevive: água espalha luz por baixo da superfície.
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.45;
// Coordenada local 0..256 m (UV, montada por HarborOcean.gd). As ondas usam vetores
// de onda inteiros sobre esse período, então se repetem exatamente em 256 m e a
// troca de bloco não tem emenda.
varying vec2 local_xz;
const float PERIOD = 256.0;

void vertex() {
	local_xz = UV;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ruído de valor periódico: `cells` células por período.
float noise(vec2 p, float cells) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(mod(i, cells)), hash(mod(i + vec2(1.0, 0.0), cells)), u.x),
		mix(hash(mod(i + vec2(0.0, 1.0), cells)), hash(mod(i + vec2(1.0, 1.0), cells)), u.x), u.y);
}

// Onda com vetor inteiro (m, n) ciclos por período; comprimento = 256/|(m,n)|.
// Devolve altura (x) e inclinação (yz). `speed` em m/s.
vec3 wave(vec2 p, vec2 cycles, float amp, float speed, float t) {
	vec2 k = cycles * 6.2831853 / PERIOD;
	float phase = dot(p, k) - t * speed * length(k);
	return vec3(sin(phase) * amp, k * cos(phase) * amp);
}

vec3 ocean(vec2 p, float t) {
	vec3 h = vec3(0.0);
	// Ondulação longa (~9 m e ~6,6 m), que dá o movimento que se vê de longe.
	h += wave(p, vec2(10.0, 26.0), 0.09, 1.2, t);
	h += wave(p, vec2(-14.0, 36.0), 0.06, 1.0, t);
	// Marola média cruzada (~2,9 m e ~2,1 m).
	h += wave(p, vec2(84.0, -26.0), 0.022, 0.7, t);
	h += wave(p, vec2(-76.0, -95.0), 0.016, 0.6, t);
	// Encrespado fino (~1,4 m e ~1,1 m), deformado por ruído para não virar grade.
	vec2 warp = vec2(noise(p * 0.25 + t * 0.05, 64.0), noise(p * 0.25 + 17.0 - t * 0.04, 64.0)) - 0.5;
	vec2 q = p + warp * 2.0;
	h += wave(q, vec2(55.0, 172.0), 0.006, 0.45, t);
	h += wave(q, vec2(215.0, -86.0), 0.005, 0.4, t);
	return h;
}

void fragment() {
	vec2 p = local_xz;
	vec3 h = ocean(p, TIME);
	vec2 slope = h.yz;
	float distance_to_shore = COLOR.r * 24.0;
	float depth_mix = smoothstep(0.0, 22.0, distance_to_shore);
	vec3 water = mix(shallow_color, deep_color, depth_mix);
	// Crista clareia, cavado escurece: é o que desenha a onda vista de cima.
	water *= 1.0 + clamp(h.x * 2.2, -0.3, 0.3);
	// Céu refletido nas faces inclinadas para o norte (lado da câmera). Sem isso o
	// mar é uma cor chapada; com isso aparecem faixas claras que andam com a onda.
	float facing = clamp(-slope.y * 5.0 + length(slope) * 1.5, 0.0, 1.0);
	float streak = smoothstep(0.25, 0.9, facing) * mix(0.6, 1.0, noise(p * 0.75 + TIME * 0.1, 192.0));
	ALBEDO = mix(water, sky_color * 0.6, streak * 0.35);
	vec3 wave_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
	// Rugosidade baixa demais refletia o céu claro inteiro e estourava em branco
	// (captura de 2026-09-24); o brilho fino vem do light() abaixo.
	ROUGHNESS = 0.5;
	SPECULAR = 0.03;
}

void light() {
	// Sombra recebida suavizada: a ponte escurece a água, mas não recorta um "piso".
	// Só no sol: em lanterna, clarão de tiro e postes o ATTENUATION também traz a
	// queda por distância e o recorte do cone. Suavizado, deixava 55% da luz passar
	// sem queda e a lanterna acendia o mar inteiro de ciano (vídeo de 25/09/2026).
	float shade = LIGHT_IS_DIRECTIONAL ? mix(1.0 - shadow_strength, 1.0, ATTENUATION) : ATTENUATION;
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * lambert * shade * 0.9 / 3.14159265;
	// Brilho de sol em pontos: lóbulo estreito nas facetas que acertam o ângulo.
	vec3 half_vector = normalize(LIGHT + VIEW);
	float glint = pow(max(dot(NORMAL, half_vector), 0.0), 600.0);
	// Área lisa da ondulação longa acendia um clarão branco inteiro; o teto
	// deixa só pontos de brilho.
	SPECULAR_LIGHT += LIGHT_COLOR * min(glint, 0.35) * 0.6 * ATTENUATION;
}
