shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
varying highp vec2 world_point;
void vertex() {
	world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
}
void fragment() {
	vec3 earth=texture(earth_texture,world_point*.045).rgb;
	vec3 detail=texture(earth_texture,world_point*.48).rgb;
	earth=mix(earth,detail,.16);
	vec3 grass=texture(grass_texture,world_point*.06).rgb;
	ALBEDO=mix(grass,earth,smoothstep(0.0,1.0,COLOR.a));
	ROUGHNESS=.96;
	SPECULAR=.06;
}
