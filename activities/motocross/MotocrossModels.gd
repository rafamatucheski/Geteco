extends RefCounted
## Comparable trade-offs, shared by the selection menu and physical motorcycles.
const MODELS := [
	{"name":"Trilha 250","role":"Equilibrada","color":Color("d66b22"),"speed":18.0,"acceleration":8.5,"turn":1.0,"grip":1.0,"ratings":[3,3,5]},
	{"name":"Faísca 250","role":"Arrancada","color":Color("c74935"),"speed":17.2,"acceleration":11.5,"turn":.87,"grip":.95,"ratings":[5,2,4]},
	{"name":"Víbora 125","role":"Curvas","color":Color("407c9b"),"speed":16.8,"acceleration":7.7,"turn":1.24,"grip":1.22,"ratings":[2,5,3]}
]

static func apply(bike: CharacterBody3D, model: int) -> void:
	var index := clampi(model,0,MODELS.size()-1)
	var spec: Dictionary = MODELS[index]
	bike.profile_id = index
	bike.max_speed = spec.speed
	bike.acceleration = spec.acceleration
	bike.turn_response = spec.turn
	bike.grip_multiplier = spec.grip
	bike.paint_color = spec.color

static func caption(model: int) -> String:
	var spec: Dictionary = MODELS[clampi(model,0,MODELS.size()-1)]
	return "%s · %s\nAceleração %d/5   Curva %d/5   Final %d/5"%[spec.name,spec.role,spec.ratings[0],spec.ratings[1],spec.ratings[2]]
