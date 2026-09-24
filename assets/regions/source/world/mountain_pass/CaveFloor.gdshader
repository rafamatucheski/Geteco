shader_type spatial;
render_mode cull_disabled;
varying vec2 ground;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { ground = VERTEX.xz; }
void fragment() {
 float strata = noise(ground*1.3)*0.6 + noise(ground*4.8)*0.4;
 float grit = noise(ground*65.0);
 ALBEDO = mix(vec3(0.19,0.18,0.135),vec3(0.30,0.275,0.21),strata) * (0.86+grit*0.25);
 ROUGHNESS = 0.85 + strata*0.13;
}
