extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Short expedition cabin, vertical grille, canvas rear, spare and fuel cans.
## Body panels share the inherited paint material for garage recoloring.

const PREPARED_GEOMETRY := preload("res://prototypes/living_cast/models/ArcticJeepPreparedGeometry.scn")
const MATERIAL_ROLE_META := &"arctic_jeep_material_role"
const SURFACE_ROLES_META := &"arctic_jeep_surface_material_roles"
const EXPECTED_CONTRACT_VERSION := 1
const EXPECTED_SIGNATURE := 2561308829
const EXPECTED_MESHES := 12
const EXPECTED_TRIANGLES := 9158
const EXPECTED_CLEARANCE_SIGNATURE := 2025983418
const EXPECTED_MATERIAL_ROLES := [
	&"paint", &"trim", &"canvas", &"glass", &"steel", &"headlight",
	&"rear_lens", &"rubber", &"rim_b5bdc3", &"caliper", &"rotor",
]


## Direct prepared-resource contract used by resumable regional prewarm.
func vehicle_prepared_template_resource() -> PackedScene:
	return PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(_template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"arctic_jeep_geometry_source": &"prepared",
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_bind_prepared_materials(template)


func build() -> void:
	if get_child_count() != 0:
		push_error("ArcticJeepModel.build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	var template := PREPARED_GEOMETRY.instantiate() as Node3D
	if template == null or not _prepared_template_is_acceptable(template):
		if template != null:
			template.free()
		set_meta("arctic_jeep_geometry_source", &"procedural_fallback")
		build_procedural_source()
		return
	for metadata in template.get_meta_list():
		set_meta(metadata, template.get_meta(metadata))
	set_meta("arctic_jeep_geometry_source", &"prepared")
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_prepared_materials(child)
	template.free()


func _prepare_runtime_materials() -> void:
	materials.clear()
	paint = null
	paint = mat("paint", "dce3df", 0.25, 0.42)
	mat("trim", "253139", 0.25, 0.8)
	mat("canvas", "536358", 0.0, 0.95)
	mat("glass", "42616c", 0.3, 0.18)
	mat("steel", "78898c", 0.75, 0.32)
	mat("headlight", "fff1c5", 0.1, 0.2, 0.7)
	mat("rear_lens", "c74b43", 0.1, 0.2, 0.5)
	mat("rubber", "15191d", 0.0, 0.92)
	mat("rim_b5bdc3", "b5bdc3", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)


func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("arctic_jeep_prepared_contract_version", 0)) != EXPECTED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("arctic_jeep_prepared_geometry_signature", 0)) != EXPECTED_SIGNATURE:
		return false
	if int(template.get_meta("arctic_jeep_prepared_meshes", 0)) != EXPECTED_MESHES:
		return false
	if int(template.get_meta("arctic_jeep_prepared_triangles", 0)) != EXPECTED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) != EXPECTED_CLEARANCE_SIGNATURE:
		return false
	if not bool(template.get_meta("vehicle_mesh_batched", false)):
		return false
	var recorded_counts_value = template.get_meta("arctic_jeep_material_role_counts", {})
	if not recorded_counts_value is Dictionary:
		return false
	var recorded_counts := recorded_counts_value as Dictionary
	var actual_counts: Dictionary = {}
	var wheel_flags: Dictionary = {}
	var headlamps := 0
	var meshes := 0
	for child in template.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			return false
		meshes += 1
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if surface_roles.size() != part.mesh.get_surface_count():
			return false
		for role_value in surface_roles:
			var role := StringName(role_value)
			if role == &"" or not materials.has(role):
				return false
			actual_counts[role] = int(actual_counts.get(role, 0)) + 1
			if role == &"headlight":
				headlamps += 1
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			var flags := int(wheel_flags.get(centre, 0))
			if bool(part.get_meta("wheel_spins", false)):
				flags |= 1
			else:
				flags |= 2
			wheel_flags[centre] = flags
	if meshes != EXPECTED_MESHES or actual_counts.size() != EXPECTED_MATERIAL_ROLES.size():
		return false
	for role_value in EXPECTED_MATERIAL_ROLES:
		var role := StringName(role_value)
		var actual := int(actual_counts.get(role, 0))
		if actual <= 0 or actual != _recorded_role_count(recorded_counts, role):
			return false
	if headlamps != 2 or wheel_flags.size() != 4:
		return false
	if int(actual_counts.get(&"paint", 0)) != 1 or int(actual_counts.get(&"canvas", 0)) <= 0:
		return false
	for centre in wheel_flags:
		if int(wheel_flags[centre]) != 3:
			return false
	return true


func _recorded_role_count(recorded_counts: Dictionary, role: StringName) -> int:
	if recorded_counts.has(role):
		return int(recorded_counts[role])
	return int(recorded_counts.get(String(role), 0))


func _bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if _all_same_surface_role(surface_roles):
			part.material_override = materials[StringName(surface_roles[0])]
		else:
			part.material_override = null
			for surface_index in surface_roles.size():
				part.set_surface_override_material(surface_index, materials[StringName(surface_roles[surface_index])])
	for child in node.get_children():
		_bind_prepared_materials(child)


func _all_same_surface_role(surface_roles: PackedStringArray) -> bool:
	if surface_roles.is_empty():
		return false
	for role in surface_roles:
		if role != surface_roles[0]:
			return false
	return true


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


## Retained exact authoring source used only to rebuild the prepared resource or
## as a defensive fallback when that resource fails its semantic contract.
func build_procedural_source() -> void:
	if get_child_count() != 0:
		push_error("ArcticJeepModel procedural build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	var trim := materials["trim"] as StandardMaterial3D
	var canvas := materials["canvas"] as StandardMaterial3D
	var glass := materials["glass"] as StandardMaterial3D
	var steel := materials["steel"] as StandardMaterial3D
	var lamp := materials["headlight"] as StandardMaterial3D
	box(Vector3(0,0.40,0),Vector3(1.8,0.18,4.4),trim)
	box(Vector3(0,0.80,0),Vector3(1.88,0.55,4.35),paint)
	box(Vector3(0,1.12,-1.38),Vector3(1.7,0.14,1.50),paint)
	box(Vector3(0,1.48,-0.61),Vector3(1.65,0.62,0.07),glass)
	box(Vector3(0,1.81,0.57),Vector3(1.82,0.10,2.64),canvas)
	box(Vector3(0,1.47,1.82),Vector3(1.76,0.68,0.14),canvas)
	for side in [-1.0,1.0]:
		box(Vector3(side*0.86,1.46,0.25),Vector3(0.05,0.56,1.60),glass)
		box(Vector3(side*0.90,1.02,0.30),Vector3(0.06,0.40,1.55),paint)
		box(Vector3(side*0.90,1.40,-0.58),Vector3(0.10,0.74,0.10),paint)
		box(Vector3(side*0.90,1.44,1.30),Vector3(0.10,0.70,0.10),canvas)
		box(Vector3(side*1.01,1.34,-0.52),Vector3(0.20,0.18,0.12),trim)
		box(Vector3(side*0.97,0.72,-1.45),Vector3(0.20,0.18,0.96),trim)
		box(Vector3(side*0.97,0.72,1.45),Vector3(0.20,0.18,0.96),trim)
		for z in [-1.45,1.45]: add_wheel(side*0.98,0.36,z,0.38,0.27,0.21,6)
		var lens := cylinder(Vector3(side*0.65,0.96,-2.19),0.15,0.04,lamp)
		lens.rotation.x = PI*0.5
		box(Vector3(side*0.76,0.86,2.2),Vector3(0.19,0.23,0.06),materials["rear_lens"] as Material)
	for x in [-0.36,-0.24,-0.12,0.0,0.12,0.24,0.36]:
		box(Vector3(x,0.96,-2.2),Vector3(0.055,0.34,0.04),trim)
	box(Vector3(0,0.58,-2.27),Vector3(1.94,0.18,0.20),steel)
	box(Vector3(0,0.60,2.25),Vector3(1.94,0.16,0.16),steel)
	var spare := cylinder(Vector3(0,1.18,2.30),0.39,0.23,trim)
	spare.rotation.x = PI*0.5
	box(Vector3(-0.64,1.09,2.31),Vector3(0.29,0.52,0.22),canvas)
	box(Vector3(0.64,1.09,2.31),Vector3(0.29,0.52,0.22),canvas)
	tube([Vector3(0.86,1,-1.4),Vector3(0.86,1.90,-0.57)],0.035,trim)
