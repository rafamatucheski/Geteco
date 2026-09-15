shader_type canvas_item;
render_mode unshaded;
uniform vec4 air_color = vec4(0.6, 0.7, 0.8, 1.0);
uniform float air_amount = 0.4;
void fragment() {
	// This material belongs only to the distant valley layer, below solid terrain.
	COLOR.rgb = mix(COLOR.rgb, air_color.rgb, air_amount);
}
