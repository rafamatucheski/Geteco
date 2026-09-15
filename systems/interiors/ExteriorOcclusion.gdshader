shader_type canvas_item;
uniform vec4 behind[16];
uniform vec4 ahead[16];
uniform int behind_count = 0;
uniform int ahead_count = 0;
varying vec2 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
bool inside(vec4 r) { return all(greaterThanEqual(world_point,r.xy)) && all(lessThanEqual(world_point,r.zw)); }
void fragment() {
 bool covered = false;
 for (int i=0; i<behind_count; i++) { covered = covered || inside(behind[i]); }
 for (int i=0; i<ahead_count; i++) { if (inside(ahead[i])) covered = false; }
 if (!covered) discard;

}
