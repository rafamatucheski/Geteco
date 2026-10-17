shader_type spatial;
render_mode specular_schlick_ggx;

// Quay pilot only. Same opaque pass, mesh and lighting as the existing ocean.
// The outer 24 m blend back into that ocean, including its wave phases.
uniform vec3 shallow_color : source_color = vec3(0.055, 0.36, 0.37);
uniform vec3 deep_color : source_color = vec3(0.035, 0.14, 0.22);
uniform vec3 natural_shallow_color : source_color = vec3(0.045, 0.255, 0.265);
uniform vec3 natural_deep_color : source_color = vec3(0.027, 0.125, 0.175);
uniform vec3 sky_color : source_color = vec3(0.50, 0.66, 0.76);
uniform float shadow_strength = 0.45;
varying vec2 local_xz;
varying float pilot_weight;
const float PERIOD = 256.0;

float pilot(vec2 p) {
	vec2 edge = min(p - vec2(128.0), vec2(320.0) - p);
	return smoothstep(0.0, 24.0, min(edge.x, edge.y));
}

void vertex() {
	local_xz = UV;
	pilot_weight = pilot(VERTEX.xz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p, float cells) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(mod(i, cells)), hash(mod(i + vec2(1.0, 0.0), cells)), u.x),
		mix(hash(mod(i + vec2(0.0, 1.0), cells)), hash(mod(i + vec2(1.0, 1.0), cells)), u.x), u.y);
}

vec3 wave(vec2 p, vec2 cycles, float amp, float speed, float t) {
	vec2 k = cycles * 6.2831853 / PERIOD;
	float phase = dot(p, k) - t * speed * length(k);
	return vec3(sin(phase) * amp, k * cos(phase) * amp);
}

vec3 ocean(vec2 p, float t, float weight, float shore) {
	// A dominant swell with a softer cross swell, instead of equally strong stripes.
	// Sheltered edges are calmer. No simulation or extra texture/pass is needed.
	float sheltered = mix(0.68, 1.0, smoothstep(1.0, 18.0, shore));
	float strength = mix(1.0, sheltered, weight);
	vec3 h = wave(p, vec2(10.0, 26.0), mix(0.09, 0.075, weight), 1.2, t);
	h += wave(p, vec2(-14.0, 36.0), mix(0.06, 0.026, weight), 1.0, t);
	h += wave(p, vec2(84.0, -26.0), mix(0.022, 0.012, weight), 0.7, t);
	h += wave(p, vec2(-76.0, -95.0), mix(0.016, 0.007, weight), 0.6, t);
	vec2 warp = vec2(noise(p * 0.25 + t * 0.05, 64.0), noise(p * 0.25 + 17.0 - t * 0.04, 64.0)) - 0.5;
	vec2 q = p + warp * 2.0;
	// Fade subpixel detail at gameplay zoom to avoid crawling highlights.
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float fine = mix(1.0, 1.0 - smoothstep(0.16, 0.55, footprint), weight);
	h += wave(q, vec2(55.0, 172.0), 0.006 * fine, 0.45, t);
	h += wave(q, vec2(215.0, -86.0), 0.005 * fine, 0.4, t);
	return h * strength;
}

void fragment() {
	float weight = pilot_weight;
	float shore = COLOR.r * 24.0;
	vec3 h = ocean(local_xz, TIME, weight, shore);
	vec2 slope = h.yz;
	float depth_mix = smoothstep(0.0, 22.0, shore);
	vec3 shallow = mix(shallow_color, natural_shallow_color, weight);
	vec3 deep = mix(deep_color, natural_deep_color, weight);
	vec3 water = mix(shallow, deep, depth_mix);
	// Water volume is mostly stable; moving normal highlights describe the waves.
	water *= 1.0 + clamp(h.x * mix(2.2, 0.95, weight), -0.3, 0.3);
	float facing = clamp(-slope.y * 5.0 + length(slope) * 1.5, 0.0, 1.0);
	float breakup = noise(local_xz * 0.75 + TIME * 0.1, 192.0);
	float streak = smoothstep(mix(0.25, 0.12, weight), mix(0.9, 0.7, weight), facing);
	streak *= mix(0.6, 1.0, breakup);
	ALBEDO = mix(water, sky_color * mix(0.6, 0.46, weight), streak * mix(0.24, 0.32, weight));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x, 1.0, -slope.y)), 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float shade = LIGHT_IS_DIRECTIONAL ? mix(1.0 - shadow_strength, 1.0, ATTENUATION) : ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * max(dot(NORMAL, LIGHT), 0.0) * shade * 0.9 / 3.14159265;
	vec3 half_vector = normalize(LIGHT + VIEW);
	float alignment = max(dot(NORMAL, half_vector), 0.0);
	// Wider, dimmer highlights remain legible without the old sharp sparkle.
	float glint = pow(alignment, mix(2600.0, 560.0, pilot_weight));
	SPECULAR_LIGHT += LIGHT_COLOR * min(glint, 0.5) * mix(0.22, 0.105, pilot_weight) * ATTENUATION;
}
