shader_type spatial;
render_mode diffuse_burley;
uniform int landform_kind = 0;
varying highp vec3 world_pos;

vec3 surface_linear(vec3 srgb) {
	return mix(pow((srgb+vec3(0.055))/1.055,vec3(2.4)),srgb/12.92,step(srgb,vec3(0.04045)));
}

float hash(highp vec2 p) {
	highp vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}

vec3 field(highp vec2 p) {
	highp vec2 i=floor(p);
	highp vec2 f=fract(p);
	vec2 u=f*f*f*(f*(f*6.0-15.0)+10.0);
	vec2 du=30.0*f*f*(f*(f-2.0)+1.0);
	float a=hash(i), b=hash(i+vec2(1.0,0.0));
	float c=hash(i+vec2(0.0,1.0)), d=hash(i+vec2(1.0,1.0));
	float k=a-b-c+d;
	return vec3(a+(b-a)*u.x+(c-a)*u.y+k*u.x*u.y,
		du.x*(b-a+k*u.y),du.y*(c-a+k*u.x));
}

float mineral_cracks(highp vec2 p, float footprint) {
	// Irregular dry polygons, with derivative filtering as they recede from view.
	highp vec2 cell=floor(p);
	highp vec2 local=fract(p);
	float first=10.0, second=10.0;
	for(int y=-1;y<=1;y++) {
		for(int x=-1;x<=1;x++) {
			vec2 offset=vec2(float(x),float(y));
			vec2 jitter=vec2(hash(cell+offset),hash(cell+offset+vec2(17.3,41.7)));
			vec2 delta=offset+0.18+jitter*0.64-local;
			float distance=dot(delta,delta);
			second=min(second,max(first,distance));
			first=min(first,distance);
		}
	}
	float edge=second-first;
	float aa=max(fwidth(edge),0.006);
	return (1.0-smoothstep(0.015-aa,0.035+aa,edge))*(1.0-smoothstep(0.35,1.2,footprint));
}

void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	highp vec2 p=world_pos.xz;
	float footprint=max(length(dFdx(p)),length(dFdy(p)));
	highp vec2 q=vec2(p.x*0.8-p.y*0.6,p.x*0.6+p.y*0.8);
	vec3 mineral=field(q*0.031+vec2(13.1,7.4));
	vec3 drift=field(p*0.17+mineral.x*1.7);
	vec3 grain=field(p*7.0);
	float grain_lod=1.0-smoothstep(0.025,0.075,footprint);
	float ripple_lod=1.0-smoothstep(0.3,1.1,footprint);
	float phase=dot(p,vec2(1.15,0.43))+drift.x*3.5;
	float ripple=sin(phase)*ripple_lod;
	// The border uses the same field, palette and normal as the existing basin.
	vec3 sand=mix(surface_linear(vec3(0.49,0.36,0.22)),surface_linear(vec3(0.70,0.585,0.405)),smoothstep(0.12,0.88,mineral.x));
	vec3 color=sand*(0.91+drift.x*0.18+ripple*0.055)+(grain.x-0.5)*0.014*grain_lod;
	vec2 slope=cos(phase)*vec2(1.15,0.43)*0.12*ripple_lod+drift.yz*0.13+grain.yz*0.024*grain_lod;
	float blend=clamp(COLOR.r,0.0,1.0);
	if(landform_kind==0) {
		vec3 dune=mix(surface_linear(vec3(0.73,0.605,0.40)),surface_linear(vec3(0.82,0.72,0.53)),mineral.x);
		color=mix(color,dune*(0.95+ripple*0.045+drift.x*0.08),blend*0.63);
	} else if(landform_kind==1) {
		vec3 mud=surface_linear(vec3(0.55,0.43,0.31))*(0.83+drift.x*0.25);
		float cracks=mineral_cracks(p*0.8,footprint)*COLOR.g;
		color=mix(color,mud*(1.0-cracks*0.29),blend*0.78);
		slope*=1.0-blend*0.6;
	} else if(landform_kind==2) {
		vec3 salt=mix(surface_linear(vec3(0.69,0.66,0.57)),surface_linear(vec3(0.87,0.85,0.76)),smoothstep(0.2,0.8,drift.x));
		float cracks=mineral_cracks(p*0.7,footprint);
		color=mix(color,salt*(1.0-cracks*0.33)+(grain.x-0.5)*0.012*grain_lod,blend);
		slope=mix(slope,grain.yz*0.018*grain_lod,blend);
	} else {
		color*=1.0-blend*0.29;
	}
	NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(-slope.x,0.0,-slope.y,0.0)).xyz);
	ALBEDO=color;
	ROUGHNESS=0.98;
}
