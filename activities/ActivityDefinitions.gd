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
			"start":Vector2(1100,2200),"phone":Vector2(1052,2332),"phone_yaw":PI,
			"checkpoints":[Vector2(2200,2130),Vector2(2270,1250),Vector2(3000,1320),Vector2(2930,2200)],
			"reward":400,"best_time_bonus":200},
		"harbor_foundry": {"id":"harbor_foundry","name":"CIRCUITO FOUNDRY","length_label":"MÉDIA",
			"start":Vector2(400,1050),"phone":Vector2(268,1002),"phone_yaw":PI/2,
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
		{"id":"mountain_expedition_camera","region":"mountain","place":"mountain_mystery_cave","point":Vector3(4.6,0,-2.7)}] + vicente_letters()

## Cartas de Vicente (20/10/2026). Harbor e serra em coordenadas de mundo (a ponte, de x ~500 em
## diante, já é a região da serra), presas ao chão pelo raio
## do pickup; as do deserto ficam dentro de cômodos e da caverna, com teto, então vão com a altura
## do piso ("fixed": o raio de 12 m pararia no telhado).
static func vicente_letters() -> Array:
	var roadside := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
	var whisper := Vector2(-360, -1010)
	var cave := Vector3(whisper.x, 0, whisper.y) + Basis(Vector3.UP, 1.8) * Vector3(0, .05, -3.6)
	return [
		# Passeio do cais, entre os guindastes: fora da pista da ponte de Foundry.
		{"id":"vicente_letter_01","region":"harbor","place":"","point":Vector3(197,0,94)},
		# Lateral da fachada, fora da vaga do M8 e da passagem em frente ao portão.
		{"id":"vicente_letter_02","region":"harbor","place":"","point":Vector3(161,0,108)},
		{"id":"vicente_letter_03","region":"harbor","place":"","point":Vector3(322,0,-58)},
		# Passeio sul da ponte, entre o asfalto e o guarda-corpo (piso a 0,07 m).
		{"id":"vicente_letter_04","region":"mountain","place":"","point":Vector3(520,0,-278.9)},
		# Clareira diante da cabana; a posição anterior ficava perdida atrás dela.
		{"id":"vicente_letter_05","region":"mountain","place":"","point":Vector3(747,0,-351.5)},
		# Passeio diante do terminal da vila, em vez do terreno entre duas pistas.
		{"id":"vicente_letter_06","region":"mountain","place":"","point":Vector3(732.375,0,-409.2)},
		{"id":"vicente_letter_07","region":"desert","place":"","point":cave,"fixed":true},
		# Piso livre ao pé da cama do quarto 1, sem intersectar cama, cômoda ou cadeira.
		{"id":"vicente_letter_08","region":"desert","place":"","point":roadside.at(roadside.site("motel"), Vector3(-13.4, .15, -3.3)),"fixed":true},
		{"id":"vicente_letter_09","region":"desert","place":"","point":roadside.at(roadside.site("chapel"), Vector3(0, .15, -5.2)),"fixed":true},
		{"id":"vicente_letter_10","region":"desert","place":"","point":roadside.at(roadside.site("grandstand"), Vector3(19.5, .15, -.4)),"fixed":true}]
