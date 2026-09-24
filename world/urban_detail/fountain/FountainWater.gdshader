shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// Espelho d'água do chafariz: ondas que saem de onde a água cai (anel da cortina e
// centro do jato), transparência mais escura no fundo e brilho de reflexo.
uniform float radius = 3.2;
uniform float impact_radius = 1.3;
uniform vec3 deep : source_color = vec3(0.05, 0.22, 0.26);
uniform vec3 shallow : source_color = vec3(0.22, 0.46, 0.48);
uniform float wave_strength = 0.018;

varying vec2 local_xz;

float wave(vec2 p, float t) {
	float r = length(p);
	float from_ring = sin((abs(r - impact_radius)) * 11.0 - t * 5.0) * exp(-abs(r - impact_radius) * 0.9);
	float from_center = sin(r * 16.0 - t * 7.0) * exp(-r * 2.2);
	float chop = sin(p.x * 3.1 + t * 1.3) * sin(p.y * 2.7 - t * 1.1) * 0.35;
	return from_ring + from_center * 0.6 + chop;
}

void vertex() {
	local_xz = VERTEX.xz;
	VERTEX.y += wave(VERTEX.xz, TIME) * wave_strength;
}

void fragment() {
	float r = length(local_xz);
	if (r > radius) discard;
	float e = 0.04;
	float h = wave(local_xz, TIME);
	float hx = wave(local_xz + vec2(e, 0.0), TIME);
	float hz = wave(local_xz + vec2(0.0, e), TIME);
	vec2 slope = vec2(hx - h, hz - h) / e * wave_strength * 6.0;
	NORMAL_MAP = vec3(0.5 - slope.x, 0.5 - slope.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	float edge = smoothstep(radius * 0.55, radius, r);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, edge * 0.7 + fresnel * 0.4);
	// Espuma clara onde a água bate.
	float foam = exp(-pow((r - impact_radius) * 5.0, 2.0)) * (0.55 + 0.45 * sin(TIME * 9.0 + atan(local_xz.y, local_xz.x) * 14.0));
	ALBEDO = mix(ALBEDO, vec3(0.85, 0.93, 0.95), clamp(foam, 0.0, 1.0) * 0.55);
	ROUGHNESS = mix(0.04, 0.3, foam);
	SPECULAR = 0.9;
	ALPHA = mix(0.78, 0.9, fresnel);
}
