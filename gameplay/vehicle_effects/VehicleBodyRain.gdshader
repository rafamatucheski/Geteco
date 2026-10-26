shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://gameplay/vehicle_effects/VehicleRainDrops.gdshaderinc"

uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float falling : hint_range(0.0, 1.0) = 0.0;
uniform float bead_visibility = 1.0;
uniform float pattern_seed = 0.0;
uniform vec4 paint_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);
varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	surface_position = VERTEX * scale;
	surface_normal = NORMAL;
	VERTEX += NORMAL * 0.0007 / max(scale, vec3(0.001));
}

void fragment() {
	vec3 n = normalize(surface_normal);
	vec2 p;
	vec3 ax;
	vec3 ay;
	if (abs(n.y) > max(abs(n.x), abs(n.z))) {
		p = surface_position.xz; ax = vec3(1.0, 0.0, 0.0); ay = vec3(0.0, 0.0, 1.0);
	} else if (abs(n.x) > abs(n.z)) {
		p = surface_position.zy; ax = vec3(0.0, 0.0, 1.0); ay = vec3(0.0, 1.0, 0.0);
	} else {
		p = surface_position.xy; ax = vec3(1.0, 0.0, 0.0); ay = vec3(0.0, 1.0, 0.0);
	}
	float slope = 1.0 - abs(n.y);
	float density = wet * mix(0.22, 0.88, falling);
	vec3 fine = rain_beads(p, 65.0, density, falling, slope, TIME, pattern_seed);
	vec3 large = rain_beads(p + vec2(0.17, 0.31), 33.0, density * smoothstep(0.25, 0.95, falling) * 0.65, falling, slope, TIME, pattern_seed + 7.0);
	float mask = max(fine.x, large.x) * smoothstep(-0.25, 0.2, n.y);
	vec2 gradient = fine.yz + large.yz;
	vec3 pn = normalize(n + (ax * gradient.x + ay * gradient.y) * 0.35);
	NORMAL = normalize(mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX * pn);
	ALBEDO = paint_color.rgb;
	ROUGHNESS = 0.24;
	SPECULAR = 0.55;
	ALPHA = mask * bead_visibility * 0.38;
}
