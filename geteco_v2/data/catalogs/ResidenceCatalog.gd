extends RefCounted
# Original property definitions; coordinates remain source-space metadata.
const PROPERTIES := {
	"westgate_garden": {
		"id": "westgate_garden", "name": "CASA", "price": 10000, "variant": 0,
		"position": Vector2(250, 150), "footprint": Vector2(200, 120), "standalone": true,
		"entrance_offset": Vector2(0, 120), "garage_offset": Vector2(88, 122),
		"monaliza_offset": Vector2(-60, 125), "extra_vehicle_offset": Vector2(40, 125),
		"checkpoint_offset": Vector2(-45, 135), "vehicle_rotation": 0.0,
		"driveway": [Vector2(-10,125),Vector2(30,190),Vector2(150,330)],
		"walkway": [Vector2(0,80),Vector2(110,80),Vector2(110,210)],
		"accent": Color("d2a95f"), "interior_position": Vector2(50000, 20000),
	},
	"quayside_house": {
		"id": "quayside_house", "name": "CASA", "price": 25000, "variant": 1,
		"position": Vector2(2775, 1670), "footprint": Vector2(200, 120), "standalone": true,
		"entrance_offset": Vector2(40, 116), "garage_offset": Vector2(-86, 120),
		"monaliza_offset": Vector2(5, 140), "extra_vehicle_offset": Vector2(5, 210),
		"checkpoint_offset": Vector2(42, 140), "vehicle_rotation": 0.0,
		"driveway": [Vector2(5,175),Vector2(120,175),Vector2(225,175)],
		"walkway": [Vector2(0,94),Vector2(65,94),Vector2(65,175)],
		"accent": Color("73b6b3"), "interior_position": Vector2(51000, 20000),
	},
	"canal_north": {
		"id": "canal_north", "name": "CASA", "price": 45000, "variant": 2,
		"position": Vector2(4915, -860), "footprint": Vector2(250, 180), "standalone": false,
		"entrance_offset": Vector2(0, 116), "garage_offset": Vector2(-78, 124),
		"monaliza_offset": Vector2(-105, 140), "extra_vehicle_offset": Vector2(-5, 140),
		"checkpoint_offset": Vector2(46, 132), "vehicle_rotation": 0.0,
		"driveway": [Vector2(-55,88),Vector2(-165,88),Vector2(-265,88)],
		"walkway": [Vector2(0,80),Vector2(90,80),Vector2(90,140)],
		"accent": Color("86ae78"), "interior_position": Vector2(52000, 20000),
	},
}
