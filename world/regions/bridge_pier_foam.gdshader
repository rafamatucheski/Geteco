shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;

// Espuma onde a água bate num pilar: borda colada no concreto que pulsa com a
// marola, e um rastro que se desfaz rio abaixo. O quad é centrado no pilar;
// `half_size` é a meia-largura do pilar em metros e `reach` o alcance da espuma.
uniform vec2 half_size = vec2(0.95, 0.95);
uniform float reach = 1.8;
uniform vec2 current = vec2(0.6, 0.35);
uniform vec3 foam_color : source_color = vec3(0.78, 0.88, 0.88);
varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Distância até a face do pilar (SDF de retângulo).
	vec2 q = abs(local) - half_size;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	if (d < 0.0) discard;
	vec2 flow = normalize(current);
	// A espuma se estica no sentido da corrente e encurta contra ela.
	float downstream = dot(normalize(local + 1e-4), flow);
	float stretch = mix(0.55, 1.6, downstream * 0.5 + 0.5);
	float t = d / (reach * stretch);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.7 - d * 5.0 + noise(local * 1.3) * 3.0);
	float contact = (1.0 - smoothstep(0.0, 0.18, d)) * mix(0.6, 1.0, pulse);
	vec2 drift = local - flow * TIME * 0.6;
	float bubbles = smoothstep(0.62, 0.9, noise(drift * 2.4)) * (1.0 - smoothstep(0.1, 1.0, t));
	float lace = smoothstep(0.55, 0.75, noise(drift * 1.4 + 7.0)) * (1.0 - smoothstep(0.2, 1.0, t)) * 0.3;
	float foam = clamp(contact * 0.8 + bubbles * 0.45 + lace, 0.0, 1.0);
	if (foam < 0.02) discard;
	ALBEDO = foam_color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
	ALPHA = foam * 0.65;
}
