shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;
varying vec2 pond;
void vertex() { pond = VERTEX.xz; }
void fragment() {
	float broad = sin(pond.x * .29 + pond.y * .19) * .5 + .5;
	float ripple = sin(pond.x * 3.7 + pond.y * 1.1 + TIME * 1.1) * sin(pond.y * 4.4 - TIME * .85);
	ALBEDO = mix(vec3(.09,.25,.23), vec3(.17,.36,.30), broad) + ripple * .009;
	ROUGHNESS = .61;
	SPECULAR = .24;
}
