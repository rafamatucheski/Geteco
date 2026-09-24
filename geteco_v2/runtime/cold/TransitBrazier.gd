extends Node3D
func _ready() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("38434a")
	iron.roughness = 0.8
	var bowl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.66
	mesh.bottom_radius = 0.39
	mesh.height = 0.46
	mesh.radial_segments = 16
	bowl.mesh = mesh
	bowl.material_override = iron
	bowl.position.y = 0.61
	add_child(bowl)
	for side in [-1.0,1.0]:
		var leg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12,0.5,0.62)
		leg.mesh = box
		leg.material_override = iron
		leg.position = Vector3(side*0.38,0.25,0)
		add_child(leg)
	var flame := preload("res://runtime/cold/HearthEffects.gd").new()
	flame.position.y = 0.76
	flame.scale = Vector3.ONE * 2.3
	flame.smoke_height = 1.4
	add_child(flame)
