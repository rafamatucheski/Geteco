shader_type canvas_item;
render_mode unshaded;
uniform float intensity : hint_range(0.0,1.0) = 0.0;
uniform float phase = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.38, 1.45, dot(p,p));
	float breath = 0.90 + 0.10 * sin(phase * 1.15);
	COLOR = vec4(0.24, 0.08, 0.12, edge * intensity * 0.28 * breath);
}
