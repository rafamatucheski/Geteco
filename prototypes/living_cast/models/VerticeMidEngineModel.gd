extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Vértice MR: very low, wide mid-engine wedge with a compact teardrop cabin.

const VERTICE_PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/models/VerticeMidEnginePreparedGeometry.scn"
const VERTICE_PREPARED_GEOMETRY: PackedScene = preload("res://prototypes/living_cast/models/VerticeMidEnginePreparedGeometry.scn")
const VERTICE_PREPARED_CONTRACT_VERSION := 1
const VERTICE_PREPARED_MATERIAL_KEY_META := &"vertice_midengine_material_key"
const VERTICE_EXPECTED_PREPARED_SIGNATURE := 1785881472
const VERTICE_EXPECTED_PREPARED_MESHES := 32
const VERTICE_EXPECTED_PREPARED_TRIANGLES := 16694


func _ready() -> void:
	if get_meta("vertice_midengine_geometry_source", &"") == &"prepared":
		_vertice_bind_prepared_materials(self)
	super._ready()


func vehicle_prepared_template_resource() -> PackedScene:
	return VERTICE_PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_vertice_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _vertice_prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"vehicle_wheel_clearance_signature": int(template.get_meta("vehicle_wheel_clearance_signature", 0)),
		&"vehicle_prepared_wheel_wells": true,
		&"vertice_midengine_geometry_source": &"prepared",
		&"vertice_midengine_prepared_geometry_signature": int(template.get_meta("vertice_midengine_prepared_geometry_signature", 0)),
		&"silhouette_signature": template.get_meta("silhouette_signature", "low_wide_mid_engine_wedge"),
		&"cabin_kind": template.get_meta("cabin_kind", "compact_teardrop"),
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_vertice_bind_prepared_materials(template)


func build(use_prepared_geometry: bool = true) -> void:
	if get_child_count() != 0:
		push_error("VerticeMidEngineModel.build refused duplicate geometry")
		return
	_vertice_prepare_runtime_materials()
	if use_prepared_geometry:
		var prepared := vehicle_prepared_template_resource()
		var template := prepared.instantiate() as Node3D if prepared != null else null
		if template != null and _vertice_prepared_template_is_acceptable(template):
			for metadata in template.get_meta_list():
				set_meta(metadata, template.get_meta(metadata))
			set_meta("vehicle_mesh_batched", true)
			set_meta("vehicle_prepared_wheel_wells", true)
			set_meta("vertice_midengine_geometry_source", &"prepared")
			for child in template.get_children():
				_vertice_clear_owner(child)
				template.remove_child(child)
				add_child(child)
				_vertice_bind_prepared_materials(child)
			template.free()
			return
		if template != null:
			template.free()
		set_meta("vertice_midengine_geometry_source", &"procedural_fallback")
	_vertice_build_procedural_geometry()


func build_vertice_procedural_source() -> void:
	if get_child_count() != 0:
		push_error("VerticeMidEngineModel.build_vertice_procedural_source refused duplicate geometry")
		return
	_vertice_prepare_runtime_materials()
	_vertice_build_procedural_geometry()


func _vertice_prepare_runtime_materials() -> void:
	vehicle_id = "vertice_midengine"
	paint = mat("paint", "d43b32", 0.42, 0.20)
	mat("rubber", "14181c", 0.0, 0.94)
	mat("trim", "20282e", 0.36, 0.38)
	var glass := mat("glass", "172f3f", 0.46, 0.10)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "dff5ff", 0.12, 0.12, 0.82)
	mat("taillight", "b91f2c", 0.12, 0.18, 0.80)
	mat("alloy", "aab4bb", 0.82, 0.23)
	mat("amber", "ed9829", 0.10, 0.20, 0.46)
	# add_wheel/add_exhaust_dual use these stable runtime material roles.
	mat("rim_b8c1c6", "b8c1c6", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)
	mat("chrome_exhaust", "dcdde1", 0.85, 0.2)
	mat("exhaust_hole", "000000", 0.0, 1.0)
	set_silhouette("low_wide_mid_engine_wedge", "compact_teardrop")


func _vertice_build_procedural_geometry() -> void:
	var trim := materials["trim"] as Material
	var head := materials["headlight"] as Material
	var tail := materials["taillight"] as Material
	var amber := materials["amber"] as Material

	var axles: Array[float] = [-1.38, 1.30]
	sculpted_shell([
		Vector3(-2.34, 0.30, 0.39), Vector3(-2.02, 0.82, 0.58),
		Vector3(-1.18, 1.03, 0.75), Vector3(0.82, 1.08, 0.80),
		Vector3(1.78, 1.00, 0.76), Vector3(2.18, 0.64, 0.52),
	], axles, 0.27, 0.31, 0.060, 0.19)
	add_underbody(4.25, 1.82, 0.19)
	add_greenhouse(-0.72, 1.12, -0.28, 0.80, 0.82, 1.18, 0.86, 0.62, 1, 0.055)
	add_aero_mirrors(-0.45, 1.12, 0.82, Vector3(0.24, 0.07, 0.18))
	add_flush_handles([0.36], 1.075, 0.65, trim)

	# The compact sports-car tires sit inside the shoulder line and below its
	# crown. This keeps the wheel wells readable in perspective without making
	# four detached tires dominate the overhead gameplay view.
	for side in [-1.0, 1.0]:
		# Deep triangular side intake feeds the mid-mounted engine.
		surface([Vector3(side * 1.085, 0.34, 0.36), Vector3(side * 1.085, 0.72, 0.55), Vector3(side * 1.085, 0.67, 1.16)], trim)
		box(Vector3(side * 0.61, 0.50, -2.18), Vector3(0.46, 0.045, 0.035), head)
		box(Vector3(side * 0.91, 0.44, -1.96), Vector3(0.07, 0.09, 0.035), amber)
		box(Vector3(side * 0.58, 0.61, 2.13), Vector3(0.52, 0.055, 0.035), tail)
		add_wheel(side * 0.73, 0.27, -1.38, 0.30, 0.20, 0.225, 5, "b8c1c6")
		add_wheel(side * 0.76, 0.28, 1.30, 0.32, 0.21, 0.24, 5, "b8c1c6")
	box(Vector3(0.0, 0.28, -2.30), Vector3(1.78, 0.045, 0.26), trim)
	box(Vector3(0.0, 0.27, 2.19), Vector3(1.82, 0.07, 0.19), trim)
	# Visible louvered engine cover behind the short cabin.
	for index in 8:
		box(Vector3(0.0, 0.82, 1.18 + index * 0.10), Vector3(1.26, 0.018, 0.045), trim)
	add_exhaust_dual(0.52, 0.28, 2.22, 0.070)


func _vertice_prepared_template_is_acceptable(template: Node3D) -> bool:
	if template == null:
		return false
	if int(template.get_meta("vertice_midengine_prepared_contract_version", 0)) != VERTICE_PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("vertice_midengine_prepared_geometry_signature", 0)) != VERTICE_EXPECTED_PREPARED_SIGNATURE:
		return false
	if int(template.get_meta("vertice_midengine_prepared_meshes", 0)) != VERTICE_EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("vertice_midengine_prepared_triangles", 0)) != VERTICE_EXPECTED_PREPARED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
		return false
	if String(template.get_meta("silhouette_signature", "")) != "low_wide_mid_engine_wedge":
		return false
	if String(template.get_meta("cabin_kind", "")) != "compact_teardrop":
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
		triangles += _vertice_mesh_triangle_count(part.mesh)
		var material_key := StringName(part.get_meta(VERTICE_PREPARED_MATERIAL_KEY_META, &""))
		if material_key.is_empty() or not materials.has(material_key):
			return false
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			if not wheel_centres.has(centre):
				wheel_centres.append(centre)
		if bool(part.get_meta("vertice_midengine_lamp", false)):
			lamps += 1
		if bool(part.get_meta("vertice_midengine_damage_body", false)):
			if material_key != &"paint" or part.mesh.get_surface_count() != 1:
				return false
			damage_bodies += 1
	return meshes == VERTICE_EXPECTED_PREPARED_MESHES \
			and triangles == VERTICE_EXPECTED_PREPARED_TRIANGLES \
			and wheel_centres.size() == 4 \
			and lamps >= 4 \
			and damage_bodies >= 1


func _vertice_mesh_triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	return count


func _vertice_bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := StringName(part.get_meta(VERTICE_PREPARED_MATERIAL_KEY_META, &""))
		if materials.has(material_key):
			part.material_override = materials[material_key]
	for child in node.get_children():
		_vertice_bind_prepared_materials(child)


func _vertice_clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_vertice_clear_owner(child)
