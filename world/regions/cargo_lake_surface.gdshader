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
uniform vec2 world_origin = vec2(0.0);
uniform float surface_kind = 0.0;
uniform vec3 lake_water_color : source_color = vec3(0.08,0.26,0.31);
uniform vec3 lake_frost_color : source_color = vec3(0.49,0.66,0.71);
uniform vec3 lake_ice_color : source_color = vec3(0.64,0.78,0.82);
varying vec2 surface_weight;
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
	local_xz = VERTEX.xz + world_origin - origin;
	surface_weight = UV2;
	world_normal = NORMAL;
	height = VERTEX.y;
}


// Fine static water grain; no coarse cloud layer or transparent screen pass.
vec3 cargo_water(vec2 q, float edge_distance) {
    float fine = ground_fine(q);
    float grain = ground_noise(q * 3.0,192.0);
    float ripple = sin(dot(q,vec2(0.85,0.35))*5.0 + ground_noise(q/2.0,32.0)*1.3);
    vec3 water = lake_water_color * (0.96 + ripple*0.025 + (grain-0.5)*0.06);
    float edge = 1.0 - smoothstep(0.0,0.32,edge_distance);
    float flecks = smoothstep(0.68,0.87,grain + (fine-0.5)*0.17);
    return mix(water,lake_frost_color,edge*flecks*0.35);
}

void fragment() {
    if (surface_kind < 0.5) {
        ALBEDO = cargo_water(local_xz,surface_weight.x*2.8);
        float ripple = cos(dot(local_xz,vec2(0.85,0.35))*5.0)*0.012;
        NORMAL_MAP = vec3(0.5+ripple,0.5+ripple*0.45,1.0);
        NORMAL_MAP_DEPTH = 1.0;
        ROUGHNESS = 0.52;
        SPECULAR = 0.08;
    } else if (surface_kind > 3.5) {
        float fine = ground_fine(local_xz);
        float grain = ground_noise(local_xz*4.0,256.0);
        float fracture = 1.0-smoothstep(0.015,0.045,abs(sin(local_xz.x*0.38+local_xz.y*0.17+ground_noise(local_xz/2.0,32.0)*1.8)));
        ALBEDO = lake_ice_color*(0.91+fine*0.07+grain*0.04);
        ALBEDO = mix(ALBEDO,lake_water_color,fracture*0.45);
        NORMAL_MAP = vec3(0.5+(grain-fine)*0.06,0.5+(fine-0.5)*0.06,1.0);
        NORMAL_MAP_DEPTH = 1.0;
        ROUGHNESS = 0.72;
        SPECULAR = 0.12;
    } else {

	vec2 p = ground_p(local_xz, origin);
	vec3 base = COLOR.rgb;
	// A altitude por fragmento evita a borda triangular da cor interpolada
	// entre os vértices de 4 m do terreno.
	float snow_amount = ground_altitude_snow(local_xz.y + origin.y);
	float macro = ground_fbm(p, 32.0);
	float mid = ground_fbm(p + 91.0, 8.0);
	float fine = ground_fine(local_xz);
	// Fine grain fades with footprint instead of sparkling at gameplay zoom.
	float detail = 1.0 - smoothstep(0.04, 0.22, max(length(dFdx(local_xz)), length(dFdy(local_xz))));
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
	color = mix(color, packed, wear * 0.88);
	ALBEDO = color;
	// Reuse fine + two offset samples instead of nine for the normal map.
	float e = 0.1;
	float h0 = fine;
	float hx = ground_noise((local_xz + vec2(e, 0.0)) * 1.5, 96.0);
	float hz = ground_noise((local_xz + vec2(0.0, e)) * 1.5, 96.0);
	vec2 bump = vec2(hx - h0, hz - h0) / e * 0.035 * detail;
	NORMAL_MAP = vec3(0.5 - bump.x, 0.5 - bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	float snowy = cover * (1.0 - cliff) * (1.0 - wear * 0.8);
	ROUGHNESS = mix(mix(0.96, 0.88, snowy), 0.55, wet);
	SPECULAR = mix(0.15, 0.20, snowy);
	EMISSION = vec3(0.0);

    // Outside the contact, retain Mountain's exact source-color palette,
    // grain, normal map, roughness, specular and existing authored trail mask.
    if (surface_kind < 1.5) {
        float distance = surface_weight.x * 2.0;
        float irregular = 0.05 + 0.12*ground_noise(local_xz*1.5,96.0);
        float contact = 1.0-smoothstep(0.0,irregular,distance);
        float sand = smoothstep(0.45,0.80,d1+(mid-0.5)*0.20);
        ALBEDO = mix(ALBEDO,mix(rock*0.52,lake_frost_color*0.60,fine),contact*sand*0.40);
    } else {
        // Blend to the surface underneath this boundary: land or open water.
        // Width varies with terrain grain instead of a uniform white band.
        float distance = surface_weight.x * (surface_kind < 2.5 ? 1.0 : 0.65);
        float width = 0.14 + 0.64*ground_noise(local_xz*1.1,70.4);
        float border = smoothstep(0.015,width,distance);
        float submerged = smoothstep(-0.025,0.025,surface_weight.y);
        vec3 below = mix(ALBEDO,cargo_water(local_xz,max(0.0,surface_weight.y)),submerged);
        vec3 dry = ALBEDO;
        if (surface_kind < 2.5) {
            float packed = smoothstep(0.44,0.78,ground_noise(local_xz*1.5,96.0)+(mid-0.5)*0.25);
            dry = mix(dry,earth_dark*(0.72+d1*0.18+d2*0.20),packed*border*0.38);
        } else {
            float exposed = smoothstep(0.50,0.77,mid+(d1-0.5)*0.22);
            dry = mix(dry,rock*(0.66+d1*0.12+d2*0.18),exposed*0.60);
        }
        ALBEDO = mix(below,dry,border);
        float water_weight = submerged*(1.0-border);
        ROUGHNESS = mix(ROUGHNESS,0.52,water_weight);
        SPECULAR = mix(SPECULAR,0.08,water_weight);
        NORMAL_MAP = mix(NORMAL_MAP,vec3(0.5,0.5,1.0),water_weight);
        EMISSION *= 1.0-water_weight;
    }
    }
}
