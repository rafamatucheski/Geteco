shader_type spatial;
render_mode diffuse_burley;

uniform vec2 court_center;
uniform vec2 court_half_size;
uniform vec4 sand_tint : source_color = vec4(0.725, 0.627, 0.475, 1.0);
uniform bool parking_paint = false;
varying highp vec2 world_ground;

vec3 surface_linear(vec3 srgb) {
	return mix(pow((srgb + vec3(0.055)) / 1.055, vec3(2.4)), srgb / 12.92, step(srgb, vec3(0.04045)));
}

float hash(highp vec2 p) {
	highp vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 field(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
		du.x * (b - a + k * u.y), du.y * (c - a + k * u.x));
}

void vertex() {
	world_ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	highp vec2 p = world_ground;
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	highp vec2 q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	vec3 mineral = field(q * 0.031 + vec2(13.1, 7.4));
	vec3 drift = field(p * 0.17 + mineral.x * 1.7);
	vec3 grain = field(p * 7.0);
	float grain_lod = 1.0 - smoothstep(0.025, 0.075, footprint);

	// Match desert_surface.gdshader at zero pavement weight: same world position,
	// palette, wind phase and normals. Sand is continuous across every chunk.
	vec3 sand = mix(surface_linear(vec3(0.49, 0.36, 0.22)), surface_linear(vec3(0.70, 0.585, 0.405)), smoothstep(0.12, 0.88, mineral.x));
	sand *= mix(vec3(1.0), sand_tint.rgb / surface_linear(vec3(0.725, 0.627, 0.475)), 0.22);
	highp float phase = dot(p, vec2(1.15, 0.43)) + drift.x * 3.5;
	float ripple_lod = 1.0 - smoothstep(0.3, 1.1, footprint);
	sand *= 0.91 + drift.x * 0.18 + sin(phase) * ripple_lod * 0.055;
	sand += (grain.x - 0.5) * 0.014 * grain_lod;
	vec2 sand_slope = cos(phase) * vec2(1.15, 0.43) * 0.12 * ripple_lod + drift.yz * 0.13;
	sand_slope += grain.yz * 0.024 * grain_lod;

	// Rounded corners plus several scales of windblown ingress; the rectangular
	// support terminates only where this shader is already identical to sand.
	vec2 edge = abs(p - court_center) - court_half_size + vec2(9.0);
	float inset = 9.0 - length(max(edge, vec2(0.0))) - min(max(edge.x, edge.y), 0.0);
	float erosion = field(p * 0.075 + vec2(27.4, 9.2)).x;
	float ingress = 1.2 + erosion * 5.5 + drift.x * 2.0;
	float paved = smoothstep(0.4, 6.0, inset - ingress);

	// Warm, dry aggregate: large areas vary gently while near-camera grit fades
	// below pixel size. Dust settles in low patches instead of a flat colour fill.
	vec3 old_asphalt = mix(surface_linear(vec3(0.245, 0.238, 0.222)), surface_linear(vec3(0.35, 0.326, 0.285)), mineral.x);
	float dust = 0.12 + 0.20 * smoothstep(0.34, 0.78, drift.x);
	vec3 pavement = mix(old_asphalt, sand * 0.73, dust);
	pavement += (grain.x - 0.5) * 0.012 * grain_lod;
	float aggregate_lod = 1.0 - smoothstep(0.10, 0.38, footprint);
	vec3 aggregate = field(p * 2.6 + vec2(2.3, 8.4));
	pavement *= 1.0 + (aggregate.x - 0.5) * 0.12 * aggregate_lod;
	float fissure = abs(drift.x - 0.49);
	float aa = max(fwidth(fissure), 0.002);
	float cracks = (1.0 - smoothstep(0.002, 0.006 + aa, fissure)) * smoothstep(0.54, 0.78, mineral.x);
	pavement *= 1.0 - cracks * 0.20;

	// Two faded, broken wheel arcs in the open manoeuvring apron; no extra
	// transparent layer, geometry, per-frame script or change to tire physics.
	vec2 turn = p - (court_center + vec2(-19.0, -2.0));
	float radial = length(turn);
	float wheel_distance = min(abs(radial - 7.0), abs(radial - 8.35));
	float wheel_aa = max(fwidth(radial), 0.03);
	float tyres = (1.0 - smoothstep(0.065, 0.17 + wheel_aa, wheel_distance));
	tyres *= smoothstep(-2.0, 1.5, turn.y) * smoothstep(0.18, 0.6, drift.x);
	pavement *= 1.0 - tyres * 0.20;

	vec2 paved_slope = grain.yz * 0.016 * grain_lod + aggregate.yz * 0.006 * aggregate_lod;
	vec2 slope = mix(sand_slope, paved_slope, paved);
	ALBEDO = mix(sand, pavement, paved);
	if (parking_paint) {
		float ink = smoothstep(0.35, 0.85, paved) * (0.56 + aggregate.x * 0.18);
		ALBEDO = mix(ALBEDO, surface_linear(vec3(0.785, 0.749, 0.651)), ink);
	}
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(-slope.x, 0.0, -slope.y, 0.0)).xyz);
	ROUGHNESS = mix(0.98, 0.94, paved);
	SPECULAR = 0.5;
}
