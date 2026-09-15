extends "res://prototypes/living_cast/models/UnionSedanModel.gd"

## Shared parked/response cruiser, including its real roof-mounted lightbar.
func build() -> void:
	super.build()
	vehicle_id = "police_cruiser"
	paint.albedo_color = Color("e5e9ed")
	var navy := mat("police_navy", "19314e", 0.3, 0.35)
	box(Vector3(0, 0.815, -1.5), Vector3(1.73, 0.035, 1.45), navy)
	box(Vector3(0, 0.84, 1.65), Vector3(1.7, 0.035, 1.2), navy)
	add_lightbar(1.47, 0.05, Color("e83c42"), Color("3689ef"), 1.1)
