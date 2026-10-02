shader_type spatial;
render_mode cull_back;
varying vec3 water_world;

void vertex() {
	water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Volume fora do vidro: o fundo do canal substitui o céu vazio sob a água.
	float depth = clamp((-water_world.y - 0.94) / 6.2, 0.0, 1.0);
	float ripple = sin(water_world.x * 0.42 + water_world.z * 0.65 + TIME * 0.35)
		* sin(water_world.x * 0.18 - water_world.y * 1.7 - TIME * 0.25);
	vec3 water = mix(vec3(0.045, 0.32, 0.37), vec3(0.018, 0.105, 0.13), depth);
	ALBEDO = water * (1.0 + ripple * 0.12);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
