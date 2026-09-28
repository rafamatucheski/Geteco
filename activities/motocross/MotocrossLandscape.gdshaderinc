uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
float clearing_ellipse(vec2 p, vec2 center, vec2 radius) {
	return 1.0-smoothstep(.70,1.0,length((p-center)/radius));
}
vec3 landscape_color(vec2 p) {
	vec3 grass = texture(grass_texture,p*.06).rgb;
	vec3 earth = mix(texture(earth_texture,p*.045).rgb,texture(earth_texture,p*.65).rgb,.32);
	float noise = texture(earth_texture,p*.13).r-.22;
	vec2 irregular = p+vec2(sin(p.y*.83),cos(p.x*.71))*.38;
	float yard = max(clearing_ellipse(irregular,vec2(-224.5,-34.5),vec2(12.5,8.0)),
		max(clearing_ellipse(irregular,vec2(-233.5,-28),vec2(5,4.7)),
		clearing_ellipse(irregular,vec2(-214,-32),vec2(4.3,9.5))));
	float trail = (1.0-smoothstep(1.4,3.5,abs(p.x+225.0+sin(p.y*.17)*.3)+noise))
		*smoothstep(-41.0,-33.0,p.y)*(1.0-smoothstep(20.0,24.0,p.y));
	return mix(grass,earth,clamp(max(yard,trail),0.0,1.0));
}
