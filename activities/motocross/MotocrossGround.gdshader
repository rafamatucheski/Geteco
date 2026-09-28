shader_type spatial;
#include "res://activities/motocross/MotocrossLandscape.gdshaderinc"
varying highp vec2 ground_point;
void vertex() { ground_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	ALBEDO = landscape_color(ground_point);
	ROUGHNESS = .96;
	SPECULAR = .06;
}
