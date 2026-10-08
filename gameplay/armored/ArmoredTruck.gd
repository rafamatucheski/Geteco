extends "res://gameplay/dispatch/DispatchVehicle.gd"
var vault_doors: Array[Node3D] = []
var cargo: Node3D
var opened := false

func _init() -> void:
	super._init()
	archetype = "armored_truck"
	paint_color = Color("64736d")

func _ready() -> void:
	super._ready()
	vault_doors.assign([visual.get_node("VaultDoorLeft"),visual.get_node("VaultDoorRight")])
	cargo = visual.get_node("VaultCargo")
	set_vault(opened)

func door_point() -> Vector3:
	# Outside the rear bumper and vehicle collider, reachable from the ground.
	return to_global(Vector3(0,.4,half_length+.8))

func set_vault(value: bool, empty := false) -> void:
	opened = value
	for index in vault_doors.size():
		vault_doors[index].rotation.y = (-1 if index == 0 else 1)*1.85 if value else 0.0
	if is_instance_valid(cargo): cargo.visible = value and not empty
