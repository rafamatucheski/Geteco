shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The train's authored materials are opaque StandardMaterial3D with constant
// PBR values. Keep their shading and clip only the occupied camera-ray prism.
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform float specular = 0.5;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform mat4 building_projection;
uniform vec3 building_cut_min;
uniform vec3 building_cut_max;
varying vec3 building_projected_position;

void vertex() {
	building_projected_position = (building_projection * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (all(greaterThan(building_projected_position, building_cut_min)) &&
			all(lessThan(building_projected_position, building_cut_max))) {
		discard;
	}
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	EMISSION = emission * emission_energy;
}
