shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://world/urban_detail/coastal_planar_reflection.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : repeat_enable, filter_linear_mipmap;
uniform bool textured = false;
uniform bool mapped_roughness = false;
uniform float roughness = 0.9;
uniform float specular = 0.5;
uniform bool coastal_asphalt = false;
uniform float wetness : hint_range(0.0,1.0) = 0.0;
// Mesma macrovariação do asfalto do porto (coastal_wet_asphalt): sem ela a boca da rua rural
// virava um retângulo de tom liso no meio do asfalto manchado.
uniform float urban_wear : hint_range(0.0,1.0) = 0.0;
uniform vec4 mouth_0;
uniform vec4 mouth_1;
uniform float width_0;
uniform float width_1;
varying highp vec2 ground_point;
varying highp vec3 coastal_world_position;

float hash_ground(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453); }
float wear_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash_ground(i),hash_ground(i+vec2(1,0)),f.x),mix(hash_ground(i+vec2(0,1)),hash_ground(i+vec2(1,1)),f.x),f.y);
}
float mouth_weight(vec4 mouth,float width) {
	vec2 offset=ground_point-mouth.xy;
	float along=dot(offset,mouth.zw);
	float side=abs(dot(offset,vec2(-mouth.w,mouth.z)));
	if (along < -4.8 || along > 1.75 || side > width+.9) return 0.0;
	float worn=wear_noise(ground_point*.85);
	float weight=smoothstep(-4.2+worn*.85,-.03,along);
	weight*=1.0-smoothstep(width,width+.9,side);
	return weight*(1.0-smoothstep(.75,1.75,along));
}
void vertex() {
	coastal_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	ground_point=coastal_world_position.xz;
}
void fragment() {
	vec3 base=base_color.rgb;
	if (textured) base*=texture(base_texture,ground_point/4.0).rgb;
	float surface_roughness=roughness;
	float surface_specular=specular;
	float moisture=clamp(wetness,0.0,1.0);
	float film=smoothstep(0.05,1.0,moisture);
	float film_coverage=0.0;
	if (coastal_asphalt && film>0.001) film_coverage=coastal_wet_film(coastal_world_position.xz);
	if (coastal_asphalt) {
		base=coastal_asphalt_aggregate(base);
		if (urban_wear > 0.001) {
			float wear_rough=1.0;
			base=mix(base,coastal_urban_wear(base,ground_point,wear_rough),urban_wear);
		}
		base*=mix(1.0,mix(0.57,0.42,film_coverage),moisture);
		surface_roughness=mix(1.0,mix(0.90,0.56,film_coverage),moisture);
		surface_specular=film*film_coverage*0.10;
	}
	float weight=max(mouth_weight(mouth_0,width_0),mouth_weight(mouth_1,width_1));
	if (weight > 0.0) {
		vec3 earth=mix(texture(earth_texture,ground_point*.045).rgb,texture(earth_texture,ground_point*.48).rgb,.16);
		base=mix(base,earth,weight);
	}
	vec4 reflected=vec4(0.0);
	if (coastal_asphalt && film*film_coverage>0.001) reflected=coastal_planar_sample(coastal_world_position,vec2(0.0),mix(1.10,0.80,film_coverage));
	float grazing=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
	float reflection_amount=reflected.a*film*film_coverage*(0.12+grazing*0.08)*(1.0-weight);
	ALBEDO=base*(1.0-reflection_amount);
	EMISSION=reflected.rgb*reflection_amount;
	if (mapped_roughness) surface_roughness*=texture(roughness_texture,ground_point/4.0).r;
	ROUGHNESS=mix(surface_roughness,.96,weight);
	SPECULAR=mix(surface_specular*(1.0-reflected.a),.06,weight);
}
