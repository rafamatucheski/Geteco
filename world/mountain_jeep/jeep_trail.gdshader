shader_type spatial;
render_mode cull_back;

float grain(vec2 p) {
	return fract(sin(dot(floor(p), vec2(127.1,311.7)))*43758.5453);
}

void fragment() {
	float detail = grain(UV * 13.0);
	float broad = sin(UV.y * 0.31 + sin(UV.x * 0.6)) * 0.5 + 0.5;
	vec3 earth = mix(vec3(0.23,0.19,0.14),vec3(0.43,0.43,0.39),0.55);
	earth *= 0.84 + detail * 0.18 + broad * 0.10;
	float tread = 1.0-smoothstep(0.12,0.26,abs(abs(UV.x)-0.90));
	earth *= 1.0-tread*(0.12+grain(UV*vec2(2.0,4.0))*0.05);
	float snow = smoothstep(2.65,6.65,abs(UV.x)+(broad-.5)*.7);
	vec3 frost = mix(vec3(.48,.56,.59),vec3(.72,.77,.76),broad);
	ALBEDO = mix(earth,frost*(.96+detail*.04),snow);
	ROUGHNESS = .96;
}
