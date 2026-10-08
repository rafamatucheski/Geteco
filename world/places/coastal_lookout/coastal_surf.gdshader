shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
// Broken, directional wash follows the sea-facing sides of submerged rocks.
// Work in metres close to the mesh origin: no distant-world precision loss.
uniform vec2 rock_radius = vec2(3.0);
uniform float wave_phase = 0.0;
varying vec2 shore_point;
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0,0.0)),u.x),
		mix(hash(i + vec2(0.0,1.0)),hash(i + vec2(1.0)),u.x),u.y);
}
void vertex() {
	shore_point = VERTEX.xz;
	float impact = pow(max(0.0,sin(TIME * 1.1 + wave_phase)),4.0);
	float contact = 1.0 - smoothstep(.93,1.22,length(VERTEX.xz / rock_radius));
	VERTEX.y += impact * .17 * contact;
}
void fragment() {
	vec2 p = shore_point;
	vec2 flow = vec2(.14,.35) * TIME;
	float broad = noise(p * .72 - flow + wave_phase);
	float detail = noise(p * 2.1 - flow * 1.7);
	float radius = length(p / rock_radius);
	// A noisy footprint breaks the outline instead of tracing a white ellipse.
	float reach = 1.0 - smoothstep(1.02,1.52,radius + (broad-.5)*.38);
	float exposed = smoothstep(-.40,.35,dot(normalize(p + vec2(.001)),vec2(.15,-.99)));
	float swell = .5 + .5*sin(TIME * 1.1 + wave_phase + p.y*.32);
	float fragments = smoothstep(.46,.74,broad*.58 + detail*.42);
	float spent = smoothstep(.58,.83,detail) * .16;
	float foam = (fragments * (.24 + swell*.45) + spent) * reach * exposed;
	if (foam < .025) discard;
	ALBEDO = vec3(.76,.86,.82);
	ROUGHNESS = .96;
	SPECULAR = .04;
	ALPHA = min(.57,foam);
}
