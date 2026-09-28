shader_type spatial;
uniform vec4 base_color : source_color = vec4(.48,.35,.22,1.0);
uniform bool timber = true;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
 vec3 p = world_point;
 float grain = hash(floor(p.xz*29.0+p.y*vec2(7.0,41.0)));
 float board = smoothstep(.02,.06,fract(p.y*3.5));
 float streak = .5+.5*sin(p.y*153.0+sin(p.x*9.0+p.z*13.0)*2.0);
 float variation = timber ? (.82+.12*grain+.09*streak)*mix(.57,1.0,board) : .82+.25*grain;
 ALBEDO = base_color.rgb*variation;
 ROUGHNESS = .90;
}
