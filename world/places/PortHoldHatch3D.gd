extends Node3D
var open_amount := 0.0
var pivot: Node3D

func _ready() -> void:
	name = "SantaMareHoldHatch"
	add_to_group("santa_mare_hold_hatch")
	pivot = Node3D.new()
	add_child(pivot)
	var lid := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.48,.11,1.48)
	lid.mesh = box
	lid.position.x = .74
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("697a78")
	surface.roughness = .82
	lid.material_override = surface
	pivot.add_child(lid)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	if is_instance_valid(pivot): pivot.rotation.z = open_amount*PI*.48
