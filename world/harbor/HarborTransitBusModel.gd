extends "res://prototypes/living_cast/models/RouteCityModel.gd"
## Compact terminal coach with an animated door on the platform side.
const DOOR_Z := -4.05 # Front overhang, clear of the wheel arch.
var platform_leaves: Array[Node3D] = []

func build() -> void:
	super.build()
	var frame := materials["bus_black"] as Material
	var glazing := materials["glass_tinted"] as Material
	var trim := materials["chrome_trim"] as Material
	# Local -X faces the north platform; local -Z is the front of the coach.
	box(Vector3(-1.215, 1.45, DOOR_Z), Vector3(0.04, 2.24, 1.25), frame)
	box(Vector3(-1.24, 0.40, DOOR_Z), Vector3(0.18, 0.10, 1.20), trim)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "PlatformDoorLeaf"
		leaf.position = Vector3(-1.25, 1.45, DOOR_Z + side * 0.30)
		add_child(leaf)
		var panel := box(leaf.position, Vector3(0.05, 2.12, 0.57), trim)
		panel.reparent(leaf, false)
		panel.position = Vector3.ZERO
		var window := box(leaf.position + Vector3(-0.035, 0.20, 0), Vector3(0.02, 1.52, 0.47), glazing)
		window.reparent(leaf, false)
		window.position = Vector3(-0.035, 0.20, 0)
		platform_leaves.append(leaf)

func set_platform_doors(amount: float) -> void:
	for i in platform_leaves.size():
		var side := -1.0 if i == 0 else 1.0
		platform_leaves[i].position.z = DOOR_Z + side * (0.30 + clampf(amount, 0.0, 1.0) * 0.10)

