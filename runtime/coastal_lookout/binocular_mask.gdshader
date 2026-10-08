shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float left_lens = length(p - vec2(-0.235, 0.0));
	float right_lens = length(p - vec2(0.235, 0.0));
	float aperture = min(left_lens, right_lens);
	float mask = smoothstep(0.422, 0.446, aperture);
	float edge = smoothstep(0.30, 0.445, aperture) * 0.22;
	COLOR = vec4(vec3(0.008, 0.014, 0.015), max(mask, edge));
}
