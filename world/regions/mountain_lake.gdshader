shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.10, 0.31, 0.37);
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float slow = sin(world_xz.x * 1.35 + world_xz.y * 0.52 + TIME * 0.85);
	float cross = sin(world_xz.x * -0.72 + world_xz.y * 1.65 - TIME * 1.12);
	VERTEX.y += slow * 0.011 + cross * 0.007;
}

void fragment() {
	float a = world_xz.x * 1.35 + world_xz.y * 0.52 + TIME * 0.85;
	float b = world_xz.x * -0.72 + world_xz.y * 1.65 - TIME * 1.12;
	float fine = sin(world_xz.x * 4.1 + TIME * 1.5) * sin(world_xz.y * 3.2 - TIME * 1.1);
	float ripple = sin(a) * 0.6 + sin(b) * 0.35 + fine * 0.05;
	vec3 normal_world = normalize(vec3(-cos(a) * 0.026 + cos(b) * 0.014, 1.0, -cos(a) * 0.010 - cos(b) * 0.032));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	ALBEDO = base_color * (1.0 + ripple * 0.10);
	ROUGHNESS = 0.24;
	SPECULAR = 0.75;
}
