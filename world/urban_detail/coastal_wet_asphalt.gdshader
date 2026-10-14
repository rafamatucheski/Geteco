shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://world/urban_detail/coastal_planar_reflection.gdshaderinc"

uniform sampler2D base_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : repeat_enable, filter_linear_mipmap;
uniform float wetness : hint_range(0.0,1.0) = 0.0;
varying highp vec3 coastal_world_position;

void vertex() {
	coastal_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 ground_uv = coastal_world_position.xz/4.0;
	vec3 aggregate = coastal_asphalt_aggregate(texture(base_texture,ground_uv).rgb);
	float moisture = clamp(wetness,0.0,1.0);
	float film = smoothstep(0.05,1.0,moisture);
	float film_coverage = 0.0;
	if (film > 0.001) film_coverage = coastal_wet_film(coastal_world_position.xz);
	float rough_map = texture(roughness_texture,ground_uv).r;
	// .42 linear matches the existing .68 sRGB wet albedo multiplier.
	vec3 base = aggregate * mix(1.0,mix(0.57,0.42,film_coverage),moisture);
	vec4 reflected = vec4(0.0);
	if (film*film_coverage > 0.001) reflected = coastal_planar_sample(coastal_world_position,vec2(0.0),mix(1.10,0.80,film_coverage));
	float grazing = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
	// Wet asphalt stays predominantly pavement. Stronger mirror response is
	// reserved for actual puddles and glazing, not the whole street.
	float reflection_amount = reflected.a*film*film_coverage*(0.12+grazing*0.08);
	// Captured scene is already lit. Mix its radiance after local shading,
	// rather than multiplying it by the receiving pavement's shadow again.
	ALBEDO = base*(1.0-reflection_amount);
	EMISSION = reflected.rgb*reflection_amount;
	ROUGHNESS = mix(1.0,mix(0.90,0.56,film_coverage),moisture)*rough_map;
	METALLIC = 0.0;
	// A weak sky fallback is useful before capture becomes available. Once
	// planar reflection is present it supplies the wet film's reflected light.
	SPECULAR = film*film_coverage*0.10*(1.0-reflected.a);
}
