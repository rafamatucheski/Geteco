shader_type spatial;
render_mode diffuse_lambert;
#include "res://activities/motocross/MotocrossLandscape.gdshaderinc"
varying highp vec2 ground_point;
void vertex() {
	ground_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	vec3 meadow = landscape_color(ground_point);
	vec3 earth = mix(texture(earth_texture,ground_point*.045).rgb,
		texture(earth_texture,ground_point*.65).rgb,.32);
	ALBEDO = mix(meadow,earth,smoothstep(0.0,1.0,COLOR.a));
	ROUGHNESS = .96;
	SPECULAR = .06;
}
