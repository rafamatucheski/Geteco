shader_type canvas_item;
render_mode unshaded;

varying vec4 icon_modulate;
uniform vec4 silhouette_color : source_color = vec4(0.9451, 0.9333, 0.9059, 1.0);

void vertex() {
	icon_modulate = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec2 pixel = (UV - 0.5) / TEXTURE_PIXEL_SIZE;
	vec2 half_size = 0.5 / TEXTURE_PIXEL_SIZE - vec2(13.0);
	float rounded_edge = length(max(abs(pixel) - half_size + vec2(10.0), vec2(0.0))) - 10.0;
	float inside = 1.0 - smoothstep(-0.5, 0.5, rounded_edge);
	float backing = 1.0 - smoothstep(0.008, 0.016, distance(texel.rgb, vec3(15.0, 18.0, 24.0) / 255.0));
	COLOR = icon_modulate * vec4(silhouette_color.rgb, texel.a * inside * (1.0 - backing));
}
