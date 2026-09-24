@tool
extends "res://prototypes/living_cast/RearEngineCoupe.gd"

const COUPE_PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/CoupeDamagePreparedGeometry.scn"
const COUPE_PREPARED_GEOMETRY: PackedScene = preload("res://prototypes/living_cast/CoupeDamagePreparedGeometry.scn")
const COUPE_PREPARED_CONTRACT_VERSION := 1
const COUPE_PREPARED_MATERIAL_KEY_META := &"coupe_damage_material_key"
const COUPE_EXPECTED_PREPARED_SIGNATURE := 909733885
const COUPE_EXPECTED_PREPARED_MESHES := 38
const COUPE_EXPECTED_PREPARED_TRIANGLES := 61039

## Event-driven visual damage. Never rewrites vertices during normal driving.
var originals: Dictionary = {}
var damaged_vertices: Dictionary = {}
var broken_lamps := [false, false]
var broken_tail_lamps := [false, false]
var lamp_sources: Dictionary = {}
var burnt_materials: Dictionary = {}
var is_charred := false
var impact_count := 0
var detached := false
var marks: Array[Node] = []

func _init() -> void:
	if _coupe_is_exact_model() and get_child_count() == 0:
		var cache = load("res://cars/VehicleGeometryCache.gd")
		if cache and cache.should_defer_constructor(self):
			set_meta("vehicle_deferred_prewarm_shell", true)
			return
		if cache and not cache.restore(self):
			build()
			cache.capture(self)

func _ready() -> void:
	if get_meta("coupe_damage_geometry_source", &"") == &"prepared":
		_coupe_bind_prepared_materials(self)
	super._ready()
	for node in get_children():
		if node is MeshInstance3D and node.material_override == paint:
			originals[node] = node.mesh
	_capture_lamps(self)


func _coupe_is_exact_model() -> bool:
	return get_script() != null and get_script().resource_path.ends_with("/CoupeDamageModel.gd")


func vehicle_prepared_template_resource() -> PackedScene:
	if not _coupe_is_exact_model():
		return null
	return COUPE_PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	if _coupe_is_exact_model():
		_coupe_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _coupe_is_exact_model() and _coupe_prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"vehicle_wheel_clearance_signature": int(template.get_meta("vehicle_wheel_clearance_signature", 0)),
		&"vehicle_prepared_wheel_wells": true,
		&"coupe_damage_geometry_source": &"prepared",
		&"coupe_damage_prepared_geometry_signature": int(template.get_meta("coupe_damage_prepared_geometry_signature", 0)),
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_coupe_bind_prepared_materials(template)


func build() -> void:
	if not _coupe_is_exact_model():
		super.build()
		return
	if get_child_count() != 0:
		push_error("CoupeDamageModel.build refused duplicate geometry")
		return
	_coupe_prepare_runtime_materials()
	var prepared := vehicle_prepared_template_resource()
	var template := prepared.instantiate() as Node3D if prepared != null else null
	if template == null or not _coupe_prepared_template_is_acceptable(template):
		if template != null:
			template.free()
		set_meta("coupe_damage_geometry_source", &"procedural_fallback")
		build_coupe_procedural_source()
		return
	for metadata in template.get_meta_list():
		set_meta(metadata, template.get_meta(metadata))
	set_meta("vehicle_mesh_batched", true)
	set_meta("vehicle_prepared_wheel_wells", true)
	set_meta("coupe_damage_geometry_source", &"prepared")
	for child in template.get_children():
		_coupe_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_coupe_bind_prepared_materials(child)
	template.free()


func build_coupe_procedural_source() -> void:
	super.build()


func _coupe_prepare_runtime_materials() -> void:
	paint = mat("paint", "b83632", 0.25, 0.24)
	mat("rubber", "171b20", 0.0, 0.9)
	mat("trim", "30373d", 0.15, 0.45)
	var glass := mat("glass", "243a47", 0.35, 0.17)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("alloy", "b5bdc3", 0.72, 0.24)
	mat("headlight", "e6f0ed", 0.15, 0.16, 0.3)
	mat("brake", "cd6133", 0.2, 0.4)
	mat("rotor", "515963", 0.55, 0.55)
	mat("smoked_lens", "293b44", 0.35, 0.16)
	mat("tail", "eb3832", 0.1, 0.25, 0.65)


func _coupe_prepared_template_is_acceptable(template: Node3D) -> bool:
	if template == null:
		return false
	if int(template.get_meta("coupe_damage_prepared_contract_version", 0)) != COUPE_PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("coupe_damage_prepared_geometry_signature", 0)) != COUPE_EXPECTED_PREPARED_SIGNATURE:
		return false
	if int(template.get_meta("coupe_damage_prepared_meshes", 0)) != COUPE_EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("coupe_damage_prepared_triangles", 0)) != COUPE_EXPECTED_PREPARED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
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
		triangles += _coupe_mesh_triangle_count(part.mesh)
		var material_key := StringName(part.get_meta(COUPE_PREPARED_MATERIAL_KEY_META, &""))
		if material_key.is_empty() or not materials.has(material_key):
			return false
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			if not wheel_centres.has(centre):
				wheel_centres.append(centre)
		if bool(part.get_meta("coupe_damage_lamp", false)):
			lamps += 1
		if bool(part.get_meta("coupe_damage_body", false)):
			if material_key != &"paint" or part.mesh.get_surface_count() != 1:
				return false
			damage_bodies += 1
	return meshes == COUPE_EXPECTED_PREPARED_MESHES \
			and triangles == COUPE_EXPECTED_PREPARED_TRIANGLES \
			and wheel_centres.size() == 4 \
			and lamps >= 4 \
			and damage_bodies >= 1


func _coupe_mesh_triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	return count


func _coupe_bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := StringName(part.get_meta(COUPE_PREPARED_MATERIAL_KEY_META, &""))
		if materials.has(material_key):
			part.material_override = materials[material_key]
	for child in node.get_children():
		_coupe_bind_prepared_materials(child)


func _coupe_clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_coupe_clear_owner(child)

func _capture_lamps(parent: Node) -> void:
	for node in parent.get_children():
		if node is MeshInstance3D:
			var material: Material = node.material_override
			var front: bool = material != null and material == materials.get("headlight")
			var rear: bool = material != null and material in [materials.get("taillight"), materials.get("tail")]
			if front or rear:
				var pos := to_local(node.global_position)
				lamp_sources[node] = {"material":material,"position":pos,"front":front,"index":0 if pos.x < 0 else 1}
		_capture_lamps(node)

func apply_impact(hit: Vector3, inward: Vector3, speed: float) -> void:
	if speed < 2.5 or not is_finite(speed) or not hit.is_finite() or not inward.is_finite(): return
	impact_count += 1
	var depth := clampf((speed - 2.0) * 0.010, 0.018, 0.10)
	var direction := inward.normalized()
	var toward_center := Vector3(-hit.x,0,-hit.z).normalized()
	if direction.dot(toward_center) < 0.0: direction = -direction
	for node in originals:
		var source: Mesh = originals[node]
		var arrays := source.surface_get_arrays(0)
		var pristine: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var points: PackedVector3Array = damaged_vertices.get(node, pristine.duplicate())
		for i in points.size():
			var world_point: Vector3 = node.transform * pristine[i]
			var weight := pow(maxf(0.0, 1.0 - world_point.distance_to(hit) / 1.10),2)
			# Limit in model metres, not mesh-local coordinates (box parts may
			# carry scale). Accumulated contact cannot pull vertices into spikes.
			var displacement: Vector3 = node.basis * (points[i] - pristine[i])
			displacement = (displacement + direction * depth * weight).limit_length(0.14)
			points[i] = pristine[i] + node.basis.inverse() * displacement
		damaged_vertices[node] = points
		arrays[Mesh.ARRAY_VERTEX] = points
		var rebuilt := ArrayMesh.new()
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_tool := SurfaceTool.new()
		surface_tool.create_from(rebuilt, 0)
		surface_tool.generate_normals()
		node.mesh = surface_tool.commit()
	for node in lamp_sources:
		var data: Dictionary = lamp_sources[node]
		var lamp: Vector3 = data.position
		if speed >= 7.0 and Vector2(lamp.x,lamp.z).distance_to(Vector2(hit.x,hit.z)) < 0.9:
			if data.front: broken_lamps[data.index] = true
			else: broken_tail_lamps[data.index] = true
	# Never attach free-standing tubes using the coupe's roof equation: that
	# surface does not describe SUV, van or truck bodywork. Dents stay in the
	# authored mesh and leave no additional geometry outside the silhouette.
	update_lens_damage()

func add_mark(points: Array[Vector3], radius: float, material: Material) -> void:
	var start := get_child_count()
	tube(points,radius,material)
	for i in range(start,get_child_count()): marks.append(get_child(i))

func update_lens_damage() -> void:
	for node in lamp_sources:
		var data: Dictionary = lamp_sources[node]
		var broken: bool = broken_lamps[data.index] if data.front else broken_tail_lamps[data.index]
		node.material_override = mat("dead_led","171c20",0,0.95) if broken or is_charred else data.material

func char_body() -> void:
	if is_charred: return
	is_charred = true
	_char_meshes(self)
	broken_lamps = [true,true]
	broken_tail_lamps = [true,true]
	update_lens_damage()

func _char_meshes(parent: Node) -> void:
	for node in parent.get_children():
		if node is MeshInstance3D:
			burnt_materials[node] = node.material_override
			node.material_override = mat("charred_shell","17191a",0.05,1.0)
		_char_meshes(node)

func repair() -> void:
	for node in burnt_materials:
		if is_instance_valid(node): node.material_override = burnt_materials[node]
	burnt_materials.clear()
	is_charred = false
	for node in originals: node.mesh = originals[node]
	damaged_vertices.clear()
	broken_lamps = [false,false]
	broken_tail_lamps = [false,false]
	impact_count = 0
	detached = false
	for node in marks: node.queue_free()
	marks.clear()
	update_lens_damage()

func max_deformation() -> float:
	var maximum := 0.0
	for node in damaged_vertices:
		var pristine: PackedVector3Array = originals[node].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points: PackedVector3Array = damaged_vertices[node]
		for i in points.size(): maximum = maxf(maximum, (node.basis * (points[i] - pristine[i])).length())
	return maximum
