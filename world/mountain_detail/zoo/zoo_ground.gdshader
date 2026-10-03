shader_type spatial;
render_mode diffuse_burley;
uniform vec4 soil : source_color = vec4(.6,.5,.35,1.0);
varying vec3 world_point;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float broad=noise(world_point.xz*.8);
	float grit=noise(world_point.xz*30.0);
	ALBEDO=soil.rgb*(.88+broad*.17+grit*.12);
	ROUGHNESS=.98;
}
