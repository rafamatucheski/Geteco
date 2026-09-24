shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform bool pool = false;
uniform float phase = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 if (!pool) {
  VERTEX.z += sin(UV.y*26.0-TIME*7.0+UV.x*9.0)*0.035;
  VERTEX.x *= 0.84 + 0.14*sin(UV.y*5.0+phase*4.0);
 }
 else VERTEX.y += sin(VERTEX.x*4.0+TIME*2.0)*0.018;
}
void fragment() {
 float n=noise(vec2(UV.x*8.0+phase*11.0,UV.y*5.0-TIME*1.8));
 float streak=noise(vec2(UV.x*21.0+phase*7.0,UV.y*3.0-TIME*3.8));
 if (!pool) {
  float edge=smoothstep(0.0,0.12,UV.x)*smoothstep(0.0,0.12,1.0-UV.x);
  float froth=smoothstep(0.60,0.96,n+streak*0.25);
  ALBEDO=mix(vec3(0.17,0.39,0.40),vec3(0.76,0.89,0.85),froth);
  ALPHA=edge*(0.42+0.42*streak)*smoothstep(0.0,0.06,UV.y); ROUGHNESS=0.3;
 } else {
  vec2 q=(UV-0.5)*2.0; float d=length(q);
  float ripple=sin(length(q-vec2(0.0,-0.4))*30.0-TIME*3.5+noise(q*6.0)*3.0)*0.5+0.5;
  float foam=smoothstep(0.74,0.98,d)*noise(q*38.0+TIME*0.5);
  ALBEDO=mix(vec3(0.045,0.19,0.20),vec3(0.20,0.43,0.42),ripple*0.12+n*0.35);
  ALBEDO=mix(ALBEDO,vec3(0.76,0.87,0.83),foam);
  ALPHA=1.0-smoothstep(0.87,1.0,d); ROUGHNESS=0.27;
 }
}
