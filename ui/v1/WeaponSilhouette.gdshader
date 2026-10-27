shader_type canvas_item;
render_mode unshaded;

varying vec4 icon_modulate;
uniform vec4 silhouette_color : source_color = vec4(0.9451, 0.9333, 0.9059, 1.0);

void vertex() {
	icon_modulate = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// Artwork already has a clean alpha channel and filtered mip levels.
	COLOR = icon_modulate * vec4(silhouette_color.rgb, texel.a * silhouette_color.a);
}
