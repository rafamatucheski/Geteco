extends RefCounted

const SPORT := {
	"id": "bike_sport", "label": "Vortex RR 900", "district": "city", "vehicle_kind": "motorcycle",
	"model_class": "res://world/shared/motorcycles/SportMotorcycle.gd", "engine_family": "bike_sport",
	"target_length": 42.0, "target_width": 15.0, "mass": 0.32,
	"max_speed": 640.0, "acceleration": 1100.0, "braking": 1250.0, "turn_speed": 3.6, "drift_factor": 0.96,
	"durability": 65, "engine_pitch": 1.0, "roof_prop": "none", "crop_index": 0,
	"colors": [Color("dc303d"), Color("2165d9"), Color("d6ed35"), Color("e9edef"), Color("1c242c")],
}
const CRUISER := {
	"id": "bike_cruiser", "label": "Ironhorse 1700", "district": "city", "vehicle_kind": "motorcycle",
	"model_class": "res://world/shared/motorcycles/CruiserMotorcycle.gd", "engine_family": "bike_cruiser",
	"target_length": 46.0, "target_width": 18.0, "mass": 0.46,
	"max_speed": 490.0, "acceleration": 780.0, "braking": 1050.0, "turn_speed": 2.7, "drift_factor": 0.95,
	"durability": 85, "engine_pitch": 1.0, "roof_prop": "none", "crop_index": 0,
	"colors": [Color("22262c"), Color("8d2435"), Color("cb702a"), Color("294d43"), Color("e7d8bb")],
}
const URBAN := {
	"id": "bike_urban", "label": "Cometa City 250", "district": "city", "vehicle_kind": "motorcycle",
	"model_class": "res://world/shared/motorcycles/UrbanMotorcycle.gd", "engine_family": "bike_urban",
	"target_length": 39.0, "target_width": 14.0, "mass": 0.24,
	"max_speed": 440.0, "acceleration": 860.0, "braking": 1100.0, "turn_speed": 4.0, "drift_factor": 0.97,
	"durability": 55, "engine_pitch": 1.0, "roof_prop": "none", "crop_index": 0,
	"colors": [Color("245cab"), Color("cd3437"), Color("ecebe3"), Color("34363c"), Color("e3b72d")],
}
