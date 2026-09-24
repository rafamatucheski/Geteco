shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.055, 0.36, 0.37);
uniform vec3 deep_color : source_color = vec3(0.035, 0.14, 0.22);
uniform vec3 foam_color : source_color = vec3(0.56, 0.73, 0.70);
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_xz;
	float a = dot(p, vec2(0.65, 1.8)) + sin(p.x * 0.43 + TIME * 0.17) * 1.1 + TIME * 0.85;
	float b = dot(p, vec2(-0.38, 2.7)) + sin(p.x * 0.71 - p.y * 0.21) * 0.8 - TIME * 0.65;
	float ripple = sin(a) * 0.6 + sin(b) * 0.4;
	float distance_to_shore = COLOR.r * 24.0;
	float depth_mix = smoothstep(0.0, 22.0, distance_to_shore);
	vec3 water = mix(shallow_color, deep_color, depth_mix);
	water *= 1.0 + ripple * 0.065;
	// Contact foam uses actual shoreline strips, not interpolated grid distance.
	ALBEDO = water;
	vec3 wave_normal = normalize(vec3(-cos(a) * 0.012 + cos(b) * 0.008, 1.0, -cos(a) * 0.026 - cos(b) * 0.016));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
	ROUGHNESS = 0.48;
	SPECULAR = 0.22;
}
