// Millimetre-scale beads in surface metres. Each cell renews independently;
// the surface coordinates never scroll with TIME or with the vehicle.
float drop_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 rain_beads(vec2 p, float cells, float density, float rainfall, float slope, float t, float seed) {
	vec2 q = p * cells;
	vec2 id = floor(q);
	// Changing rain must not multiply the accumulated clock and jump every bead.
	float phase = t * mix(0.09, 0.22, drop_hash(id + seed + 19.3)) + drop_hash(id + seed);
	float cycle = floor(phase);
	float life = fract(phase);
	float h = drop_hash(id + vec2(seed, cycle * 7.13));
	float h2 = drop_hash(id * 1.73 + vec2(cycle * 3.7, seed + 5.1));
	float alive = smoothstep(h - 0.035, h + 0.035, density);
	alive *= smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.78, 1.0, life));
	float threshold = 0.7 - rainfall * 0.35;
	float run = smoothstep(0.48, 0.9, life) * smoothstep(threshold - 0.15, threshold + 0.15, h2) * slope;
	vec2 centre = (vec2(h, h2) - 0.5) * 0.42;
	centre.y -= run * 0.27;
	vec2 d = fract(q) - 0.5 - centre;
	d.y /= 1.0 + run * 0.75;
	float radius = mix(0.075, 0.21, h2 * h2) * mix(0.55, 1.0, smoothstep(0.0, 0.65, life));
	float distance_to_drop = length(d);
	float pixel = max(length(fwidth(q)), 0.001);
	float mask = (1.0 - smoothstep(radius - pixel * 0.5, radius + pixel * 0.5, distance_to_drop)) * alive;
	// Subpixel beads merge into the wet finish instead of sparkling/aliasing.
	mask *= 1.0 - smoothstep(radius * 1.5, radius * 5.0, pixel);
	return vec3(mask, d / max(radius, 0.01) * mask);
}
