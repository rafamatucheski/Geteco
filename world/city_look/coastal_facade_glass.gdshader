shader_type spatial;
render_mode depth_draw_opaque, cull_back;

// Opaque coated glazing: the original upper floors have no room geometry.
// Keep ordinary lit material shading and the environment when no planar
// reflection is selected. No emission or second clearcoat highlight.
uniform vec3 glass_tint : source_color = vec3(0.48, 0.62, 0.69);
uniform float glass_roughness : hint_range(0.08, 0.5) = 0.20;
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.48;
uniform vec2 facade_height_range = vec2(4.12, 12.0);
// First pilaster X and distance between pilasters, in the unrotated mesh.
uniform vec2 facade_pane_layout = vec2(-8.0, 2.2);
uniform float facade_floor_height = 1.65;
uniform sampler2D reflection_texture : filter_linear_mipmap, repeat_disable;
// World -> reflected camera clip coordinates, provided by the shared manager.
uniform mat4 reflection_projection;
uniform bool reflection_enabled = false;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.8;
uniform vec2 reflection_texel_size = vec2(0.003125, 0.005556);
varying vec3 world_position;
varying float facade_height;
varying vec2 facade_local;

vec4 glass_reflection_tap(vec2 uv) {
	vec4 captured = texture(reflection_texture, uv);
	return vec4(captured.rgb * captured.a, captured.a);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facade_local = VERTEX.xy;
	facade_height = clamp((VERTEX.y - facade_height_range.x) /
		max(facade_height_range.y - facade_height_range.x, 0.01), 0.0, 1.0);
}

void fragment() {
	// Broad, restrained absorption variation describes coated glass even when
	// a reflection sees uniform pavement. It does not paint a white reflection,
	// alter normals or add light. Scene reflections remain projected below.
	float height_blend = smoothstep(0.0, 1.0, facade_height);
	// Each existing framed sheet has a small, fixed coating difference. These
	// boundaries coincide with the actual mullions, not scrolling shader noise.
	float column = floor((facade_local.x - facade_pane_layout.x) / max(facade_pane_layout.y, 0.01));
	float row = floor((facade_local.y - facade_height_range.x) / max(facade_floor_height, 0.01));
	float coating = sin(column * 1.73 + row * 2.41 + 0.6);
	float pane_tone = 1.0 + coating * 0.035;
	ALBEDO = glass_tint * mix(0.92, 1.04, height_blend) * pane_tone;
	ROUGHNESS = clamp(glass_roughness + (1.0 - height_blend) * 0.025 + (1.0 - coating) * 0.012, 0.08, 0.5);
	METALLIC = glass_metallic;
	SPECULAR = 0.8;
	// Contact is confined to 13cm immediately inside the physical reveals.
	// There is no full-pane dark overlay or repeated band at each floor.
	float pane_x = fract((facade_local.x - facade_pane_layout.x) / max(facade_pane_layout.y, 0.01)) * facade_pane_layout.y;
	float edge_x = min(pane_x, facade_pane_layout.y - pane_x) - 0.195;
	float edge_y = min(facade_local.y - facade_height_range.x, facade_height_range.y - facade_local.y);
	float contact = 1.0 - smoothstep(0.0, 0.13, max(0.0, min(edge_x, edge_y)));
	AO = mix(1.0, 0.78, contact);
	AO_LIGHT_AFFECT = 0.1;
	// Alpha 0 preserves the engine's environment radiance, including when the
	// shared camera is assigned elsewhere or the facade approaches a view edge.
	RADIANCE = vec4(0.0);
	if (reflection_enabled && reflection_strength > 0.001) {
		vec4 clip = reflection_projection * vec4(world_position, 1.0);
		if (clip.w > 0.0001) {
			vec2 projected = clip.xy / clip.w;
			vec2 uv = projected * vec2(0.5, -0.5) + vec2(0.5);
			vec2 edge = min(uv, vec2(1.0) - uv);
			vec2 margin = max(reflection_texel_size * 2.0, vec2(0.0001));
			float coverage = smoothstep(0.0, margin.x, edge.x) * smoothstep(0.0, margin.y, edge.y);
			if (coverage > 0.0) {
				// The custom radiance bypasses the sky's roughness convolution.
				// Four overlapping bilinear taps soften it too, with unit energy
				// and alpha-aware filtering at silhouettes. No extra capture pass.
				vec2 radius = reflection_texel_size * mix(0.45, 0.85, clamp(ROUGHNESS * 2.0, 0.0, 1.0));
				uv = clamp(uv, reflection_texel_size * 2.0, vec2(1.0) - reflection_texel_size * 2.0);
				vec4 reflected = glass_reflection_tap(uv + radius);
				reflected += glass_reflection_tap(uv - radius);
				reflected += glass_reflection_tap(uv + vec2(radius.x, -radius.y));
				reflected += glass_reflection_tap(uv + vec2(-radius.x, radius.y));
				reflected *= 0.25;
				reflected.rgb /= max(reflected.a, 0.0001);
				// Texture alpha is the producer's validity mask. Bounded radiance
				// blends with environment once; never add a glowing overlay.
				RADIANCE = vec4(clamp(reflected.rgb, vec3(0.0), vec3(4.0)),
					coverage * clamp(reflected.a, 0.0, 1.0) * reflection_strength);
			}
		}
	}
}
