shader_type canvas_item;

uniform vec2 reveal_position = vec2(0.0);
uniform float reveal_amount = 0.0;
uniform float reveal_radius = 76.0;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float hole = 1.0 - smoothstep(reveal_radius * 0.48, reveal_radius, distance(world_position, reveal_position));
	COLOR.a *= 1.0 - hole * reveal_amount * 0.88;
}
