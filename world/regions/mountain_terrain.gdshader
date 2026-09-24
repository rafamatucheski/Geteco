shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Chão de Mountain. Antes era só a cor do vértice (a cada 4 m) e, com a luz de
// inverno, lia como uma placa creme lisa (captura de 2026-09-24). Aqui a cor do
// vértice vira base e ganha: variação em várias escalas, terra/capim aparecendo
// pela neve, rocha nas encostas, azul frio nos baixios, lama na beira dos lagos e
// cintilado na neve. Ruído e cobertura de neve vêm de mountain_ground.gdshaderinc,
// o mesmo que o capim 3D usa.
//
// `origin` é o canto do chunk de 64 m, por instância: no renderizador Mobile a
// coordenada de mundo (x > 600 m) perde precisão no fragmento e o ruído vira
// blocos, como aconteceu no mar.
#include "res://world/regions/mountain_ground.gdshaderinc"

instance uniform vec2 origin = vec2(0.0);
uniform vec3 earth_dark : source_color = vec3(0.17, 0.19, 0.13);
uniform vec3 grass : source_color = vec3(0.24, 0.31, 0.18);
uniform vec3 rock : source_color = vec3(0.42, 0.43, 0.43);
uniform vec3 snow_shade : source_color = vec3(0.60, 0.70, 0.84);
uniform vec3 snow_lit : source_color = vec3(0.94, 0.95, 0.96);

varying vec2 local_xz;
varying vec3 world_normal;
varying float height;

void vertex() {
	local_xz = VERTEX.xz - origin;
	world_normal = NORMAL;
	height = VERTEX.y;
}

void fragment() {
	vec2 p = ground_p(local_xz, origin);
	vec3 base = COLOR.rgb;
	float snow_amount = smoothstep(0.55, 0.8, dot(base, vec3(0.333)));
	float macro = ground_fbm(p, 32.0);
	float mid = ground_fbm(p + 91.0, 8.0);
	float fine = ground_fine(local_xz);
	// Detalhe de perto (0,2 a 0,5 m): sem ele o chão lia como imagem esticada
	// (relato do jogador em 2026-09-24). Períodos múltiplos de 64 m, sem emenda.
	float d1 = ground_noise(local_xz * 3.0, 192.0);
	float d2 = ground_noise(local_xz * 8.0, 512.0);
	float d3 = ground_noise(local_xz * vec2(18.0, 5.0), 1152.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	// Chão sem neve: terra e capim em manchas, com o tom de altura do vértice.
	vec3 ground = mix(earth_dark, grass, smoothstep(0.45, 0.55, mid + (d1 - 0.5) * 0.25));
	ground = mix(ground, base, 0.2);
	ground *= 0.85 + macro * 0.3;
	// Tufos e terra granulada: manchas pequenas escuras/claras e fios de capim.
	ground *= 0.72 + d1 * 0.28 + d2 * 0.22 + d3 * 0.12;
	ground = mix(ground, grass * 1.25, smoothstep(0.72, 0.9, d2) * 0.35);
	float cover = ground_cover(p, fine, snow_amount);
	// Luz de inverno estoura a neve para quase branco; o contraste vem de manchas de
	// sombra fria largas e de ondulações de vento (sastrugi) numa direção só.
	vec3 snow = mix(snow_shade, snow_lit, smoothstep(0.3, 0.75, macro));
	vec2 wind = vec2(0.8, 0.6);
	float ripple = sin(dot(p, wind) * 2.4 + mid * 9.0) * 0.5 + 0.5;
	ripple = smoothstep(0.55, 1.0, ripple) * smoothstep(0.35, 0.65, ground_fbm(p + 37.0, 16.0));
	snow = mix(snow, snow_shade * 0.95, ripple * 0.45);
	// Baixios ficam em sombra fria.
	snow = mix(snow_shade * 0.92, snow, smoothstep(0.5, 4.0, height));
	// Crosta de neve: grão fino, bem mais sutil que no chão.
	snow *= 0.95 + fine * 0.04 + d2 * 0.04;
	// Borda da neve suja de terra, em vez de corte limpo sobre o capim.
	float rim = smoothstep(0.15, 0.45, cover) * (1.0 - smoothstep(0.55, 0.9, cover));
	snow = mix(snow, mix(snow, ground, 0.45), rim * d1);
	vec3 color = mix(ground, snow, cover);
	// Encosta íngreme: neve não para, aparece rocha.
	float cliff = smoothstep(0.12, 0.28, slope + (mid - 0.5) * 0.12);
	color = mix(color, rock * (0.8 + fine * 0.2 + d2 * 0.15), cliff);
	// Encosta da bacia dos lagos: margem úmida acima da linha d'água (-0,2) e lama
	// plena logo abaixo. Bem mais escura que o capim: a luz de inverno clareia ~2,5x.
	// (smoothstep sempre com limites em ordem crescente: invertidos, o GLSL não
	// define o resultado.)
	float wet = 1.0 - smoothstep(-0.3, 0.02, height + (fine - 0.5) * 0.06);
	vec3 mud = mix(vec3(0.085, 0.066, 0.045), vec3(0.05, 0.045, 0.035), smoothstep(0.1, 0.4, -height));
	color = mix(color, mud * (0.85 + d1 * 0.2 + d2 * 0.1), wet * 0.92);
	ALBEDO = color;
	// Relevo fino na iluminação, também com a camada de perto.
	float e = 0.1;
	float h0 = ground_noise(local_xz * 1.5, 96.0) + ground_noise(local_xz * 4.0, 256.0) * 0.5 + ground_noise(local_xz * 8.0, 512.0) * 0.25;
	float hx = ground_noise((local_xz + vec2(e, 0.0)) * 1.5, 96.0) + ground_noise((local_xz + vec2(e, 0.0)) * 4.0, 256.0) * 0.5 + ground_noise((local_xz + vec2(e, 0.0)) * 8.0, 512.0) * 0.25;
	float hz = ground_noise((local_xz + vec2(0.0, e)) * 1.5, 96.0) + ground_noise((local_xz + vec2(0.0, e)) * 4.0, 256.0) * 0.5 + ground_noise((local_xz + vec2(0.0, e)) * 8.0, 512.0) * 0.25;
	vec2 bump = vec2(hx - h0, hz - h0) / e * 0.07;
	NORMAL_MAP = vec3(0.5 - bump.x, 0.5 - bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	float snowy = cover * (1.0 - cliff);
	ROUGHNESS = mix(mix(0.95, 0.6, snowy), 0.35, wet);
	SPECULAR = mix(0.2, 0.4, snowy);
	// Cintilado de cristal de gelo: pontos minúsculos, só na neve.
	float glitter = step(0.985, ground_hash(floor(local_xz * 9.0))) * snowy;
	EMISSION = vec3(glitter * 0.12);
}
