shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://world/urban_detail/coastal_planar_reflection.gdshaderinc"

uniform sampler2D base_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : repeat_enable, filter_linear_mipmap;
uniform float wetness : hint_range(0.0,1.0) = 0.0;
// Asfalto da serra (MountainGroundFinish, GETECO_MOUNTAIN_GROUND): o mesmo material
// atravessa porto, ponte e serra; a geada vale só onde o chão já é de montanha
// (mesma rampa de WorldConnection3D.mountain_weight). 0 = desenho anterior.
uniform float mountain_finish = 0.0;
uniform vec2 frost_entry_x = vec2(559.375,651.25);
uniform vec2 frost_north_fade = vec2(-203.75,-128.75);
// Frente de neve da serra (0..1, ColdSurvival): pó de neve e bancos na nevasca.
uniform float snowfall : hint_range(0.0,1.0) = 0.0;
// Macrovariação de tom do asfalto urbano (HarborRoadWear.asphalt_amount; 0 = desenho anterior).
// Some onde a geada da serra começa: lá o desgaste é o de mountain_frost.
uniform float urban_wear : hint_range(0.0,1.0) = 0.0;
varying highp vec3 coastal_world_position;

void vertex() {
	coastal_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

float frost_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx)*0.1031);
	q += dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}

// Asfalto velho de serra: manchas de sal secas, remendos e pó de neve, que vira
// bancos alongados pelo vento quando a nevasca aperta.
vec3 mountain_frost(vec3 base, vec2 g, float frost, float footprint, out float snowy) {
	float stain = coastal_film_noise(g*0.19+vec2(5.1,-9.3));
	float patch = coastal_film_noise(g*0.043+vec2(-11.7,3.9));
	vec3 salt = vec3(0.105,0.108,0.112);
	vec3 color = mix(base, max(base,salt), smoothstep(0.52,0.80,stain*0.7+patch*0.3)*0.75);
	// Remendos escuros de recapeamento em parte do trecho.
	color *= 1.0 - smoothstep(0.66,0.70,patch)*0.28;
	// Pó de neve: grãos de 2-4 cm em manchas (o vento junta), quase nada com o tempo
	// firme e cobrindo com a frente; longe vira só a média clara, sem cintilar.
	float clump = smoothstep(0.35,0.85,coastal_film_noise(g*0.61+vec2(7.7,1.3)));
	float density = (0.015+snowfall*0.55)*clump;
	vec2 cell = floor(g*16.0);
	vec2 local = fract(g*16.0)-0.5;
	float present = step(frost_hash(cell+4.3),density);
	float radius = mix(0.10,0.24,frost_hash(cell+2.9));
	float grain = present*(1.0-smoothstep(radius-0.08,radius+0.08,length(local-(vec2(frost_hash(cell+1.7),frost_hash(cell+8.2))-0.5)*0.5)));
	float grain_lod = 1.0-smoothstep(0.01,0.04,footprint);
	float dust = mix(density*0.08,grain*0.6,grain_lod);
	// Bancos alongados no sentido do vento da serra (oeste-leste), não manchas redondas.
	float streak = coastal_film_noise(g*vec2(0.08,0.33)+vec2(3.3,-7.1));
	float drift = smoothstep(0.64,0.80,streak*0.6+patch*0.4+snowfall*0.16)*snowfall;
	snowy = clamp(dust*0.85+drift,0.0,1.0)*frost;
	return mix(base,mix(color,vec3(0.62,0.65,0.68),clamp(dust*0.85+drift,0.0,1.0)),frost);
}

void fragment() {
	vec2 ground_uv = coastal_world_position.xz/4.0;
	vec3 aggregate = coastal_asphalt_aggregate(texture(base_texture,ground_uv).rgb);
	float frost = 0.0;
	float frost_snow = 0.0;
	if (mountain_finish > 0.5) {
		frost = smoothstep(frost_entry_x.x,frost_entry_x.y,coastal_world_position.x)
			*(1.0-smoothstep(frost_north_fade.x,frost_north_fade.y,coastal_world_position.z));
	}
	float wear_rough = 1.0;
	float wear_amount = urban_wear*(1.0-frost);
	if (wear_amount > 0.001) {
		vec3 worn = coastal_urban_wear(aggregate,coastal_world_position.xz,wear_rough);
		aggregate = mix(aggregate,worn,wear_amount);
		wear_rough = mix(1.0,wear_rough,wear_amount);
	}
	float moisture = clamp(wetness,0.0,1.0);
	float film = smoothstep(0.05,1.0,moisture);
	float film_coverage = 0.0;
	if (film > 0.001) film_coverage = coastal_wet_film(coastal_world_position.xz);
	float rough_map = texture(roughness_texture,ground_uv).r*wear_rough;
	// .42 linear matches the existing .68 sRGB wet albedo multiplier.
	vec3 base = aggregate * mix(1.0,mix(0.57,0.42,film_coverage),moisture);
	// Dentro do ramo só conta sem derivada: a pegada é medida fora dele.
	float frost_footprint = max(length(dFdx(coastal_world_position.xz)),length(dFdy(coastal_world_position.xz)));
	if (frost > 0.001) base = mountain_frost(base,coastal_world_position.xz,frost,frost_footprint,frost_snow);
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
	ROUGHNESS = mix(mix(1.0,mix(0.90,0.56,film_coverage),moisture)*rough_map,0.9,frost_snow);
	METALLIC = 0.0;
	// A weak sky fallback is useful before capture becomes available. Once
	// planar reflection is present it supplies the wet film's reflected light.
	SPECULAR = film*film_coverage*0.10*(1.0-reflected.a);
}
