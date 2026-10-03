extends RefCounted
## Digo's personal two-door 1993 hatch. Independent of Vehicle to allow cold save restore.
const ID := "digo_gol_1993"
static func spec() -> Dictionary:
	return {"id": ID, "label": "Gol quadrado 1993 · Digo", "scene": "res://gameplay/digo/DigoGolModel.tscn",
		"colors": ["bcc2c4ff"], "bounds_size": [1.72, 1.43, 3.80], "bounds_center": [0, .715, 0],
		"durability": 240, "mass": .90, "max_speed": 640.0, "acceleration": 1250.0,
		"braking": 1350.0, "turn_speed": 3.05, "drift_factor": .84, "drivetrain": "fwd",
		"engine_family": "sport", "engine_pitch": 1.05, "turbo_audio": true, "roof_prop": "none",
		"owner": "digo", "year": 1993, "rim_inches": 15, "plate_color": "black", "turbo": true}
