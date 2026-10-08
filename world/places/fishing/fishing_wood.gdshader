shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(.59,.47,.31,1.0);
varying vec3 timber;
void vertex() { timber = VERTEX; }
void fragment() {
	float bend = sin(timber.z*.8 + timber.y*.5)*.9;
	float grain = sin(timber.x*46.0 + bend) * sin(timber.x*13.0 + timber.z*.31);
	grain *= 1.0 - smoothstep(.5,2.6,fwidth(timber.x*46.0 + bend));
	float broad = sin(timber.z*.21 + timber.x*2.4);
	ALBEDO = base_color.rgb * (.94 + grain*.045 + broad*.035);
	ROUGHNESS = .90;
}
