shader_type spatial;
uniform vec4 base_color : source_color;
uniform vec4 marking : source_color;
uniform int pattern = 0;
uniform bool anatomical_coordinates = false;
varying vec3 coat_point;
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453); }
void vertex() { coat_point=anatomical_coordinates ? vec3(UV2.x,UV.y,UV.x) : VERTEX; }
void fragment() {
	float mask=0.0;
	if (pattern==1) {
		vec2 p=vec2(coat_point.y,coat_point.z+coat_point.x*.37)*4.0;
		vec2 cell=floor(p), f=fract(p);
		float first=10.0, second=10.0;
		for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
			vec2 offset=vec2(float(x),float(y));
			float d=length(offset+hash2(cell+offset)-f);
			if(d<first) { second=first; first=d; } else { second=min(second,d); }
		}
		mask=smoothstep(.08,.16,second-first);
	} else if(pattern==2) {
		float wave=sin(coat_point.z*30.0+sin(coat_point.y*7.0)*2.0+sin(coat_point.x*10.0)*.8);
		mask=smoothstep(-.15,.10,wave);
	}
	ALBEDO=mix(base_color.rgb,marking.rgb,mask);
	ROUGHNESS=.93;
}
