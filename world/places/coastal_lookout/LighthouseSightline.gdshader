shader_type spatial;
render_mode depth_draw_opaque, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool textured = false;
uniform float texture_scale = .32;
uniform float roughness_value = .9;
uniform float metallic_value = 0.0;
uniform float specular_value = .18;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform bool cut_enabled = false;
uniform vec3 player_foot;
uniform vec3 camera_origin;
uniform vec3 camera_direction = vec3(0.0,.707,.707);
uniform float cut_radius = 1.17;
varying vec3 world_point;
varying vec3 world_normal;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	if (cut_enabled && world_point.y > player_foot.y + .10) {
		vec3 target = player_foot + vec3(0.0,.90,0.0);
		vec3 ray = camera_origin - target;
		float ray_length = length(ray);
		// Orthographic rays remain parallel even when walk lead shifts the
		// camera focus away from Dante. Use the actual camera view direction.
		vec3 axis = normalize(camera_direction);
		vec3 relative = world_point - target;
		float along = dot(relative,axis);
		vec3 lateral = relative - axis * along;
		if (along > .10 && along < ray_length && dot(lateral,lateral) < cut_radius * cut_radius) discard;
	}
	vec3 surface = albedo.rgb;
	if (textured) {
		vec3 blend = pow(abs(normalize(world_normal)),vec3(4.0));
		blend /= max(dot(blend,vec3(1.0)),.001);
		vec3 p = world_point * texture_scale;
		surface *= texture(albedo_texture,p.zy).rgb * blend.x
			+ texture(albedo_texture,p.xz).rgb * blend.y
			+ texture(albedo_texture,p.xy).rgb * blend.z;
	}
	ALBEDO = surface;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = emission_color * emission_energy;
}
