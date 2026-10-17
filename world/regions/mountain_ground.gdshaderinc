// Ruído e cobertura de neve do chão de Mountain, compartilhados pelo terreno
// (mountain_terrain.gdshader) e pelo capim 3D (mountain_grass.gdshader): o capim
// some exatamente onde o terreno pinta neve, sem descasar.
//
// Coordenadas: `local_xz` = metros dentro do chunk de 64 m (0..64); `p` = local +
// canto do chunk reduzido a 256 m. Tudo pequeno de propósito: no renderizador
// Mobile a coordenada de mundo (x > 600 m) perde precisão e o ruído vira blocos.

const float GROUND_PERIOD = 256.0;
uniform vec2 mountain_entry_x = vec2(559.375, 651.25);
uniform vec2 mountain_north_fade = vec2(-203.75, -128.75);

float ground_mountain_weight(vec2 world_xz) {
	return smoothstep(mountain_entry_x.x, mountain_entry_x.y, world_xz.x)
		* (1.0 - smoothstep(mountain_north_fade.x, mountain_north_fade.y, world_xz.y));
}

float ground_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ruído de valor periódico em `cells` células; `p` já em células.
float ground_noise(vec2 p, float cells) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ground_hash(mod(i, cells)), ground_hash(mod(i + vec2(1.0, 0.0), cells)), u.x),
		mix(ground_hash(mod(i + vec2(0.0, 1.0), cells)), ground_hash(mod(i + vec2(1.0, 1.0), cells)), u.x), u.y);
}

// Soma de oitavas; `scale` em metros por célula, período de 256 m.
float ground_fbm(vec2 p, float scale) {
	float cells = GROUND_PERIOD / scale;
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += ground_noise(p / scale, cells) * amp;
		scale *= 0.5;
		cells *= 2.0;
		amp *= 0.5;
	}
	return v / 0.875;
}

vec2 ground_p(vec2 local_xz, vec2 origin) {
	return local_xz + mod(origin, GROUND_PERIOD);
}

// Grão fino só na coordenada local; período de 64 m = um chunk, sem emenda.
float ground_fine(vec2 local_xz) {
	return ground_noise(local_xz * 1.5, 96.0);
}

// Shared terrain/grass coverage: broad wind-scoured pockets, not camouflage.
float ground_cover_fields(float macro, float mid, float fine, float snow_amount) {
	// A continuous snow field: sparse scoured edges, not repeating green islands.
	float drift = smoothstep(0.28, 0.64, macro * 0.70 + mid * 0.30);
	float cover = mix(0.78 + drift * 0.20, 0.99, snow_amount);
	float exposed = smoothstep(0.66, 0.82, macro * 0.35 + mid * 0.65 + (fine - 0.5) * 0.035);
	return cover * (1.0 - exposed * 0.46);
}

float ground_cover(vec2 p, float fine, float snow_amount) {
	return ground_cover_fields(ground_fbm(p, 32.0), ground_fbm(p + 91.0, 8.0), fine, snow_amount);
}

// Neve de altitude a partir de Z de mundo, como MountainTerrain3D pinta o vértice
// (neve plena acima de y_V1 = -1500, sem neve abaixo de -1200; offset de Mountain
// -4960 px) convertida na mesma curva de luminância que o terreno usa.
float ground_altitude_snow(float world_z) {
	float original_y = world_z * 16.0 + 4960.0;
	float snow = 1.0 - smoothstep(-1500.0, -1200.0, original_y);
	float luminance = mix(0.36, 0.85, snow);
	return smoothstep(0.55, 0.8, luminance);
}
