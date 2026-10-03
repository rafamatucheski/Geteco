extends RefCounted
const ID := "digo_amarok_2014"
static func spec() -> Dictionary:
	return {"id":ID,"label":"Amarok 2014 Stage 2 · Digo","scene":"res://gameplay/digo/DigoAmarokModel.tscn",
		"colors":["f0f1efff"],"bounds_size":[2.12,1.86,5.22],"bounds_center":[0,.93,0],
		"durability":350,"mass":2.0,"max_speed":660.0,"acceleration":1700.0,"braking":1550.0,
		"turn_speed":2.6,"drift_factor":.88,"drivetrain":"4x4","engine_family":"diesel","engine_pitch":.84,
		"turbo":true,"turbo_audio":false,"tuning_stage":2,"owner":"digo","year":2014,"roof_prop":"none"}
