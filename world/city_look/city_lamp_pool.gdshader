shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// This adds radiance over an already fogged floor. Applying the environment's
// coloured fog again turns zero-light texels into visible rectangular plates.

uniform sampler2D radial_texture : source_color, filter_linear;
uniform float night : hint_range(0.0,1.0) = 0.0;
uniform float diffuse_energy = 0.0;
uniform float wetness : hint_range(0.0,1.0) = 0.0;
varying vec3 ground_position;
varying flat vec3 pool_center;
varying flat float pool_size;

void vertex() {
	pool_center = MODEL_MATRIX[3].xyz;
	pool_size = max(length(MODEL_MATRIX[0].xyz),.01);
	// Preserve the established diffuse footprint. Geometry reflections now
	// come from the shared planar capture, not a second artificial light lobe.
	VERTEX.xz *= mix(1.0,1.30,wetness);
	ground_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 offset = ground_position.xz-pool_center.xz;
	vec2 radial_uv = offset/pool_size+vec2(.5);
	vec3 diffuse = texture(radial_texture,clamp(radial_uv,vec2(0.0),vec2(1.0))).rgb;
	diffuse *= diffuse_energy*mix(1.0,.32,wetness);
	ALBEDO = diffuse;
	ALPHA = 1.0;
}
