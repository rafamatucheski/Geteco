// Corpo comum dos lagos de montanha: mountain_lake.gdshader (sem fundo), mountain_lake_alpine.gdshader
// (fundo pelo mapa de alturas do terreno) e mountain_lake_depth.gdshader (fundo lido no depth, só A/B).

// Lago de montanha. Escuro e frio (a exposição de inverno de Mountain clareia a
// cena ~2,5x; com o albedo da V1 a água saía ciano pálido), céu só em faixas nas
// ondas e reflexo do motor baixo. Coordenada local da malha: sem perda de precisão.
//
// `depth_fade` = 1 (lago alpino, que tem bacia no terreno): a cor e a opacidade
// vêm da profundidade real da água sobre o fundo, lida no buffer de profundidade.
// No raso a água é transparente e deixa ver a lama da margem; escurece ao
// aprofundar; espuma fina na linha d'água. Sem isso o lago era um plano opaco de
// borda dura sobre o capim (relato do jogador em 2026-09-24).
uniform vec3 base_color : source_color = vec3(0.10, 0.31, 0.37);
uniform vec3 sky_color : source_color = vec3(0.62, 0.74, 0.82);
uniform vec3 foam_color : source_color = vec3(0.70, 0.76, 0.76);
uniform float clear_depth = 0.25;
uniform float dark_depth = 0.6;
#ifdef LAKE_DEPTH_TEXTURE
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
#endif
#ifdef LAKE_FLOOR_MAP
// Fundo do lago sem ler o depth (16/10): com MSAA, um material vivo com hint_depth_texture
// tirava do jogo inteiro a pré-compilação de pipelines do Forward Mobile (ver
// occluded_silhouette.gdshader). NativeLake grava aqui as alturas dos cantos da grade do
// terreno da serra (MountainTerrain3D.height_at, passo STEP), e o shader refaz a mesma
// interpolação por triângulo de surface_height_at/build_chunk: o mesmo fundo que o depth via.
uniform sampler2D floor_heights : filter_nearest;
uniform vec2 floor_origin = vec2(0.0);
uniform float floor_step = 4.0;
uniform ivec2 floor_size = ivec2(2);
// Vértice da malha (relativo ao NativeLake) + floor_offset = coordenada do terreno.
uniform vec3 floor_offset = vec3(0.0);
varying vec3 floor_position;
varying vec3 floor_direction;

float floor_height(vec2 p) {
	vec2 g = (p - floor_origin) / floor_step;
	ivec2 i = clamp(ivec2(floor(g)), ivec2(0), floor_size - ivec2(2));
	vec2 f = clamp(g - vec2(i), vec2(0.0), vec2(1.0));
	float a = texelFetch(floor_heights, i, 0).r;
	float b = texelFetch(floor_heights, i + ivec2(1, 0), 0).r;
	float c = texelFetch(floor_heights, i + ivec2(0, 1), 0).r;
	float d = texelFetch(floor_heights, i + ivec2(1, 1), 0).r;
	if (f.x + f.y <= 1.0) return a + (b - a) * f.x + (c - a) * f.y;
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y);
}

// Distância ao longo do raio da câmera entre a superfície e o fundo, como a versão do depth.
float floor_thickness(vec3 p, vec3 direction) {
	vec3 dir = normalize(direction);
	float down = max(-dir.y, 0.05);
	float t = max(0.0, p.y - floor_height(p.xz)) / down;
	// Fundo inclinado: refina o encontro do raio com o terreno.
	for (int k = 0; k < 3; k++) {
		vec3 q = p + dir * t;
		t = max(0.0, t + (q.y - floor_height(q.xz)) / down);
	}
	return t;
}
#endif
#if defined(LAKE_DEPTH_TEXTURE) || defined(LAKE_FLOOR_MAP)
instance uniform float depth_fade = 0.0;
#endif
varying vec2 local_xz;

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

vec3 waves(vec2 p, float t) {
	float a = dot(p, vec2(0.9, 0.4)) * 1.3 + t * 0.7;
	float b = dot(p, vec2(-0.5, 1.0)) * 1.9 - t * 0.9;
	vec2 q = p + vec2(noise(p * 0.3 + t * 0.05), noise(p * 0.3 - t * 0.04)) * 2.0;
	float c = dot(q, vec2(0.2, -1.0)) * 4.3 + t * 1.3;
	float h = sin(a) * 0.5 + sin(b) * 0.3 + sin(c) * 0.12;
	vec2 slope = vec2(0.9, 0.4) * cos(a) * 0.5 * 1.3 + vec2(-0.5, 1.0) * cos(b) * 0.3 * 1.9 + vec2(0.2, -1.0) * cos(c) * 0.12 * 4.3;
	return vec3(h, slope * 0.02);
}

void vertex() {
	local_xz = VERTEX.xz;
	VERTEX.y += waves(local_xz, TIME).x * 0.008;
#ifdef LAKE_FLOOR_MAP
	floor_position = VERTEX + floor_offset;
	// Raio da câmera no espaço da malha. Câmera ortográfica (CameraRig): raios paralelos ao eixo de visão.
	mat4 to_model = inverse(MODEL_MATRIX);
	vec3 camera_model = (to_model * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 forward_model = (to_model * vec4(-INV_VIEW_MATRIX[2].xyz, 0.0)).xyz;
	floor_direction = PROJECTION_MATRIX[3][3] > 0.5 ? forward_model : VERTEX - camera_model;
#endif
}

void fragment() {
	vec3 w = waves(local_xz, TIME);
	vec2 slope = w.yz;
	vec3 deep = mix(base_color, vec3(dot(base_color, vec3(0.333))), 0.35) * 0.32;
	float alpha = 1.0;
	vec3 water = deep;
	float foam = 0.0;
#if defined(LAKE_DEPTH_TEXTURE) || defined(LAKE_FLOOR_MAP)
	if (depth_fade > 0.5) {
#ifdef LAKE_DEPTH_TEXTURE
		// Distância, ao longo do raio da câmera, entre a superfície e o fundo.
		float z = texture(depth_tex, SCREEN_UV).r;
		vec4 floor_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
		floor_view.xyz /= floor_view.w;
		float thickness = max(0.0, length(floor_view.xyz) - length(VERTEX));
#else
		float thickness = floor_thickness(floor_position, floor_direction);
#endif
		float depth01 = smoothstep(0.0, dark_depth, thickness);
		// Raso: verde-acinzentado claro sobre a lama; fundo: azul escuro.
		// Raso quase transparente: deixa ver a lama e só a escurece. Cor clara no
		// raso virava um véu leitoso sobre a margem.
		vec3 shallow = deep * 0.8;
		water = mix(shallow, deep, depth01);
		alpha = mix(0.08, 0.95, smoothstep(0.0, clear_depth, thickness));
		// Linha d'água: faixa fina de espuma que respira com as ondas.
		float edge = 1.0 - smoothstep(0.0, 0.04 + w.x * 0.015, thickness);
		foam = edge * mix(0.1, 0.35, noise(local_xz * 3.0 + TIME * 0.3));
		alpha = max(alpha, foam * 0.8);
	}
#endif
	water *= 1.0 + w.x * 0.15;
	float facing = clamp(-slope.y * 18.0 + length(slope) * 5.0, 0.0, 1.0);
	float streak = smoothstep(0.35, 0.95, facing) * mix(0.5, 1.0, noise(local_xz * 0.6 + TIME * 0.08));
	ALBEDO = mix(mix(water, sky_color * 0.3, streak * 0.3), foam_color, foam);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 0.45;
	SPECULAR = 0.08;
	ALPHA = alpha;
}
