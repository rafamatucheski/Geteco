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

// ---------------------------------------------------------------------------
// Acabamento do chão da serra (18/10/2026). O jogador achou o terreno chapado: neve
// branca lisa sem grão nem relevo, asfalto encostando direto na neve, bordas das
// trilhas borradas pela máscara de 0,5 m. Tudo aqui é conta no mesmo passe opaco:
// nenhuma textura, nenhuma variante de shader nova (o uniform só escolhe o ramo).
// GETECO_MOUNTAIN_GROUND=0 põe 0 e o terreno volta ao desenho anterior (A/B).
// Sem fwidth/dFdx aqui: o capim inclui este arquivo no vertex; a pegada do pixel
// vem do fragment como argumento.
uniform float ground_finish = 1.0;

// Seixos salpicados (receita do chão do deserto): um disco por célula de 1/scale m,
// presença sorteada por `density`. x = cobertura com borda suavizada, y = tom.
// Célula reduzida ao período de 256 m: o padrão não emenda na volta de `p`.
vec2 ground_pebbles(vec2 p, float scale, float density, float footprint) {
	vec2 q = p * scale;
	vec2 cell = mod(floor(q), GROUND_PERIOD * scale);
	vec2 local = fract(q) - 0.5;
	vec2 jitter = vec2(ground_hash(cell + 3.1), ground_hash(cell + 9.7)) - 0.5;
	float radius = mix(0.12, 0.30, ground_hash(cell + 5.5));
	float present = step(ground_hash(cell + 17.3), density);
	float edge = length(local - jitter * 0.4);
	float aa = max(footprint * scale, 0.002);
	return vec2(present * (1.0 - smoothstep(radius - aa, radius + aa, edge)), ground_hash(cell + 23.9));
}

// Ondulações de vento na neve (~1,6 m, levemente diagonais), entortadas pelo ruído
// grosso. Frequências inteiras por período de 256 m, então continuam sem emenda.
// x = altura (-1..1), y = derivada ao longo da fase (para o relevo).
const vec2 GROUND_RIPPLE_K = vec2(160.0, 48.0) * 6.2831853 / 256.0;
vec2 ground_ripple(vec2 p, float warp) {
	float phase = dot(p, GROUND_RIPPLE_K) + warp;
	return vec2(sin(phase), cos(phase));
}

// Acabamento de superfície antes das trilhas: neve com ondulação, sombra fria nos
// vales do vento e grão; chão exposto e rocha com seixos; estratos na encosta.
// Devolve a cor; `slope` acumula a inclinação do relevo procedural (m/m).
vec3 ground_finish_surface(vec3 color, vec2 p, float mid, float d1, float d2, float detail,
		float footprint, float cover, float cliff, float height, inout vec2 slope) {
	float snow_mask = smoothstep(0.55, 0.9, cover) * (1.0 - cliff);
	// Longe a ondulação vira média (não cintila); perto ela aparece inteira.
	float ripple_lod = 1.0 - smoothstep(0.05, 0.35, footprint);
	// Só em manchas (o vento não penteia o campo inteiro) e bem entortada: de cima,
	// faixas regulares liam como veludo cotelê.
	float ripple_patch = smoothstep(0.42, 0.70, mid + (d1 - 0.5) * 0.2);
	vec2 ripple = ground_ripple(p, mid * 16.0 + d1 * 3.0);
	float crest = ripple.x * (0.4 + d2 * 0.6) * ripple_patch;
	// Neve: vales do vento levemente azulados e mais escuros, cristas mais claras.
	vec3 cold = color * vec3(0.84, 0.89, 0.98);
	color = mix(color, cold, snow_mask * smoothstep(0.35, 0.75, mid) * 0.55);
	color *= 1.0 + crest * 0.045 * ripple_lod * snow_mask;
	color *= 1.0 + (d2 - 0.5) * 0.06 * detail * snow_mask;
	slope += GROUND_RIPPLE_K * ripple.y * (0.4 + d2 * 0.6) * ripple_patch * 0.022 * ripple_lod * snow_mask;
	// Chão exposto (capim, terra, rocha): seixos escuros e claros, mais densos na rocha.
	// Só chão descoberto de fato: na neve rala o seixo virava bolinha cinza no branco.
	float bare = 1.0 - smoothstep(0.25, 0.55, cover);
	float pebble_lod = 1.0 - smoothstep(0.03, 0.09, footprint);
	vec2 pebble = ground_pebbles(p, 2.6, mix(0.10, 0.42, max(cliff, smoothstep(0.4, 0.8, d1))), footprint);
	vec3 stone = pebble.y < 0.6 ? color * vec3(0.55, 0.55, 0.57) : color * vec3(1.18, 1.16, 1.12);
	color = mix(color, stone, pebble.x * pebble_lod * bare);
	// Estratos na encosta: faixas de altura quebradas pelo ruído, só onde há rocha.
	float strata = sin(height * 4.2 + mid * 5.0 + d1 * 1.6);
	color *= 1.0 + strata * 0.07 * cliff;
	return color;
}

// Trilhas e acostamentos (máscara de união das estradas): borda recortada pelo
// grão, leito de cascalho e lama de neve com seixos, e uma leira de neve tirada
// pela lâmina logo depois (mais clara e com relevo). `wear` sai já recortado.
vec3 ground_finish_trail(vec3 color, vec2 p, float trail, float mid, float d1, float fine,
		float footprint, float snow_amount, float cover, inout float wear, inout vec2 slope) {
	float ragged = trail + ((mid - 0.5) * 0.23 + (d1 - 0.5) * 0.30) * trail * (1.0 - trail) * 4.0;
	wear = smoothstep(0.30, 0.62, ragged);
	vec3 slush = mix(vec3(0.20, 0.18, 0.15), vec3(0.31, 0.31, 0.30), snow_amount * 0.6);
	slush *= 0.88 + mid * 0.16 + (fine - 0.5) * 0.12;
	// Só pedra escura e só no leito: seixo claro na borda virava bolinha cinza na neve.
	vec2 gravel = ground_pebbles(p + 37.0, 6.0, 0.40, footprint);
	float gravel_lod = 1.0 - smoothstep(0.02, 0.07, footprint);
	slush = mix(slush, slush * (0.55 + gravel.y * 0.2), gravel.x * gravel_lod * smoothstep(0.5, 0.9, wear));
	// Leira: faixa logo fora do leito, só onde o chão em volta é neve.
	float berm = smoothstep(0.06, 0.30, ragged) * (1.0 - smoothstep(0.30, 0.55, ragged)) * smoothstep(0.5, 0.85, cover);
	vec3 piled = mix(color, color * vec3(0.93, 0.93, 0.92), 0.5 + (fine - 0.5) * 0.6);
	color = mix(color, piled, berm);
	slope += vec2(d1 - 0.5, fine - 0.5) * 0.35 * berm;
	return mix(color, slush, wear * 0.92);
}
