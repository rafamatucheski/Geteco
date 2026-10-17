uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 venue_origin;
uniform bool road_surface = false;
uniform vec4 gravel_tint : source_color = vec4(0.5765,0.5333,0.4275,1.0);
varying highp vec2 world_point;

float rounded_box_distance(vec2 p,vec2 center,vec2 half_size,float radius) {
	vec2 q=abs(p-center)-half_size+vec2(radius);
	return length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
}

float path_distance(vec2 p,vec2 a,vec2 b) {
	vec2 edge=b-a;
	return length(p-a-edge*clamp(dot(p-a,edge)/dot(edge,edge),0.0,1.0));
}

float clearing_weight(vec2 p,float noise) {
	// The same lobes and radii as FishingSite._shore. The mask begins outside
	// the water/stone edge: the existing pond and its bottom are unchanged.
	vec2 q=p-vec2(0.0,-4.0);
	float angle=atan(q.y/18.0,q.x/27.0);
	float lobe=1.0+0.045*sin(angle*3.0+0.6)+0.025*cos(angle*5.0);
	vec2 shore=vec2(cos(angle)*27.0,sin(angle)*18.0)*lobe;
	float bank_distance=length(q)-length(shore);
	float dry_ground=smoothstep(0.22,0.48,bank_distance);
	float bank=dry_ground
		*(1.0-smoothstep(2.35,4.65,bank_distance+noise));
	// Broad corners follow parking and foot traffic, not the streaming grid.
	float parking=rounded_box_distance(p,vec2(-8.7,25.0),vec2(11.7,7.5),2.8);
	float counter=rounded_box_distance(p,vec2(10.0,22.1),vec2(5.9,4.8),2.5);
	float gate=path_distance(p,vec2(0.0,26.5),vec2(1.4,31.3))-3.1;
	float approach=path_distance(p,vec2(0.0,16.2),vec2(0.0,25.0))-1.9;
	float apron=min(min(parking,counter),min(gate,approach));
	float used_ground=1.0-smoothstep(-0.7,1.15,apron+noise);
	return max(bank,used_ground*dry_ground);
}

void vertex() {
	world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
}

void fragment() {
	vec3 grass=texture(grass_texture,world_point*0.16).rgb;
	vec2 local_point=world_point-venue_origin;
	bool near_venue=abs(local_point.x)<38.0 && local_point.y>-31.0 && local_point.y<36.0;
	// The venue owns a submerged bed. Do not draw the former flat meadow
	// through its transparent water; dry support and shore masks stay intact.
	if (near_venue) {
		vec2 pond_point=local_point-vec2(0.0,-4.0);
		float pond_angle=atan(pond_point.y/18.0,pond_point.x/27.0);
		float pond_lobe=1.0+0.045*sin(pond_angle*3.0+0.6)+0.025*cos(pond_angle*5.0);
		if (length(pond_point/vec2(27.0,18.0))<pond_lobe-0.002) { discard; }
	}
	vec3 earth=vec3(0.0);
	if (road_surface || near_venue) {
		// Exactly the rural road samples and weights outside the local mask.
		earth=mix(texture(earth_texture,world_point*0.045).rgb,
			texture(earth_texture,world_point*0.48).rgb,0.16);
	}
	vec3 base=road_surface ? mix(grass,earth,smoothstep(0.0,1.0,COLOR.a)) : grass;
	float coverage=0.0;
	if (near_venue) {
		float broad=texture(earth_texture,world_point*0.13).r;
		float edge_noise=(broad-0.18)*3.1
			+sin(local_point.x*0.59+local_point.y*0.24)*0.16
			+cos(local_point.y*0.73-local_point.x*0.19)*0.12;
		coverage=clearing_weight(local_point,edge_noise);
	}
	vec3 finish=base;
	if (coverage>0.0) {
		// Fine muted aggregate sits in the same earth as the access road.
		vec3 grain=texture(gravel_texture,world_point*0.48).rgb;
		vec3 packed_soil=mix(earth,grain*gravel_tint.rgb,0.48);
		finish=mix(base,packed_soil,coverage);
	}
	ALBEDO=finish;
	ROUGHNESS=0.96;
	SPECULAR=0.06;
}
