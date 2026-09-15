extends "res://prototypes/living_cast/CoupeDamageModel.gd"

func is_open_top() -> bool:
	return true

func build() -> void:
	super.build()
	var upholstery := mat("upholstery", "292b30", 0.0, 0.9)
	box(Vector3(0,0.34,0.10), Vector3(1.35,0.08,1.6), upholstery)
	for side in [-1.0, 1.0]:
		box(Vector3(side*0.32,0.46,0.12), Vector3(0.48,0.08,0.48), upholstery)
		box(Vector3(side*0.32,0.72,0.38), Vector3(0.48,0.50,0.10), upholstery)
	box(Vector3(0,0.74,-0.62), Vector3(1.3,0.15,0.20), upholstery)
