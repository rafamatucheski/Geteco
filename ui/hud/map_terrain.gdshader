shader_type canvas_item;
render_mode unshaded;
uniform sampler2D mineral_detail : source_color, repeat_enable, filter_linear_mipmap;
uniform float mineral_detail_strength : hint_range(0.0,1.0) = 0.0;
uniform float mineral_detail_world_size = 360.0;
varying highp vec2 world_point;
float hash12(highp vec2 p) {
	highp vec3 p3=fract(vec3(p.xyx)*.1031);
	p3+=dot(p3,p3.yzx+33.33);
	return fract((p3.x+p3.y)*p3.z);
}
float noise2(highp vec2 p) {
	highp vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	highp vec4 h=vec4(hash12(i),hash12(i+vec2(1,0)),hash12(i+vec2(0,1)),hash12(i+vec2(1,1)));
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void vertex() { world_point=VERTEX; }
void fragment() {
	vec3 base=COLOR.rgb;
	// Heights, snow, shorelines and hillshade are already sampled from production
	// geography into retained vertex colours. This is surface grain only: it
	// cannot add a navigable contour, a mountain, or a road to the atlas.
	float broad=noise2(world_point*.011);
	float mineral=noise2(world_point*.047+vec2(broad*3.1,-broad*1.7));
	float grain=noise2(world_point*.21+vec2(mineral*.9,broad));
	float grit=noise2(world_point*.72);
	float fine_weight=1.0-smoothstep(.9,2.5,length(fwidth(world_point)));
	float fleck=(grit-.5)*.13*fine_weight;
	float warmth=smoothstep(.01,.12,base.r-base.b);
	// Mineral mottling is deliberately much smaller than navigable landforms.
	float stone=abs(mineral-.5)*2.0;
	base*=1.0+(broad-.5)*.12+(mineral-.5)*.23+(grain-.5)*.14+fleck;
	base=mix(base,base*vec3(.83,.87,.88),stone*warmth*.24);
	if(mineral_detail_strength>0.0) {
		vec2 uv=world_point/max(mineral_detail_world_size,1.0);
		vec3 material_sample=texture(mineral_detail,uv).rgb;
		float mineral_value=dot(material_sample,vec3(.2126,.7152,.0722));
		base*=1.0+(mineral_value-.45)*mineral_detail_strength;
	}
	float alpha=COLOR.a;
	float desert_edge=min(min(world_point.x+1500.0,440.0-world_point.x),min(world_point.y+1950.0,-373.5-world_point.y));
	if(warmth>.1 && world_point.y< -270.0 && world_point.x<900.0) {
		// Material grades continuously across the runtime basin boundary. Alpha
		// comes only from the outside edge of the union of basin and escarpments.
		float outside=max(-desert_edge,0.0);
		float rock=smoothstep(20.0,450.0,outside)*warmth;
		base=mix(base,base*vec3(.54,.63,.67),rock*.72);
	}
	COLOR=vec4(base,alpha);
}
