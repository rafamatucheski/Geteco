extends Node3D
func _ready() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("38434a")
	iron.roughness = 0.8
	var bowl := preload("res://runtime/cold/FireArt.gd").bowl()
	bowl.position.y = .38
	add_child(bowl)
	var fuel := preload("res://runtime/cold/FireArt.gd").fuel()
	fuel.position.y = .72
	add_child(fuel)
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
