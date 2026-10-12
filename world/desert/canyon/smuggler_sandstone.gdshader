shader_type spatial;
// Local canyon sandstone. The flat sand calculation below deliberately matches
// desert_relief/desert_surface so the perimeter cannot expose a rectangular patch.
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.59,0.44,0.28,1.0);
uniform bool asphalt = false;
uniform bool shoulder = false;
varying highp vec3 world_pos;

vec3 surface_linear(vec3 srgb) {
	// ALBEDO is linear. Numeric art palettes need the same conversion as source_color.
	return mix(pow((srgb+vec3(0.055))/1.055,vec3(2.4)),srgb/12.92,step(srgb,vec3(0.04045)));
}

float hash(highp vec2 p) {
	highp vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
// Value and analytic derivatives: surface relief without extra texture samples,
// vertex displacement or changing the playable collision surface.
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
void vertex() {
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	highp vec2 p=world_pos.xz;
	float footprint=max(length(dFdx(p)),length(dFdy(p)));
	highp vec2 q=vec2(p.x*0.8-p.y*0.6,p.x*0.6+p.y*0.8);
	vec3 mineral=field(q*0.031+vec2(13.1,7.4));
	vec3 drift=field(p*0.17+mineral.x*1.7);
	vec3 grain=field(p*7.0);
	float grain_lod=1.0-smoothstep(0.025,0.075,footprint);
	vec3 color;
	vec2 slope;
	if(asphalt) {
		// Warm neutral aggregate, avoiding the old green cast of the road tint.
		vec3 old=surface_linear(vec3(0.225,0.219,0.208));
		vec3 worn=surface_linear(vec3(0.35,0.336,0.312));
		float patch=smoothstep(0.47,0.53,drift.x)*smoothstep(0.28,0.54,mineral.x);
		color=mix(old,worn,mineral.x)*mix(1.0,0.57,patch);
		color+=(grain.x-0.5)*0.022*grain_lod;
		float seam=abs(drift.x-0.47);
		float aa=max(fwidth(seam),0.001);
		float cracks=(1.0-smoothstep(0.003-aa,0.009+aa,seam))*smoothstep(0.45,0.68,mineral.x);
		color*=1.0-cracks*0.4;
		// Aggregate is fine grit, not raised paving stones. Keep the visible albedo
		// breakup while restraining the procedural normal to sub-degree relief.
		slope=grain.yz*0.012*grain_lod+drift.yz*0.008;
		ROUGHNESS=mix(0.96,0.83,patch);
	} else {
		vec3 sand=mix(surface_linear(vec3(0.49,0.36,0.22)),surface_linear(vec3(0.70,0.585,0.405)),smoothstep(0.12,0.88,mineral.x));
		// Retain authored apron tints, but reduce orange saturation across the basin.
		sand*=mix(vec3(1.0),base_color.rgb/surface_linear(vec3(0.725,0.627,0.475)),0.22);
		highp float phase=dot(p,vec2(1.15,0.43))+drift.x*3.5;
		float ripple_lod=1.0-smoothstep(0.3,1.1,footprint);
		float ripple=sin(phase)*ripple_lod;
		color=sand*(0.91+drift.x*0.18+ripple*0.055);
		color+=(grain.x-0.5)*0.014*grain_lod;
		float gravel=shoulder?COLOR.r:0.0;
		color=mix(color,color*vec3(0.67,0.72,0.77)+(grain.x-0.5)*grain_lod*0.020,gravel);
		color*=1.0-gravel*smoothstep(0.57,0.8,drift.x)*0.16;
		slope=cos(phase)*vec2(1.15,0.43)*0.12*ripple_lod+drift.yz*0.13;
		slope+=grain.yz*mix(0.024,0.075,gravel)*grain_lod;
		ROUGHNESS=0.98;
	}
	// Sedimentary rock emerges from the same sand, driven by slope and altitude.
	// Broad strata remain visible from the drag; fine mineral detail filters out.
	// Sand caps the desert and mesa; the excavated geological beds are sandstone,
	// including their benches. Elevation gives a continuous boundary independent
	// of triangulation instead of painting bright sand along every shelf normal.
	float exposure=smoothstep(0.15,3.5,-world_pos.y);
	vec2 rock_uv=vec2(p.x*0.71+p.y*0.49,world_pos.y);
	vec3 rock_field=field(rock_uv*vec2(0.19,0.11));
	vec3 erosion=field(rock_uv*vec2(1.25,0.18));
	vec3 rock_grain=field(rock_uv*5.0);
	float rock_pixel=max(length(dFdx(world_pos)),length(dFdy(world_pos)));
	float rock_lod=1.0-smoothstep(0.04,0.24,rock_pixel);
	// Unequal sediment beds only tint the rock. They are not alternating painted bars.
	float bedding=(world_pos.y+p.x*0.012+p.y*0.008+rock_field.x*1.7)*0.19;
	float bed_tone=hash(vec2(floor(bedding),17.0));
	float seam=1.0-smoothstep(0.018,0.07,abs(fract(bedding)-0.46));
	vec3 stone=mix(surface_linear(vec3(0.47,0.285,0.17)),surface_linear(vec3(0.73,0.515,0.32)),rock_field.x);
	stone*=0.86+bed_tone*0.18+mineral.x*0.06;
	stone*=1.0-seam*0.14;
	stone*=0.88+erosion.x*0.21;
	stone+=(rock_grain.x-0.5)*0.018*rock_lod;
	color=mix(color,stone,exposure);
	// Small chisel-like mineral variation on rock, filtered with screen footprint.
	slope=mix(slope,erosion.yz*0.18+rock_grain.yz*0.035*rock_lod,exposure);
	NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(-slope.x,0.0,-slope.y,0.0)).xyz*(1.0-exposure*0.85));
	ALBEDO=color;
}
