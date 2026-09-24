shader_type spatial;
render_mode cull_disabled, depth_draw_never;

float shore_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(fract(sin(i * 127.1) * 43758.5453), fract(sin((i + 1.0) * 127.1) * 43758.5453), f);
}

// UV.x is metres away from the actual quay/hull; UV.y is distance along it.
void fragment() {
	float d = UV.x;
	float along = UV.y;
	float phase = TIME * 0.72 + sin(along * 0.12) * 0.3;
	float cycle = fract(phase / 6.2831853);
	// First half approaches the wall, second half returns and dissipates.
	float front = 0.10 + 1.35 * abs(cycle * 2.0 - 1.0);
	float returning = smoothstep(0.49, 0.56, cycle);
	float width = mix(0.07, 0.12, returning) * mix(0.65, 1.3, shore_noise(along * 1.8));
	float distortion = (shore_noise(along * 1.3 + TIME * 0.1) - 0.5) * 0.17;
	float crest = 1.0 - smoothstep(width * 0.3, width, abs(d - front + distortion));
	float fragments = smoothstep(0.24, 0.7, shore_noise(along * 2.4 + TIME * 0.08)) * mix(0.35, 1.0, shore_noise(along * 0.41));
	float impact = pow(max(0.0, sin(cycle * 3.14159265)), 8.0);
	float contact = (1.0 - smoothstep(0.04, 0.22, d)) * impact;
	float fade = 1.0 - smoothstep(0.9, 1.65, d);
	float foam = (crest * mix(0.21, 0.10, returning) + contact * 0.28) * fragments * fade;
	ALBEDO = vec3(0.63, 0.79, 0.75);
	ALPHA = foam;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}
