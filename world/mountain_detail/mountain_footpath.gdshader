shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
#include "res://world/regions/mountain_ground.gdshaderinc"
varying float mountain_weight;

void vertex() {
	mountain_weight = ground_mountain_weight((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz);
}

// Trilha de beira de estrada em Mountain: cascalho escuro com neve pisada, bordas
// que se desfazem no terreno. UV.x = 0 junto ao asfalto, 1 do lado do mato;
// UV.y = metros ao longo do trecho (valores pequenos: sem perda de precisão).
uniform vec3 gravel : source_color = vec3(0.30, 0.28, 0.25);
uniform vec3 packed_snow : source_color = vec3(0.62, 0.66, 0.70);

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

void fragment() {
	vec2 p = vec2(UV.x * 1.6, UV.y);
	float patches = noise(p * vec2(1.2, 0.4));
	float grain = noise(p * 7.0);
	// Pisada no meio da trilha, neve acumulada nas margens.
	float trodden = 1.0 - smoothstep(0.25, 0.5, abs(UV.x - 0.5));
	vec3 color = mix(packed_snow, gravel, clamp(trodden * 0.8 + patches * 0.4 - 0.15, 0.0, 1.0));
	color = mix(gravel, color, mountain_weight);
	color *= 0.88 + grain * 0.22;
	ALBEDO = color;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	float edge = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.78, 1.0, UV.x + (noise(p * vec2(2.0, 1.1)) - 0.5) * 0.25));
	ALPHA = edge;
}
