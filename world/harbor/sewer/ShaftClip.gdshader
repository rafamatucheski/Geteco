shader_type canvas_item;

uniform float lip_y = 0.0;
uniform bool ceiling = false;
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	// Hard geometric occlusion, not a fade or a change in character scale.
	if ((!ceiling && local_y > lip_y) || (ceiling && local_y < lip_y)) {
		discard;
	}
}
