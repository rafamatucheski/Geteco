shader_type canvas_item;
render_mode unshaded;

// Driven by the menu so reduced motion freezes every atmospheric layer.
uniform float atmosphere_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float ellipse(vec2 uv, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.85, 1.05, length((uv - center) / radius));
}

void fragment() {
	vec2 uv = UV;
	float t = atmosphere_time;
	vec4 original = texture(TEXTURE, uv);
	// Exposed harbour only: stay behind the car's diagonal bonnet/window edge,
	// and exclude the foreground mooring post and wing mirror.
	float water = smoothstep(0.296, 0.302, uv.x)
		* smoothstep(0.430, 0.442, uv.y)
		* (1.0 - smoothstep(0.548, 0.556, uv.y))
		* (1.0 - smoothstep(0.780, 0.790, uv.x + uv.y * 0.79));
	water *= 1.0 - ellipse(uv, vec2(0.393, 0.522), vec2(0.023, 0.031));
	water *= 1.0 - ellipse(uv, vec2(0.309, 0.543), vec2(0.012, 0.030));
	float wave = sin(uv.y * 420.0 - t * 1.45 + sin(uv.x * 65.0 - t * 0.5));
	float ripple = sin(uv.y * 810.0 - t * 2.1 + uv.x * 95.0);
	vec2 offset = vec2(wave * 0.0019 + ripple * 0.00052,
		sin(uv.x * 145.0 - t * 0.8) * 0.00060) * water;
	vec4 c = texture(TEXTURE, uv + offset);
	float reflection = smoothstep(0.36, 0.80, original.r)
		* (1.0 - smoothstep(0.038, 0.102, abs(uv.x - 0.377)));
	c.rgb += vec3(1.0, 0.60, 0.25) * water * reflection
		* (wave * 0.032 + ripple * 0.018);

	// Low wisps drift left to right. Sky windows keep the painted logo,
	// cranes, hills, palm and Dante completely outside the animated layer.
	float sky_left = smoothstep(0.446, 0.476, uv.x)
		* (1.0 - smoothstep(0.608, 0.636, uv.x))
		* (1.0 - smoothstep(0.235, 0.267, uv.y));
	float sky_right = smoothstep(0.736, 0.759, uv.x)
		* (1.0 - smoothstep(0.843, 0.867, uv.x))
		* (1.0 - smoothstep(0.105, 0.137, uv.y));
	float sky = max(sky_left, sky_right);
	sky *= smoothstep(0.22, 0.48, original.r);
	sky *= 1.0 - ellipse(uv, vec2(0.558, 0.276), vec2(0.038, 0.063));
	if (sky > 0.001) {
		vec2 wind = vec2(uv.x - t * 0.0028, uv.y);
		float clouds = noise(wind * vec2(17.0, 48.0)) * 0.60;
		clouds += noise(wind * vec2(34.0, 96.0)) * 0.27;
		clouds += noise(wind * vec2(68.0, 192.0)) * 0.13;
		float veil = smoothstep(0.43, 0.72, clouds) * sky;
		c.rgb = mix(c.rgb, vec3(0.54, 0.34, 0.30), veil * 0.22);
	}
	COLOR = c;
}
