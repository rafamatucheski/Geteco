extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## The authored port prop, adapted to the fleet's -Z forward convention.
var carriage: Node3D

func build() -> void:
	vehicle_id = "port_forklift"
	set_meta("rear_steering", true)
	var source := preload("res://prototypes/harbor_art_pack/props/PortForklift3D.gd").new()
	source._build_model()
	paint = source.get_child(0).material_override
	materials["paint"] = paint
	# The work lamps on the safety cage are the physical beam origins.
	materials["headlight"] = preload("res://prototypes/harbor_art_pack/PortArtMaterials.gd").floodlight_emission()
	carriage = Node3D.new()
	carriage.name = "ForkCarriage"
	add_child(carriage)
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for part: MeshInstance3D in source.get_children():
		source.remove_child(part)
		var old_position := part.position
		part.transform = flip * part.transform
		if part.has_meta("forklift_carriage"):
			carriage.add_child(part)
		else:
			add_child(part)
		if part.mesh is CylinderMesh and absf(part.rotation.z) > 1.0 and (is_equal_approx(old_position.z, .35) or is_equal_approx(old_position.z, -1.25)):
			var front := old_position.z > 0
			part.set_meta("wheel_center", Vector3(signf(part.position.x) * (.545 if front else .525), old_position.y, -old_position.z))
			part.set_meta("wheel_radius", .33 if front else .25)
			part.set_meta("wheel_spins", true)
		if part.material_override not in materials.values():
			materials["port_%d" % materials.size()] = part.material_override
	source.free()

func set_fork_height(height: float) -> void:
	carriage.position.y = height
