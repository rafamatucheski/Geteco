shader_type spatial;
render_mode diffuse_burley;
uniform vec4 ground_color : source_color = vec4(0.43,0.37,0.30,1.0);
uniform bool quarry_wall = false;
uniform vec3 world_origin = vec3(0.0);
// Mobile interpolation at z ~= -1800 must retain sub-metre precision. Work
// relative to the shared site origin and keep the noise/hash in high precision;
// otherwise neighbouring triangles acquire visibly different colour blocks.
varying highp vec3 world_point;
varying highp vec3 world_normal;
float hash(highp vec2 p) {
	highp vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float noise(highp vec2 p) {
	highp vec2 i=floor(p), f=fract(p); f=f*f*f*(f*(f*6.0-15.0)+10.0);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	world_point=(MODEL_MATRIX*vec4(VERTEX,1)).xyz-world_origin;
	world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	highp vec2 p=world_point.xz;
	float broad=noise(p*.07), dirt=noise(p*.42);
	float footprint=max(length(dFdx(p)),length(dFdy(p)));
	float grit=(noise(p*5.5)-.5)*(1.0-smoothstep(.03,.15,footprint));
	vec3 color=ground_color.rgb*(.74+broad*.35+dirt*.18+grit*.12);
	if(quarry_wall) {
		float layers=sin(world_point.y*1.4+noise(p*.08)*1.2);
		// Elevation does not make a wall: the horizontal pit floor must share
		// exactly the road's base colour, even 28 metres below the entrance.
		float slope=smoothstep(.015,.16,1.0-abs(normalize(world_normal).y));
		color*=mix(1.0,.9+layers*.105,slope);
		color=mix(color,color*vec3(1.1,.82,.67),smoothstep(.64,.83,noise(p*.14+world_point.y*.21))*.5*slope);
	}
	ALBEDO=color;
	ROUGHNESS=.98;
}
