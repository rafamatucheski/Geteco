shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform bool triplanar_enabled = false;
uniform bool world_triplanar = false;
uniform float triplanar_sharpness = 1.0;
uniform bool vertex_color_enabled = false;
uniform bool normal_enabled = false;
uniform float normal_scale = 1.0;
uniform float roughness_value = 0.8;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.5;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool unshaded_source = false;
uniform vec3 reveal_origin;
uniform vec3 reveal_ahead;
uniform vec3 reveal_to_camera;
uniform float reveal_radius = 2.5;
instance uniform float exterior_reveal_amount : instance_index(15) = 0.0;
varying vec3 reveal_world;
varying vec3 texture_position;
varying vec3 texture_weights;

void vertex() {
	reveal_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	texture_position = (world_triplanar ? reveal_world : VERTEX) * uv_scale + uv_offset;
	vec3 texture_normal = world_triplanar ? normalize(MODEL_NORMAL_MATRIX * NORMAL) : NORMAL;
	texture_weights = pow(abs(texture_normal), vec3(triplanar_sharpness));
	texture_weights /= max(dot(texture_weights, vec3(1.0)), 0.0001);
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	vec4 texel = texture(base_texture, UV);
	if (triplanar_enabled) {
		texel = texture(base_texture, texture_position.xy) * texture_weights.z;
		texel += texture(base_texture, texture_position.xz) * texture_weights.y;
		texel += texture(base_texture, texture_position.zy * vec2(-1.0, 1.0)) * texture_weights.x;
	}
	vec4 color = base_color * texel;
	if (vertex_color_enabled) { color *= COLOR; }
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = emission_color * texture(emission_texture, UV).rgb;
	if (unshaded_source) { EMISSION += ALBEDO; ALBEDO = vec3(0.0); }
	if (normal_enabled) { NORMAL_MAP = texture(normal_texture, UV).rgb; NORMAL_MAP_DEPTH = normal_scale; }
	vec3 view = normalize(reveal_to_camera);
	vec3 relative = reveal_world - reveal_origin;
	float depth = dot(relative, view);
	vec3 lateral = relative - view * depth;
	vec3 ahead = reveal_ahead - view * dot(reveal_ahead, view);
	float t = clamp(dot(lateral, ahead) / max(dot(ahead, ahead), 0.001), 0.0, 1.0);
	float distance_to_path = length(lateral - ahead * t);
	float window = 1.0 - smoothstep(reveal_radius * 0.65, reveal_radius, distance_to_path);
	// Ground at/behind the target and geometry beyond the lens stay intact.
	window *= smoothstep(0.35, 1.1, depth);
	window *= 1.0 - smoothstep(length(reveal_to_camera) - 0.5, length(reveal_to_camera), depth);
	ALPHA = color.a * (1.0 - window * exterior_reveal_amount);
}
