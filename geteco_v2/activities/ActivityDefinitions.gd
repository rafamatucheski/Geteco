extends RefCounted
const SCALE := 1.0/16.0
const MOUNTAIN_OFFSET := Vector2(4300,-4960)
const RACES := preload("res://data/catalogs/RaceCatalog.gd")
const DRIFT := preload("res://data/catalogs/DriftZoneCatalog.gd")
const HOMES := preload("res://data/catalogs/ResidenceCatalog.gd")
# RaceCatalog/DriftZoneCatalog are CityDemo legacy, not the live Harbor map.
static func races(region: String) -> Dictionary:
	if region == "legacy": return RACES.RACES
	if region != "harbor": return {}
	# Production V1: HarborGame._spawn_motorsport_weather. Keep its authored
	# street coordinates here; at() performs the sole pixels-to-metres conversion.
	return {
		"harbor_docks": {"id":"harbor_docks","name":"VOLTA DO PORTO","length_label":"CURTA",
			"start":Vector2(1100,2200),
			"checkpoints":[Vector2(2200,2130),Vector2(2270,1250),Vector2(3000,1320),Vector2(2930,2200)],
			"reward":400,"best_time_bonus":200},
		"harbor_foundry": {"id":"harbor_foundry","name":"CIRCUITO FOUNDRY","length_label":"MÉDIA",
			"start":Vector2(400,1050),
			"checkpoints":[Vector2(470,400),Vector2(2200,470),Vector2(2130,1250),Vector2(400,1180)],
			"reward":650,"best_time_bonus":300}}
static func drifts(region: String) -> Dictionary:
	if region == "legacy": return DRIFT.ZONES
	if region != "harbor": return {}
	return {
		"harbor_westgate": {"id":"harbor_westgate","name":"PÁTIO WESTGATE","pos":Vector2(750,1900),"radius":120.0,"reward_per_1000":150},
		"harbor_cold_storage": {"id":"harbor_cold_storage","name":"PÁTIO DOS ARMAZÉNS","pos":Vector2(2600,1050),"radius":130.0,"reward_per_1000":200}}
static func at(point: Vector2, region: String = "harbor") -> Vector3:
	if region == "mountain": point += MOUNTAIN_OFFSET
	return Vector3(point.x*SCALE,0,point.y*SCALE)
static func collectibles() -> Array:
	return [
		{"id":"harbor_memorial_letter","region":"harbor","place":"","point":at(Vector2(-650,1740)+Vector2(310,292))},
		{"id":"harbor_col_navio_01","region":"harbor","place":"","point":at(Vector2(3515,1545))},
		{"id":"harbor_col_cobras_01","region":"harbor","place":"","point":at(Vector2(7440,1035))},
		{"id":"harbor_col_oeste_01","region":"harbor","place":"","point":at(Vector2(555,932))},
		{"id":"harbor_col_leste_01","region":"harbor","place":"","point":at(Vector2(8480,1440))},
		{"id":"harbor_col_norte_01","region":"harbor","place":"","point":at(Vector2(1455,22))},
		{"id":"harbor_col_sul_01","region":"harbor","place":"","point":at(Vector2(2705,1768))},
		# Native model local positions, not projected coordinates re-scaled twice.
		{"id":"mountain_expedition_pack","region":"mountain","place":"","point":at(Vector2(6200,-320),"mountain")+Vector3(3.2,0,3.8)},
		{"id":"mountain_expedition_journal","region":"mountain","place":"mountain_mystery_cave","point":Vector3(-3.4,0,-.5)},
		{"id":"mountain_expedition_camera","region":"mountain","place":"mountain_mystery_cave","point":Vector3(4.6,0,-2.7)}]
