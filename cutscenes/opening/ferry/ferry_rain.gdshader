shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D rain_texture : source_color, filter_linear_mipmap;
uniform vec4 rain_color : source_color = vec4(0.56, 0.69, 0.79, 0.4);
varying float camera_visibility;

void vertex() {
	// Fade whole drops before they cross the lens and fill a frame as a flash.
	vec3 center = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
	camera_visibility = smoothstep(0.8, 1.8, length(center));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec4 drop = texture(rain_texture, UV);
	ALBEDO = drop.rgb * rain_color.rgb;
	ALPHA = drop.a * rain_color.a * camera_visibility;
}
