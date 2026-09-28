shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Tufo de capim de Mountain (MultiMesh por bloco de 16 m, MountainGrass3D).
// Usa a mesma cobertura de neve do chão (mountain_ground.gdshaderinc): onde o
// terreno pinta neve, o tufo encolhe a zero no vértice, sem descasar a borda.
// `origin` = canto do chunk de 64 m do bloco, como no terreno.
#include "res://world/regions/mountain_ground.gdshaderinc"

instance uniform vec2 origin = vec2(0.0);
uniform vec3 root_color : source_color = vec3(0.09, 0.12, 0.05);
uniform vec3 tip_color : source_color = vec3(0.30, 0.36, 0.15);
uniform vec3 dry_tip : source_color = vec3(0.42, 0.38, 0.20);
varying float tip;
varying float tint;

void vertex() {
	vec3 instance_world = MODEL_MATRIX[3].xyz;
	vec2 local = instance_world.xz - origin;
	vec2 p = ground_p(local, origin);
	float cover = ground_cover(p, ground_fine(local), ground_altitude_snow(instance_world.z)) * ground_mountain_weight(instance_world.xz);
	// Some na neve, e fica mais baixo perto da borda dela.
	float keep = 1.0 - smoothstep(0.25, 0.55, cover);
	tip = UV.y;
	tint = ground_hash(floor(local * 3.0));
	// Vento: balança mais na ponta, em rajadas que atravessam o campo.
	float gust = sin(TIME * 1.3 + instance_world.x * 0.21 + instance_world.z * 0.17) * 0.5 + 0.5;
	float sway = sin(TIME * 2.7 + instance_world.x * 0.9 + instance_world.z * 0.7) * (0.04 + gust * 0.08);
	VERTEX.x += sway * UV.y * UV.y;
	VERTEX.z += sway * 0.6 * UV.y * UV.y;
	VERTEX *= keep;
}

void fragment() {
	vec3 tip_mix = mix(tip_color, dry_tip, smoothstep(0.6, 1.0, tint));
	ALBEDO = mix(root_color, tip_mix, smoothstep(0.0, 1.0, tip)) * (0.85 + tint * 0.3);
	ROUGHNESS = 0.9;
	// Folha fina deixa passar luz: contraluz ilumina a ponta.
	BACKLIGHT = vec3(0.25, 0.3, 0.12) * tip;
}
