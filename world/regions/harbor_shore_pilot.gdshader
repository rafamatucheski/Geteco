shader_type spatial;
render_mode cull_disabled, depth_draw_never;

varying vec2 coast_position;
varying float pilot_weight;

void vertex() {
	coast_position = VERTEX.xz;
	vec2 edge = min(VERTEX.xz - vec2(128.0), vec2(320.0) - VERTEX.xz);
	pilot_weight = smoothstep(0.0, 24.0, min(edge.x, edge.y));
}

float shore_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(fract(sin(i * 127.1) * 43758.5453), fract(sin((i + 1.0) * 127.1) * 43758.5453), f);
}

void fragment() {
	float d = UV.x;
	float along = UV.y;
	float phase = TIME * 0.72 + sin(along * 0.12) * 0.3;
	float cycle = fract(phase / 6.2831853);
	float front = 0.10 + 1.35 * abs(cycle * 2.0 - 1.0);
	float returning = smoothstep(0.49, 0.56, cycle);
	float width = mix(0.07, 0.12, returning) * mix(0.65, 1.3, shore_noise(along * 1.8));
	float distortion = (shore_noise(along * 1.3 + TIME * 0.1) - 0.5) * 0.17;
	float crest = 1.0 - smoothstep(width * 0.3, width, abs(d - front + distortion));
	float fragments = smoothstep(0.24, 0.7, shore_noise(along * 2.4 + TIME * 0.08)) * mix(0.35, 1.0, shore_noise(along * 0.41));
	float impact = pow(max(0.0, sin(cycle * 3.14159265)), 8.0);
	float contact = (1.0 - smoothstep(0.04, 0.22, d)) * impact;
	float fade = 1.0 - smoothstep(0.9, 1.65, d);
	float original = (crest * mix(0.21, 0.10, returning) + contact * 0.28) * fragments * fade;

	// Soft arrivals in staggered patches, followed by dispersed retreating foam.
	// World position keeps phase continuous when the shore is split into chunks.
	float variation = shore_noise(dot(coast_position, vec2(0.083, 0.061)));
	float wash_phase = TIME * 0.72 + variation * 2.8;
	float wash = 0.5 + 0.5 * cos(wash_phase);
	float natural_front = 0.08 + 1.25 * wash;
	float retreat = smoothstep(-0.2, 0.35, -sin(wash_phase));
	float ragged = shore_noise(along * 3.2 + d * 5.0 - TIME * 0.12);
	float front_distance = d - natural_front + distortion;
	float pixel = max(fwidth(front_distance), 0.001);
	float band_width = mix(0.13, 0.22, retreat);
	float band = 1.0 - smoothstep(max(0.0, 0.035 - pixel), band_width + pixel, abs(front_distance));
	band *= band_width / (band_width + pixel);
	float broken = smoothstep(0.28, 0.73, ragged) * mix(0.35, 1.0, variation);
	float detail = 1.0 - smoothstep(0.12, 0.4, max(length(dFdx(coast_position)), length(dFdy(coast_position))));
	broken = mix(0.42 * mix(0.35, 1.0, variation), broken, detail);
	float touch = (1.0 - smoothstep(0.025, 0.19, d)) * pow(1.0 - wash, 3.0);
	float natural = (band * mix(0.28, 0.12, retreat) + touch * 0.34) * broken * fade;
	ALBEDO = mix(vec3(0.63, 0.79, 0.75), vec3(0.56, 0.71, 0.67), pilot_weight);
	ALPHA = mix(original, natural, pilot_weight);
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}
