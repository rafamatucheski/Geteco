shader_type spatial;
render_mode specular_disabled;
varying vec3 rock_position;
varying vec4 rock_tint;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
void vertex() {
	rock_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	// Mesh colours are authored sRGB, as in the original StandardMaterial3D.
	vec3 linear_tint=mix(COLOR.rgb/12.92,pow((COLOR.rgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),COLOR.rgb));
	rock_tint=vec4(linear_tint,COLOR.a);
}
void fragment() {
	vec3 p=rock_position;
	float along=p.x+p.z*.47;
	float erosion=texture(stone_noise,vec2(along*.0034,p.y*.0016)).r;
	float strata=sin(p.y*.52+texture(stone_noise,p.xz*.0014).r*3.4+erosion*.8);
	float ledge=smoothstep(.74,.98,strata);
	float grain=texture(stone_noise,vec2(along*.025,p.y*.033)).r;
	vec3 color=rock_tint.rgb*(.83+erosion*.24+grain*.10);
	color=mix(color,color*vec3(.74,.70,.65),ledge*.24);
	ALBEDO=color;
	ROUGHNESS=1.0;
}
