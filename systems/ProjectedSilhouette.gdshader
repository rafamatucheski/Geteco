shader_type canvas_item;
render_mode unshaded;
uniform vec2 foot = vec2(0.0);
void vertex() {
	vec2 relative = VERTEX - foot;
	VERTEX = foot + vec2(relative.x - relative.y * 0.55, -relative.y * 0.38);
}
void fragment() {
	COLOR = vec4(vec3(0.025, 0.03, 0.045), COLOR.a * 0.36);
}
