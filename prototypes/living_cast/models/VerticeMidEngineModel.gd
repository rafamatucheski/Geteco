extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Vértice MR: very low, wide mid-engine wedge with a compact teardrop cabin.


func build() -> void:
	vehicle_id = "vertice_midengine"
	paint = mat("paint", "d43b32", 0.42, 0.20)
	var rubber := mat("rubber", "14181c", 0.0, 0.94)
	var trim := mat("trim", "20282e", 0.36, 0.38)
	var glass := mat("glass", "172f3f", 0.46, 0.10)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "dff5ff", 0.12, 0.12, 0.82)
	var tail := mat("taillight", "b91f2c", 0.12, 0.18, 0.80)
	var alloy := mat("alloy", "aab4bb", 0.82, 0.23)
	var amber := mat("amber", "ed9829", 0.10, 0.20, 0.46)
	set_silhouette("low_wide_mid_engine_wedge", "compact_teardrop")

	var axles: Array[float] = [-1.38, 1.30]
	sculpted_shell([
		Vector3(-2.34, 0.26, 0.36), Vector3(-2.02, 0.78, 0.52),
		Vector3(-1.18, 1.02, 0.68), Vector3(0.82, 1.08, 0.78),
		Vector3(1.78, 0.97, 0.72), Vector3(2.18, 0.61, 0.48),
	], axles, 0.34, 0.36, 0.065, 0.20)
	add_underbody(4.25, 1.82, 0.19)
	add_greenhouse(-0.68, 1.18, -0.24, 0.86, 0.78, 1.16, 0.86, 0.62, 1, 0.055)
	add_aero_mirrors(-0.45, 1.12, 0.82, Vector3(0.24, 0.07, 0.18))
	add_flush_handles([0.36], 1.075, 0.65, trim)

	for side in [-1.0, 1.0]:
		# Deep triangular side intake feeds the mid-mounted engine.
		surface([Vector3(side * 1.085, 0.34, 0.36), Vector3(side * 1.085, 0.72, 0.55), Vector3(side * 1.085, 0.67, 1.16)], trim)
		box(Vector3(side * 0.61, 0.50, -2.18), Vector3(0.46, 0.045, 0.035), head)
		box(Vector3(side * 0.91, 0.44, -1.96), Vector3(0.07, 0.09, 0.035), amber)
		box(Vector3(side * 0.58, 0.61, 2.13), Vector3(0.52, 0.055, 0.035), tail)
		add_wheel(side * 1.03, 0.34, -1.38, 0.36, 0.255, 0.27, 5, "b8c1c6")
		add_wheel(side * 1.04, 0.35, 1.30, 0.39, 0.275, 0.29, 5, "b8c1c6")
	box(Vector3(0.0, 0.28, -2.30), Vector3(1.78, 0.045, 0.26), trim)
	box(Vector3(0.0, 0.27, 2.19), Vector3(1.82, 0.07, 0.19), trim)
	# Visible louvered engine cover behind the short cabin.
	for index in 8:
		box(Vector3(0.0, 0.82, 1.18 + index * 0.10), Vector3(1.26, 0.018, 0.045), trim)
	add_exhaust_dual(0.52, 0.28, 2.22, 0.070)

