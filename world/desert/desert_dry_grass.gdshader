shader_type spatial;
render_mode cull_disabled;
varying float height;
varying float camera_distance;
uniform bool distance_fade = false;
void vertex() {
	height=clamp(VERTEX.y/0.55,0.0,1.0);
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float gust=sin(TIME*1.1+world.x*0.07+world.z*0.041);
	VERTEX.x+=gust*height*height*0.075;
	VERTEX.z+=sin(TIME*0.8+world.x*0.06)*height*height*0.045;
	camera_distance=0.0;
	if (distance_fade) camera_distance=length((VIEW_MATRIX*MODEL_MATRIX*vec4(VERTEX,1.0)).xyz);
}
void fragment() {
	if (distance_fade) {
		float fade=1.0-smoothstep(75.0,115.0,camera_distance);
		float pixel=fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(0.06711056,0.00583715))));
		if (pixel>fade) discard;
	}
	vec3 straw=mix(vec3(0.28,0.24,0.16),vec3(0.52,0.46,0.30),height);
	ALBEDO=pow(straw,vec3(2.2))*COLOR.rgb;
	ROUGHNESS=1.0;
}
