shader_type spatial;
render_mode cull_back;
#include "res://activities/motocross/MotocrossLandscape.gdshaderinc"
uniform sampler2D soil_noise : repeat_enable, filter_linear_mipmap;
uniform float wetness : hint_range(0.0,1.0) = 0.0;
uniform bool track_surface = true;
varying vec3 world_point;
varying vec3 world_normal;
varying float grass_mask;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	grass_mask = COLOR.r;
}
void fragment() {
	float broad = texture(soil_noise,world_point.xz*.022).r;
	float grain = texture(soil_noise,world_point.xz*.46).r;
	float grit = texture(soil_noise,world_point.xz*2.7).r;
	vec3 dry = mix(vec3(.28,.072,.024),vec3(.59,.205,.069),broad*.65+grain*.35);
	float grooves = 0.0;
	float grass = 0.0;
	if (track_surface) {
		float wandering = texture(soil_noise,vec2(UV.y*.008,UV.x*.4)).r*.11;
		grooves = pow(abs(sin((UV.x+wandering)*92.0)),18.0)*.34;
		dry *= 1.0-grooves;
	} else {
		grass = grass_mask*smoothstep(.72,.95,world_normal.y);
		dry = mix(dry,landscape_color(world_point.xz),grass);
	}
	float water = wetness*smoothstep(.46,.64,broad+grooves*.25)*smoothstep(.8,.99,world_normal.y)*(1.0-grass);
	vec3 mud = mix(vec3(.105,.041,.022),vec3(.23,.087,.036),grain);
	ALBEDO = mix(dry,mud,wetness*.9*(1.0-grass))*mix(0.8+grit*.38,1.0,grass);
	ALBEDO = mix(ALBEDO,vec3(.125,.073,.047),water*.55);
	ROUGHNESS = mix(.96,.62,wetness)-water*.19;
	SPECULAR = mix(.18,.40,wetness)*(1.0-grass*.5);
}
