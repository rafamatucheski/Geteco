extends Node3D
var split_count := 0
var log_piece: MeshInstance3D

func _ready() -> void:
	var parts = preload("res://world/shared/pedestrians/CitizenDetails.gd")
	var stump := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .24
	cylinder.bottom_radius = .30
	cylinder.height = .43
	cylinder.radial_segments = 10
	stump.mesh = cylinder
	stump.position.y = .215
	stump.material_override = StandardMaterial3D.new()
	stump.material_override.albedo_color = Color("70503a")
	add_child(stump)
	parts.piece(self,Vector3(.38,.025,.38),Vector3(0,.44,0),Color("c39a63"),true)
	log_piece = parts.piece(self,Vector3(.13,.25,.14),Vector3(0,.57,0),Color("a47b4a"))
	for i in 5:
		var wood: MeshInstance3D = parts.piece(self,Vector3(.12,.10,.38),Vector3(.4+float(i%2)*.12,.06+float(i/2)*.07,1.0),Color("b78d58"))
		wood.rotation.y = float(i)*.35

func chop() -> void:
	split_count += 1
	# Keep the target seated on its support; chips show the cut without moving
	# the contact surface out from under the next stroke.
	for i in 4:
		var chip_name := "SplitWood%d" % i
		var chip := get_node_or_null(chip_name) as MeshInstance3D
		if chip == null:
			chip = preload("res://world/shared/pedestrians/CitizenDetails.gd").piece(self,Vector3(.035,.025,.12),Vector3.ZERO,Color("d0a371"))
			chip.name = chip_name
		chip.position = Vector3(-.3 + i * .18, .03, .18 + .08 * (split_count % 3))
		chip.rotation.y = split_count * .8 + i
