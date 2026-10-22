shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Porto vivido: broad snow drifts, slate slopes and packed authored trails.
// Existing opaque terrain owns every finish, without extra planes or samples.
// Periodic local coordinates preserve precision and continuity at chunk borders.
#include "res://world/regions/mountain_ground.gdshaderinc"
#include "res://world/editing/terrain_paint.gdshaderinc"

instance uniform vec2 origin = vec2(0.0);
uniform sampler2D trail_mask : filter_linear, repeat_disable;
uniform vec3 earth_dark : source_color = vec3(0.23, 0.20, 0.15);
uniform vec3 grass : source_color = vec3(0.25, 0.31, 0.20);
uniform vec3 rock : source_color = vec3(0.38, 0.42, 0.42);
uniform vec3 snow_shade : source_color = vec3(0.65, 0.69, 0.70);
uniform vec3 snow_lit : source_color = vec3(0.88, 0.87, 0.83);

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
	// A altitude por fragmento evita a borda triangular da cor interpolada
	// entre os vértices de 4 m do terreno.
	float snow_amount = ground_altitude_snow(local_xz.y + origin.y);
	float macro = ground_fbm(p, 32.0);
	float mid = ground_fbm(p + 91.0, 8.0);
	float fine = ground_fine(local_xz);
	// Fine grain fades with footprint instead of sparkling at gameplay zoom.
	float detail = 1.0 - smoothstep(0.06, 0.34, max(length(dFdx(local_xz)), length(dFdy(local_xz))));
	float d1 = ground_noise(local_xz * 3.0, 192.0);
	float d2 = ground_noise(local_xz * 8.0, 512.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float vegetation = smoothstep(0.28, 0.72, macro * 0.65 + mid * 0.35);
	vec3 ground = mix(earth_dark, grass, vegetation * (1.0 - snow_amount));
	ground *= 0.90 + macro * 0.20;
	ground *= 1.0 + ((d1 - 0.5) * 0.10 + (d2 - 0.5) * 0.04) * detail;
	float cover = ground_cover_fields(macro, mid, fine, snow_amount) * ground_mountain_weight(local_xz + origin);
	// Broad shaded hollows replace blue speckle and all-over straw.
	vec3 snow = mix(snow_shade, snow_lit, smoothstep(0.05, 0.95, macro));
	snow *= 1.0 + (fine - 0.5) * 0.045 * detail;
	float rim = smoothstep(0.12, 0.42, cover) * (1.0 - smoothstep(0.58, 0.94, cover));
	snow = mix(snow, mix(snow, earth_dark, 0.28), rim * 0.65);
	vec3 color = mix(ground, snow, cover);
	// Exposed slate follows the actual slope.
	float cliff = smoothstep(0.10, 0.30, slope + (mid - 0.5) * 0.08);
	color = mix(color, rock * (0.88 + mid * 0.20 + (d1 - 0.5) * 0.05 * detail), cliff);
	// Acabamento da serra (mountain_ground.gdshaderinc). A pegada do pixel em metros
	// decide quanto grão aparece; o relevo vai direto na normal (a malha não tem tangente).
	float footprint = max(length(dFdx(local_xz)), length(dFdy(local_xz)));
	vec2 finish_slope = vec2(0.0);
	if (ground_finish > 0.5) {
		color = ground_finish_surface(color, p, mid, d1, d2, detail, footprint, cover, cliff, height, finish_slope);
	}
	// Encosta da bacia dos lagos: margem úmida acima da linha d'água (-0,2) e lama
	// plena logo abaixo. Bem mais escura que o capim: a luz de inverno clareia ~2,5x.
	// (smoothstep sempre com limites em ordem crescente: invertidos, o GLSL não
	// define o resultado.)
	float wet = 1.0 - smoothstep(-0.3, 0.02, height + (fine - 0.5) * 0.06);
	vec3 mud = mix(vec3(0.085, 0.066, 0.045), vec3(0.05, 0.045, 0.035), smoothstep(0.1, 0.4, -height));
	color = mix(color, mud * (0.94 + (d1 - 0.5) * 0.08 * detail), wet * 0.92);
	// The trail is part of this opaque surface, with one maximum-union mask.
	// Pixel centers include both chunk borders, so adjacent chunks sample identically.
	float trail = texture(trail_mask, (local_xz * 2.0 + 0.5) / 129.0).r;
	float wear = smoothstep(0.03, 0.92, trail + (mid - 0.5) * 0.23 * trail);
	vec3 packed = mix(vec3(0.27,0.23,0.18), vec3(0.48,0.48,0.44), snow_amount * 0.65);
	packed *= 0.94 + mid * 0.10 + (d1 - 0.5) * 0.08 * detail;
	if (ground_finish > 0.5) {
		color = ground_finish_trail(color, p, trail, mid, d1, fine, footprint, snow_amount, cover, wear, finish_slope);
	} else {
		color = mix(color, packed, wear * 0.88);
	}
	vec4 editor_finish = editor_terrain_finish(color, local_xz + origin);
	ALBEDO = editor_finish.rgb;
	// Reuse fine + two offset samples instead of nine for the normal map.
	float e = 0.1;
	float h0 = fine;
	float hx = ground_noise((local_xz + vec2(e, 0.0)) * 1.5, 96.0);
	float hz = ground_noise((local_xz + vec2(0.0, e)) * 1.5, 96.0);
	vec2 bump = vec2(hx - h0, hz - h0) / e * 0.035 * detail;
	NORMAL_MAP = vec3(0.5 - bump.x, 0.5 - bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(-finish_slope.x, 0.0, -finish_slope.y, 0.0)).xyz);
	float snowy = cover * (1.0 - cliff) * (1.0 - wear * 0.8);
	ROUGHNESS = mix(mix(0.96, 0.88, snowy), 0.55, wet);
	ROUGHNESS = mix(ROUGHNESS,0.95,editor_finish.a);
	SPECULAR = mix(0.15, 0.20, snowy);
	EMISSION = vec3(0.0);
}
