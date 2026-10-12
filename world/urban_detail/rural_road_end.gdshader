shader_type spatial;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool textured = false;
uniform float roughness = 0.9;
uniform float specular = 0.5;
uniform vec4 mouth_0;
uniform vec4 mouth_1;
uniform float width_0;
uniform float width_1;
varying highp vec2 ground_point;

float hash_ground(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453); }
float wear_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash_ground(i),hash_ground(i+vec2(1,0)),f.x),mix(hash_ground(i+vec2(0,1)),hash_ground(i+vec2(1,1)),f.x),f.y);
}
float mouth_weight(vec4 mouth,float width) {
	vec2 offset=ground_point-mouth.xy;
	float along=dot(offset,mouth.zw);
	float side=abs(dot(offset,vec2(-mouth.w,mouth.z)));
	if (along < -4.8 || along > 1.75 || side > width+.9) return 0.0;
	float worn=wear_noise(ground_point*.85);
	float weight=smoothstep(-4.2+worn*.85,-.03,along);
	weight*=1.0-smoothstep(width,width+.9,side);
	return weight*(1.0-smoothstep(.75,1.75,along));
}
void vertex() { ground_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	vec3 base=base_color.rgb;
	if (textured) base*=texture(base_texture,ground_point/4.0).rgb;
	float weight=max(mouth_weight(mouth_0,width_0),mouth_weight(mouth_1,width_1));
	if (weight > 0.0) {
		vec3 earth=mix(texture(earth_texture,ground_point*.045).rgb,texture(earth_texture,ground_point*.48).rgb,.16);
		base=mix(base,earth,weight);
	}
	ALBEDO=base;
	ROUGHNESS=mix(roughness,.96,weight);
	SPECULAR=mix(specular,.06,weight);
}
