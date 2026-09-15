extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Tall, three-axle intercity coach; -Z nose matches the traffic renderer.
var platform_leaves: Array[Node3D] = []
var south_leaves: Array[Node3D] = []
const DOOR_Z := -5.05 # Ahead of the front tire, including the open leaves.
var mountain_platform := false

func build() -> void:
	paint = mat("paint", "3f788b", 0.25, 0.38)
	var ivory := mat("coach_ivory", "ede9db", 0.1, 0.55)
	var dark := mat("bus_black", "172c37", 0.05, 0.65)
	var glass := mat("glass_tinted", "233c4a", 0.32, 0.20)
	var trim := mat("chrome_trim", "98a7ad", 0.65, 0.32)
	var headlamp := mat("headlight", "ffeac1", 0.0, 0.25, 0.8)
	var tail := mat("taillight", "ed503b", 0.0, 0.25, 0.65)
	box(Vector3(0, 1.54, 0), Vector3(2.55, 2.58, 11.50), ivory)
	box(Vector3(0, 2.92, 0.1), Vector3(2.53, 0.66, 10.96), glass)
	box(Vector3(0, 3.33, 0.1), Vector3(2.58, 0.19, 11.15), ivory)
	box(Vector3(0, 0.67, 0), Vector3(2.59, 0.36, 11.60), paint)
	box(Vector3(0, 2.20, 0), Vector3(2.60, 0.26, 11.56), paint)
	box(Vector3(0, 2.56, -5.77), Vector3(2.32, 1.15, 0.06), glass)
	box(Vector3(0, 3.05, -5.82), Vector3(1.92, 0.26, 0.05), dark)
	box(Vector3(0, 1.49, -5.79), Vector3(2.51, 0.36, 0.06), paint)
	box(Vector3(0, 0.35, -5.85), Vector3(2.60, 0.19, 0.15), trim)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.94, 1.12, -5.82), Vector3(0.45, 0.26, 0.08), headlamp)
		box(Vector3(side * 1.0, 1.70, 5.78), Vector3(0.23, 0.62, 0.07), tail)
		box(Vector3(side * 1.34, 2.66, -5.24), Vector3(0.13, 0.12, 0.62), trim)
		box(Vector3(side * 1.49, 2.66, -5.45), Vector3(0.25, 0.44, 0.30), dark)
		for index in 8:
			box(Vector3(side * 1.286, 2.89, 4.72 - index * 1.32), Vector3(0.05, 0.77, 0.10), ivory)
		for z in [3.60, 2.45, -3.82]:
			add_wheel(side * 1.27, 0.60, z, 0.58, 0.25, 0.31, 8, "839196")
		for index in 4:
			box(Vector3(side * 1.30, 1.45, 1.3 - index * 1.12), Vector3(0.02, 0.74, 0.025), trim)
		box(Vector3(side * 1.31, 1.79, -0.45), Vector3(0.018, 0.035, 4.4), trim)
		for index in 5:
			box(Vector3(side * 1.30, 1.11 + index * 0.12, 4.87), Vector3(0.025, 0.035, 1.04), dark)
		var brand := _route_label("EXPRESSO HARBOR", Vector3(side * 1.32, 1.68, 0), 48)
		brand.rotation.y = side * PI / 2.0
		box(Vector3(side * 1.32, 1.48, DOOR_Z), Vector3(0.07, 2.24, 1.15), dark)
		box(Vector3(side * 1.37, 0.39, DOOR_Z), Vector3(0.19, 0.13, 1.19), trim)
		for leaf_side in [-1.0, 1.0]:
			var leaf := Node3D.new()
			leaf.position = Vector3(side * 1.40, 1.48, DOOR_Z + leaf_side * 0.28)
			add_child(leaf)
			var panel := box(leaf.position, Vector3(0.05, 2.12, 0.54), trim)
			panel.reparent(leaf, false)
			panel.position = Vector3.ZERO
			var window := box(leaf.position, Vector3(0.02, 1.65, 0.43), glass)
			window.reparent(leaf, false)
			window.position = Vector3(side * 0.04, 0.10, 0)
			if side < 0:
				platform_leaves.append(leaf)
			else:
				south_leaves.append(leaf)
	box(Vector3(0, 3.56, 1.70), Vector3(1.83, 0.30, 2.72), ivory)
	for index in 6:
		box(Vector3(0, 3.72, 2.68 - index * 0.37), Vector3(1.53, 0.025, 0.10), trim)
	var destination := _route_label("HARBOR · NEVE", Vector3(0, 3.05, -5.86), 35)
	destination.rotation.y = PI

func _route_label(value: String, point: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = size
	label.pixel_size = 0.003
	label.modulate = Color("f3dfad")
	label.outline_size = 0
	label.position = point
	add_child(label)
	return label

func set_platform_doors(amount: float) -> void:
	for index in platform_leaves.size():
		var side := -1.0 if index == 0 else 1.0
		platform_leaves[index].position.z = DOOR_Z + side * (0.28 + (0.0 if mountain_platform else amount) * 0.18)
		south_leaves[index].position.z = DOOR_Z + side * (0.28 + (amount if mountain_platform else 0.0) * 0.18)
