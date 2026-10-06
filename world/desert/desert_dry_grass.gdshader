shader_type spatial;
render_mode cull_disabled;
varying float height;
void vertex() {
	height=clamp(VERTEX.y/0.55,0.0,1.0);
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float gust=sin(TIME*1.1+world.x*0.07+world.z*0.041);
	VERTEX.x+=gust*height*height*0.075;
	VERTEX.z+=sin(TIME*0.8+world.x*0.06)*height*height*0.045;
}
void fragment() {
	vec3 straw=mix(vec3(0.28,0.24,0.16),vec3(0.52,0.46,0.30),height);
	ALBEDO=pow(straw,vec3(2.2))*COLOR.rgb;
	ROUGHNESS=1.0;
}
