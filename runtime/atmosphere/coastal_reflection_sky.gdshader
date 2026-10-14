shader_type sky;
// Broad marine sky/ground gradients, used for material reflections only.
// No tiny sun disk, TIME, camera position or dynamic light dependency.
uniform vec3 top_color : source_color = vec3(.38,.54,.62);
uniform vec3 horizon_color : source_color = vec3(.81,.73,.59);
uniform vec3 ground_color : source_color = vec3(.20,.24,.27);
uniform vec3 cloud_color : source_color = vec3(.92,.88,.80);
uniform float cloud_cover : hint_range(0.0,1.0) = 0.0;
uniform vec3 sun_direction = vec3(.25,.65,.72);
void sky() {
	float elevation = EYEDIR.y;
	vec3 upper = mix(horizon_color,top_color,smoothstep(0.0,.80,elevation));
	// Large, soft cloud banks survive a 64px cubemap and roughness filtering.
	// Their angular shape travels naturally over curved paint and glazing as
	// the view changes. There is no tiny highlight that can shimmer at distance.
	float banks = sin(EYEDIR.x*5.0+EYEDIR.z*3.0)*.5
		+ cos(EYEDIR.z*6.0-EYEDIR.y*4.0)*.3;
	float clouds = smoothstep(.12-cloud_cover*.65,.68-cloud_cover*.35,banks);
	clouds *= smoothstep(.0,.20,elevation)*(1.0-smoothstep(.72,.98,elevation));
	upper = mix(upper,cloud_color,clouds*mix(.40,.72,cloud_cover));
	float sun_shoulder = pow(max(dot(EYEDIR,normalize(sun_direction)),0.0),12.0);
	upper += cloud_color*sun_shoulder*.34*(1.0-smoothstep(.45,.85,cloud_cover));
	vec3 lower = mix(horizon_color*.55,ground_color,smoothstep(0.0,.65,-elevation));
	COLOR = mix(lower,upper,smoothstep(-.04,.04,elevation));
}
