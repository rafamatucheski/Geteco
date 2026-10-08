shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(.4,.37,.32,1.0);
uniform vec3 world_origin = vec3(0.0);
uniform bool floor_mode = false;
varying highp vec3 mineral_point;
float mineral_hash(highp vec2 p) {
	highp vec3 q=fract(vec3(p.xyx)*.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float mineral_noise(highp vec2 p) {
	highp vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(mineral_hash(i),mineral_hash(i+vec2(1,0)),f.x),mix(mineral_hash(i+vec2(0,1)),mineral_hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { mineral_point=(MODEL_MATRIX*vec4(VERTEX,1)).xyz-world_origin; }
void fragment() {
	highp vec2 plane=mineral_point.xz+mineral_point.y*vec2(.31,.47);
	float patch=mineral_noise(plane*.47);
	float fragments=mineral_noise(plane*3.4);
	float footprint=max(length(dFdx(plane)),length(dFdy(plane)));
	float grain=(fragments-.5)*(1.0-smoothstep(.12,.48,footprint));
	vec3 stone=base_color.rgb*(.64+patch*.66+grain*.25);
	if(floor_mode) {
		// Coal dust, pale chipped gravel and compacted wheel paths are part of
		// the existing floor surface, with no floating decal or new geometry.
		float gravel=smoothstep(.60,.80,fragments)*(1.0-smoothstep(.18,.5,footprint));
		stone=mix(stone,base_color.rgb*1.65,gravel*.36);
		float rail_lane=min(abs(mineral_point.x+7.5),abs(mineral_point.x-9.0));
		float worn=(1.0-smoothstep(.6,1.35,rail_lane))*(1.0-smoothstep(10.0,12.0,abs(mineral_point.z)));
		stone*=1.0+worn*.18;
		float coal=smoothstep(.58,.77,patch)*(1.0-worn*.65);
		stone=mix(stone,base_color.rgb*.36,coal*.6);
		ROUGHNESS=.91;
	} else {
		float strata=abs(sin(mineral_point.y*4.2+mineral_point.x*.2+mineral_point.z*.13+(patch-.5)*2.5));
		float seam=1.0-smoothstep(.055,.22,strata);
		stone*=1.0-seam*.27;
		stone=mix(stone,stone*vec3(1.13,.88,.70),smoothstep(.61,.83,patch)*.45);
		ROUGHNESS=.97;
	}
	ALBEDO=stone*COLOR.rgb;
}
