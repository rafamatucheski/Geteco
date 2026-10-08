shader_type spatial;
render_mode cull_back;

uniform float finish_kind = 0.0;

float hash2(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float grain_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash2(cell),hash2(cell+vec2(1.0,0.0)),f.x),mix(hash2(cell+vec2(0.0,1.0)),hash2(cell+vec2(1.0)),f.x),f.y);
}

void fragment() {
	// Authored vertex palette is sRGB, matching the neighbouring mountain kit.
	vec3 base = pow(max(COLOR.rgb,vec3(0.0)),vec3(2.2));
	float detail = 1.0;
	if (finish_kind < 0.5) {
		float broad = grain_noise(UV*vec2(5.0,43.0));
		float resolved = 1.0-smoothstep(0.35,1.5,length(fwidth(UV*70.0)));
		detail = 0.87+0.21*broad+resolved*0.025*sin(UV.y*70.0+broad*2.5);
	} else if (finish_kind < 1.5) {
		detail = 0.83+0.22*grain_noise(UV*7.0)+0.06*grain_noise(UV*29.0);
	} else if (finish_kind < 2.5) {
		float resolved = 1.0-smoothstep(0.3,1.2,length(fwidth(UV*100.0)));
		detail = 0.90+0.09*grain_noise(UV*8.0)+resolved*0.025*sin(UV.x*100.0)*sin(UV.y*100.0);
	} else {
		detail = 0.94+0.06*grain_noise(UV*18.0);
	}
	ALBEDO = base*detail;
	ROUGHNESS = finish_kind > 2.5 ? 0.96 : 0.89;
	METALLIC = 0.0;
}
