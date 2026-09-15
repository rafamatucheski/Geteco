extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Órbita: rounded one-box city micro-hatch with wheels pushed to the corners.


func build() -> void:
	vehicle_id = "orbita_micro"
	paint = mat("paint", "58a7d8", 0.24, 0.25)
	var rubber := mat("rubber", "171b20", 0.0, 0.92)
	var trim := mat("trim", "293238", 0.24, 0.44)
	var glass := mat("glass", "203d4d", 0.38, 0.14)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e9f7ff", 0.10, 0.14, 0.72)
	var tail := mat("taillight", "d93c38", 0.10, 0.20, 0.70)
	var chrome := mat("chrome", "d3dadd", 0.74, 0.24)
	var amber := mat("amber", "f4a62d", 0.10, 0.22, 0.45)
	set_silhouette("short_round_micro_hatch", "bubble_two_box")

	var axles: Array[float] = [-1.08, 1.02]
	sculpted_shell([
		Vector3(-1.74, 0.48, 0.51), Vector3(-1.48, 0.76, 0.72),
		Vector3(-0.72, 0.84, 0.83), Vector3(0.88, 0.83, 0.85),
		Vector3(1.55, 0.68, 0.68), Vector3(1.70, 0.44, 0.51),
	], axles, 0.34, 0.32, 0.075, 0.25)
	add_underbody(3.24, 1.42, 0.23)
	add_greenhouse(-0.96, 1.38, -0.56, 1.04, 0.84, 1.48, 0.79, 0.64, 2, 0.09)
	add_aero_mirrors(-0.73, 0.88, 0.94, Vector3(0.17, 0.08, 0.15))
	add_flush_handles([-0.08, 0.74], 0.845, 0.72, chrome)

	for side in [-1.0, 1.0]:
		var front := cylinder(Vector3(side * 0.49, 0.69, -1.67), 0.115, 0.045, head)
		front.rotation.x = PI / 2.0
		box(Vector3(side * 0.73, 0.55, -1.67), Vector3(0.12, 0.12, 0.04), amber)
		box(Vector3(side * 0.68, 0.90, 1.64), Vector3(0.13, 0.36, 0.04), tail)
		add_wheel(side * 0.80, 0.34, -1.08, 0.32, 0.20, 0.20, 7, "d7dfe2")
		add_wheel(side * 0.80, 0.34, 1.02, 0.32, 0.20, 0.20, 7, "d7dfe2")
	box(Vector3(0.0, 1.50, 1.08), Vector3(1.18, 0.045, 0.19), trim)
	box(Vector3(0.0, 0.36, -1.73), Vector3(1.32, 0.10, 0.10), trim)
	box(Vector3(0.0, 0.35, 1.71), Vector3(1.28, 0.10, 0.10), trim)

