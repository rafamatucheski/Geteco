extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Nimbus: forward-cab family minivan with panoramic glass and sliding doors.

const NIMBUS_PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/models/NimbusMinivanPreparedGeometry.scn"
const NIMBUS_PREPARED_GEOMETRY: PackedScene = preload("res://prototypes/living_cast/models/NimbusMinivanPreparedGeometry.scn")
const NIMBUS_PREPARED_CONTRACT_VERSION := 1
const NIMBUS_PREPARED_MATERIAL_KEY_META := &"nimbus_minivan_material_key"
const NIMBUS_EXPECTED_PREPARED_SIGNATURE := 1774174466
const NIMBUS_EXPECTED_PREPARED_MESHES := 30
const NIMBUS_EXPECTED_PREPARED_TRIANGLES := 19689


func _ready() -> void:
	if get_meta("nimbus_minivan_geometry_source", &"") == &"prepared":
		_nimbus_bind_prepared_materials(self)
	super._ready()


func vehicle_prepared_template_resource() -> PackedScene:
	return NIMBUS_PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_nimbus_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _nimbus_prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"vehicle_wheel_clearance_signature": int(template.get_meta("vehicle_wheel_clearance_signature", 0)),
		&"vehicle_prepared_wheel_wells": true,
		&"nimbus_minivan_geometry_source": &"prepared",
		&"nimbus_minivan_prepared_geometry_signature": int(template.get_meta("nimbus_minivan_prepared_geometry_signature", 0)),
		&"silhouette_signature": template.get_meta("silhouette_signature", "forward_cab_long_arch_minivan"),
		&"cabin_kind": template.get_meta("cabin_kind", "panoramic_three_row"),
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_nimbus_bind_prepared_materials(template)


func build(use_prepared_geometry: bool = true) -> void:
	if get_child_count() != 0:
		push_error("NimbusMinivanModel.build refused duplicate geometry")
		return
	_nimbus_prepare_runtime_materials()
	if use_prepared_geometry:
		var prepared := vehicle_prepared_template_resource()
		var template := prepared.instantiate() as Node3D if prepared != null else null
		if template != null and _nimbus_prepared_template_is_acceptable(template):
			for metadata in template.get_meta_list():
				set_meta(metadata, template.get_meta(metadata))
			set_meta("vehicle_mesh_batched", true)
			set_meta("vehicle_prepared_wheel_wells", true)
			set_meta("nimbus_minivan_geometry_source", &"prepared")
			for child in template.get_children():
				_nimbus_clear_owner(child)
				template.remove_child(child)
				add_child(child)
				_nimbus_bind_prepared_materials(child)
			template.free()
			return
		if template != null:
			template.free()
		set_meta("nimbus_minivan_geometry_source", &"procedural_fallback")
	_nimbus_build_procedural_geometry()


func build_nimbus_procedural_source() -> void:
	if get_child_count() != 0:
		push_error("NimbusMinivanModel.build_nimbus_procedural_source refused duplicate geometry")
		return
	_nimbus_prepare_runtime_materials()
	_nimbus_build_procedural_geometry()


func _nimbus_prepare_runtime_materials() -> void:
	vehicle_id = "nimbus_minivan"
	paint = mat("paint", "6d7f92", 0.32, 0.27)
	mat("rubber", "171b1f", 0.0, 0.93)
	mat("trim", "283137", 0.24, 0.50)
	var glass := mat("glass", "1f3e50", 0.40, 0.13)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "e3f6ff", 0.10, 0.15, 0.74)
	mat("taillight", "ca3235", 0.10, 0.21, 0.70)
	mat("chrome", "cbd4d8", 0.76, 0.25)
	mat("rim_c7d0d4", "c7d0d4", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)
	set_silhouette("forward_cab_long_arch_minivan", "panoramic_three_row")


func _nimbus_build_procedural_geometry() -> void:
	var trim := materials["trim"] as Material
	var head := materials["headlight"] as Material
	var tail := materials["taillight"] as Material
	var chrome := materials["chrome"] as Material

	var axles: Array[float] = [-1.55, 1.48]
	sculpted_shell([
		Vector3(-2.48, 0.55, 0.62), Vector3(-2.22, 0.88, 0.91),
		Vector3(-1.15, 0.98, 1.00), Vector3(1.32, 0.99, 1.01),
		Vector3(2.30, 0.88, 0.88), Vector3(2.48, 0.61, 0.64),
	], axles, 0.38, 0.36, 0.055, 0.27)
	add_underbody(4.72, 1.70, 0.26)
	add_greenhouse(-2.16, 2.18, -1.78, 1.90, 1.00, 1.77, 0.91, 0.75, 3, 0.075)
	add_aero_mirrors(-1.92, 1.06, 1.15, Vector3(0.22, 0.12, 0.17))
	add_flush_handles([-0.98, 0.70], 1.005, 0.85, chrome)

	# Sliding-door rails and deep side steps communicate family/MPV use.
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 1.012, 0.93, -0.24), Vector3(side * 1.012, 0.93, 1.62)], 0.011, chrome)
		tube([Vector3(side * 1.012, 0.42, -0.36), Vector3(side * 1.012, 0.42, 1.72)], 0.016, trim)
		box(Vector3(side * 0.66, 0.72, -2.46), Vector3(0.38, 0.14, 0.035), head)
		box(Vector3(side * 0.82, 1.02, 2.45), Vector3(0.13, 0.48, 0.035), tail)
		add_wheel(side * 0.95, 0.38, -1.55, 0.36, 0.225, 0.23, 8, "c7d0d4")
		add_wheel(side * 0.95, 0.38, 1.48, 0.36, 0.225, 0.23, 8, "c7d0d4")
	box(Vector3(0.0, 1.80, 0.16), Vector3(1.40, 0.035, 2.80), paint)
	for z in [-2.50, 2.50]:
		box(Vector3(0.0, 0.36, z), Vector3(1.74, 0.11, 0.11), trim)


func _nimbus_prepared_template_is_acceptable(template: Node3D) -> bool:
	if template == null:
		return false
	if int(template.get_meta("nimbus_minivan_prepared_contract_version", 0)) != NIMBUS_PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("nimbus_minivan_prepared_geometry_signature", 0)) != NIMBUS_EXPECTED_PREPARED_SIGNATURE:
		return false
	if int(template.get_meta("nimbus_minivan_prepared_meshes", 0)) != NIMBUS_EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("nimbus_minivan_prepared_triangles", 0)) != NIMBUS_EXPECTED_PREPARED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
		return false
	if String(template.get_meta("silhouette_signature", "")) != "forward_cab_long_arch_minivan":
		return false
	if String(template.get_meta("cabin_kind", "")) != "panoramic_three_row":
		return false
	var meshes := 0
	var triangles := 0
	var wheel_centres: Array[Vector3] = []
	var lamps := 0
	var damage_bodies := 0
	for child in template.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null or part.get_script() != null:
			return false
		meshes += 1
		triangles += _nimbus_mesh_triangle_count(part.mesh)
		var material_key := StringName(part.get_meta(NIMBUS_PREPARED_MATERIAL_KEY_META, &""))
		if material_key.is_empty() or not materials.has(material_key):
			return false
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			if not wheel_centres.has(centre):
				wheel_centres.append(centre)
		if bool(part.get_meta("nimbus_minivan_lamp", false)):
			lamps += 1
		if bool(part.get_meta("nimbus_minivan_damage_body", false)):
			if material_key != &"paint" or part.mesh.get_surface_count() != 1:
				return false
			damage_bodies += 1
	return meshes == NIMBUS_EXPECTED_PREPARED_MESHES \
			and triangles == NIMBUS_EXPECTED_PREPARED_TRIANGLES \
			and wheel_centres.size() == 4 \
			and lamps >= 4 \
			and damage_bodies >= 1


func _nimbus_mesh_triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	return count


func _nimbus_bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := StringName(part.get_meta(NIMBUS_PREPARED_MATERIAL_KEY_META, &""))
		if materials.has(material_key):
			part.material_override = materials[material_key]
	for child in node.get_children():
		_nimbus_bind_prepared_materials(child)


func _nimbus_clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_nimbus_clear_owner(child)
