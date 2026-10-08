shader_type sky;
render_mode use_debanding;

uniform vec4 base_color : source_color = vec4(.4,.5,.6,1.0);
uniform float region_weight = 1.0;
uniform float hour = .45;
uniform float cloud_cover = 0.0;
uniform float moon_phase = 1.0;
uniform sampler2D cloud_texture : repeat_enable, filter_linear_mipmap;
uniform float lightning_strength = 0.0;
uniform float strike_offset = 0.0;
uniform float strike_seed = 0.0;

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab=b-a;
	return length(p-a-ab*clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0));
}

void sky() {
	float day=smoothstep(.20,.29,hour)*(1.0-smoothstep(.72,.81,hour));
	float dusk=exp(-pow((hour-.755)/.060,2.0))+exp(-pow((hour-.235)/.050,2.0));
	vec3 zenith=mix(vec3(.010,.021,.043),vec3(.19,.36,.52),day);
	vec3 horizon=mix(vec3(.065,.080,.12),vec3(.69,.73,.73),day);
	horizon=mix(horizon,vec3(.88,.40,.19),clamp(dusk*.73,0.0,1.0));
	vec3 col=mix(horizon,zenith,pow(clamp(EYEDIR.y,0.0,1.0),.43));
	col=mix(col,base_color.rgb,cloud_cover*.48);
	// Dense storm cloud deck keeps the clear blue gradient from shining through.
	col=mix(col,base_color.rgb*.88,smoothstep(.72,1.0,cloud_cover)*.72);
	if (!AT_CUBEMAP_PASS) {
		// Both arcs cross the northern backdrop seen by the real side camera.
		float solar=(hour-.25)*6.2831853;
		vec3 sun_dir=normalize(vec3(cos(solar)*.38,sin(solar)*1.1,-.94));
		float moon_angle=(hour-.75)*6.2831853;
		vec3 moon_dir=normalize(vec3(cos(moon_angle)*.36,sin(moon_angle)*.78,-1.0));
		float sun_dot=dot(EYEDIR,sun_dir);
		float sun=smoothstep(.99970,.99987,sun_dot)*smoothstep(-.04,.035,sun_dir.y);
		float glow=pow(max(sun_dot,0.0),70.0)*.28*smoothstep(-.1,.02,sun_dir.y);
		col+=vec3(1.0,.53,.24)*glow*(1.0-cloud_cover*.8);
		col=mix(col,vec3(1.0,.86,.61),sun*(1.0-cloud_cover*.85));
		float moon_dot=dot(EYEDIR,moon_dir);
		float moon=smoothstep(.99965,.99981,moon_dot)*smoothstep(-.02,.035,moon_dir.y)*(1.0-day);
		float lunar_texture=.76+texture(cloud_texture,EYEDIR.xz*8.0).r*.24;
		col=mix(col,vec3(.74,.81,.88)*lunar_texture,moon*(.22+.78*moon_phase));
		// A cached seamless noise texture avoids per-pixel octave evaluation.
		vec2 plane=EYEDIR.xz/max(.12,EYEDIR.y+.20)*2.2+vec2(hour*3.2,hour*.8);
		float field=texture(cloud_texture,plane*.085).r;
		float cloud=smoothstep(.48-cloud_cover*.25,.72-cloud_cover*.24,field);
		cloud*=smoothstep(.005,.13,EYEDIR.y)*(1.0-smoothstep(.68,.97,EYEDIR.y));
		vec3 cloud_tint=mix(vec3(.09,.12,.18),vec3(.84,.85,.82),day);
		cloud_tint=mix(cloud_tint,vec3(.93,.61,.39),min(dusk*.6,1.0));
		cloud_tint*=mix(.72,1.08,field);
		cloud_tint=mix(cloud_tint,base_color.rgb*mix(.8,1.4,field),smoothstep(.72,1.0,cloud_cover));
		col=mix(col,cloud_tint,cloud*.84);
		// World-facing distant discharge, occluded by real mountain geometry.
		// Uses the existing storm envelope and delayed thunder, never a second timer.
		if (lightning_strength>.001 && EYEDIR.z<-.1 && EYEDIR.y>0.0) {
			vec2 p=EYEDIR.xy/(-EYEDIR.z);
			vec2 a=vec2(strike_offset,.52);
			float dist=10.0;
			float branch=10.0;
			for (int i=1;i<=9;i++) {
				float t=float(i)/9.0;
				float jitter=texture(cloud_texture,vec2(t*.79+strike_seed,.37+strike_seed)).r-.5;
				vec2 b=vec2(strike_offset+jitter*.27+t*.055,.52-t*.51);
				dist=min(dist,segment_distance(p,a,b));
				if (i==4) branch=segment_distance(p,b,b+vec2(-.095,-.1));
				a=b;
			}
			float core=1.0-smoothstep(.00065,.0022,dist);
			float fork=(1.0-smoothstep(.0004,.0012,branch))*.6;
			float halo=exp(-dist*180.0)*.30;
			float bloom=exp(-length(p-vec2(strike_offset,.39))*8.0)*.18;
			col+=vec3(.65,.79,1.0)*(core+fork+halo+bloom)*lightning_strength;
		}
	}
	COLOR=AT_CUBEMAP_PASS ? base_color.rgb : mix(base_color.rgb,col,region_weight);
}
