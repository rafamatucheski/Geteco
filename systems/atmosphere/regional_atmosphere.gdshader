shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D mist_texture : repeat_enable, filter_linear;
uniform vec4 shadow_tint = vec4(1.0);
uniform vec4 sunlight_tint = vec4(1.0);
uniform vec4 fog_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float exposure = 1.0;
uniform float haze = 0.0;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 world_axis_x = vec2(1280.0, 0.0);
uniform vec2 world_axis_y = vec2(0.0, 720.0);
uniform vec2 focus_world = vec2(0.0);
uniform vec2 drift = vec2(0.0);

void fragment() {
	vec3 src = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float luminance = dot(src, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luminance), src, saturation);
	float lit = smoothstep(0.20, 0.78, luminance);
	graded *= mix(shadow_tint.rgb, sunlight_tint.rgb, lit);
	// Contrast about mid gray, with black protected from an artificial fog lift.
	graded = max(vec3(0.0), (graded - 0.45) * contrast + 0.45);
	vec2 world = world_origin + SCREEN_UV.x * world_axis_x + SCREEN_UV.y * world_axis_y;
	float broad = texture(mist_texture, (world + drift) / 1700.0).r;
	float detail = texture(mist_texture, (world - drift * 0.37) / 610.0).r;
	// Top-down atmosphere: distance from the actor is a readability mask, not 3D depth.
	float outside_focus = smoothstep(85.0, 520.0, length(world - focus_world));
	float air = haze * outside_focus * (0.25 + 0.95 * broad * detail);
	COLOR = vec4(mix(graded, fog_color.rgb, clamp(air, 0.0, 0.24)) * exposure, 1.0);
}
