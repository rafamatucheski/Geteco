shader_type canvas_item;
render_mode unshaded;
varying highp vec2 world_point;
float noise2(highp vec2 p) {
	highp vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	highp vec4 h=fract(sin(vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7))))*43758.5453);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void vertex() { world_point=VERTEX; }
void fragment() {
	vec3 base=COLOR.rgb;
	float n=noise2(world_point*.018)*.65+noise2(world_point*.047)*.25+noise2(world_point*.21)*.10;
	float natural=step(.015,abs(base.r-base.g));
	base*=1.0+(n-.5)*.16*natural;
	// Palette relief only, not survey contours or fabricated navigation data.
	if(base.b>base.r && base.g>base.r && base.r>.19) {
		float snow=smoothstep(445.0,610.0,-world_point.y+n*24.0);
		base=mix(base,vec3(.64,.69,.69)*( .85+n*.20),snow);
	}
	COLOR=vec4(base,COLOR.a);
}
