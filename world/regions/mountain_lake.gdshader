shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Lago de montanha. Antes: especular 0,75 com o céu claro de inverno deixava a
// água ciano pálido e chapada (captura de 2026-09-24). Agora a água é escura e
// fria, o céu entra como faixas nas ondas (como no mar de Harbor) e o reflexo do
// motor fica baixo. Coordenada local da malha do lago: sem perda de precisão.
uniform vec3 base_color : source_color = vec3(0.10, 0.31, 0.37);
uniform vec3 sky_color : source_color = vec3(0.62, 0.74, 0.82);
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
}

void fragment() {
	vec3 w = waves(local_xz, TIME);
	vec2 slope = w.yz;
	// A exposição de inverno de Mountain clareia a cena ~2,5x: com o albedo da V1 a
	// água saía ciano pálido, mais clara que o capim. Escura e menos saturada aqui.
	vec3 water = mix(base_color, vec3(dot(base_color, vec3(0.333))), 0.35) * 0.32 * (1.0 + w.x * 0.15);
	float facing = clamp(-slope.y * 18.0 + length(slope) * 5.0, 0.0, 1.0);
	float streak = smoothstep(0.35, 0.95, facing) * mix(0.5, 1.0, noise(local_xz * 0.6 + TIME * 0.08));
	ALBEDO = mix(water, sky_color * 0.3, streak * 0.3);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 0.45;
	SPECULAR = 0.08;
}
