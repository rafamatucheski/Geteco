extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Boreal plow: high forward cab, salt hopper and a wide articulated V blade.

const GEOMETRY_RESOURCE_PATH := "res://prototypes/living_cast/models/SnowPlowGeometry.scn"
const GEOMETRY_RESOURCE: PackedScene = preload(GEOMETRY_RESOURCE_PATH)
const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/SnowPlowWheelWells.res"
const MATERIAL_ROLE_META := &"snow_plow_material_role"
const EXPECTED_CONTRACT_VERSION := 1
const EXPECTED_VISUAL_SIGNATURE := 3643091624
const EXPECTED_MESHES := 46
const EXPECTED_TRIANGLES := 38642
const EXPECTED_MATERIAL_ROLES := [
	&"paint", &"rubber", &"trim", &"glass", &"headlight", &"taillight",
	&"plow_steel", &"plow_edge", &"road_salt", &"lightbar_mount",
	&"bar_left", &"bar_right", &"siren_speaker", &"rim_aeb5b9", &"rotor",
]

# The truck repeats utility-wheel and hard-surface primitives heavily. Geometry
# resources are immutable, so sharing them removes cold PrimitiveMesh creation
# without sharing materials or paint between vehicle instances.
static var _shared_box_meshes: Dictionary = {}
static var _shared_cylinder_meshes: Dictionary = {}
static var _shared_sphere_mesh: SphereMesh
static var _shared_torus_meshes: Dictionary = {}
static var _baked_wheel_well_meshes: Dictionary = {}


## Opt-in contract for resumable regional prewarm. SnowPlowGeometry already
## contains the mounted, flattened and batched wheel/body representation, so
## the cache can publish it without rebuilding or packing procedural geometry.
func vehicle_prepared_template_resource() -> PackedScene:
	return GEOMETRY_RESOURCE


func prepare_vehicle_prewarm_materials() -> void:
	_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(_template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"snow_plow_geometry_source": &"prepared",
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_bind_prepared_materials(template)


func box(pos: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := _shared_box_meshes.get(size_value) as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size_value
		_shared_box_meshes[size_value] = mesh
	return mesh_node(mesh, pos, material)


func cylinder(pos: Vector3, radius: float, depth: float, material: Material) -> MeshInstance3D:
	var key := Vector2(radius, depth)
	var mesh := _shared_cylinder_meshes.get(key) as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = depth
		mesh.radial_segments = 32
		_shared_cylinder_meshes[key] = mesh
	return mesh_node(mesh, pos, material)


func ell(pos: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	if _shared_sphere_mesh == null:
		_shared_sphere_mesh = SphereMesh.new()
		_shared_sphere_mesh.radius = 0.5
		_shared_sphere_mesh.height = 1.0
		_shared_sphere_mesh.radial_segments = 24
		_shared_sphere_mesh.rings = 12
	var node := mesh_node(_shared_sphere_mesh, pos, material)
	node.scale = size_value
	return node


func mesh_node(mesh: Mesh, position_value: Vector3, material: Material) -> MeshInstance3D:
	var child_index := get_child_count()
	var reusable_mesh := mesh
	if mesh is TorusMesh:
		var torus := mesh as TorusMesh
		var key := Vector4(torus.inner_radius, torus.outer_radius, torus.rings, torus.ring_segments)
		if not _shared_torus_meshes.has(key):
			_shared_torus_meshes[key] = torus
		reusable_mesh = _shared_torus_meshes[key]
	var final_mesh: Mesh = _baked_wheel_well_meshes.get(child_index, reusable_mesh)
	var node := MeshInstance3D.new()
	node.mesh = final_mesh
	node.position = position_value
	node.material_override = material
	if _baked_wheel_well_meshes.has(child_index):
		node.set_meta("snow_plow_precarved_mesh", true)
		if final_mesh.get_surface_count() == 0:
			node.hide()
	add_child(node)
	return node


func build() -> void:
	if get_child_count() != 0:
		push_error("SnowPlowModel.build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	var template := GEOMETRY_RESOURCE.instantiate() as Node3D
	if template == null or not _prepared_template_is_acceptable(template):
		if template != null:
			template.free()
		set_meta("snow_plow_geometry_source", &"procedural_fallback")
		_build_procedural_geometry()
		return
	for metadata in template.get_meta_list():
		set_meta(metadata, template.get_meta(metadata))
	set_meta("snow_plow_geometry_source", &"prepared")
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_prepared_materials(child)
	template.free()


func _prepare_runtime_materials() -> void:
	vehicle_id = "snow_plow_truck"
	materials.clear()
	paint = null
	paint = mat("paint", "e47a22", 0.28, 0.34)
	mat("rubber", "161a1d", 0.0, 0.94)
	mat("trim", "2b3033", 0.34, 0.46)
	var glass := mat("glass", "2a4654", 0.32, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "e9f6ff", 0.12, 0.18, 0.78)
	mat("taillight", "c9342d", 0.10, 0.22, 0.65)
	mat("plow_steel", "d79a25", 0.58, 0.34)
	mat("plow_edge", "596168", 0.78, 0.28)
	mat("road_salt", "e7edf0", 0.0, 0.92)
	mat("amber_beacon", "ffb11f", 0.10, 0.12, 1.15)
	mat("lightbar_mount", "1a1d20", 0.5, 0.4)
	mat("bar_left", "ffb11f", 0.1, 0.1, 0.95)
	mat("bar_right", "ffd45c", 0.1, 0.1, 0.95)
	mat("siren_speaker", "2f3640", 0.6, 0.3)
	mat("rim_aeb5b9", "aeb5b9", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)


func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("format_version", 0)) != EXPECTED_CONTRACT_VERSION:
		return false
	if String(template.get_meta("model_id", "")) != "snow_plow_truck":
		return false
	if int(template.get_meta("visual_signature", 0)) != EXPECTED_VISUAL_SIGNATURE:
		return false
	if int(template.get_meta("mesh_count", 0)) != EXPECTED_MESHES:
		return false
	if int(template.get_meta("triangle_count", 0)) != EXPECTED_TRIANGLES:
		return false
	if not bool(template.get_meta("vehicle_mesh_batched", false)):
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
		return false
	var recorded_counts_value = template.get_meta("material_role_counts", {})
	if not recorded_counts_value is Dictionary:
		return false
	var recorded_counts := recorded_counts_value as Dictionary
	var actual_counts: Dictionary = {}
	var wheel_flags: Dictionary = {}
	var meshes := 0
	for child in template.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			return false
		meshes += 1
		var role := StringName(part.get_meta(MATERIAL_ROLE_META, &""))
		if role == &"" or not materials.has(role):
			return false
		actual_counts[role] = int(actual_counts.get(role, 0)) + 1
		if part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			var flags := int(wheel_flags.get(center, 0))
			if bool(part.get_meta("wheel_spins", false)):
				flags |= 1
			else:
				flags |= 2
			wheel_flags[center] = flags
	if meshes != EXPECTED_MESHES or actual_counts.size() != EXPECTED_MATERIAL_ROLES.size():
		return false
	for role_value in EXPECTED_MATERIAL_ROLES:
		var role := StringName(role_value)
		var actual := int(actual_counts.get(role, 0))
		if actual <= 0 or actual != _recorded_role_count(recorded_counts, role):
			return false
	if int(actual_counts.get(&"plow_steel", 0)) <= 0 or int(actual_counts.get(&"plow_edge", 0)) <= 0:
		return false
	if int(actual_counts.get(&"road_salt", 0)) <= 0 or int(actual_counts.get(&"paint", 0)) <= 0:
		return false
	if wheel_flags.size() != 6:
		return false
	for center in wheel_flags:
		if int(wheel_flags[center]) != 3:
			return false
	return true


func _recorded_role_count(recorded_counts: Dictionary, role: StringName) -> int:
	if recorded_counts.has(role):
		return int(recorded_counts[role])
	return int(recorded_counts.get(String(role), 0))


func _bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var role := StringName(part.get_meta(MATERIAL_ROLE_META, &""))
		if role != &"" and materials.has(role):
			part.material_override = materials[role]
	for child in node.get_children():
		_bind_prepared_materials(child)


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


# Kept as the exact authoring source for rebuilding SnowPlowGeometry.scn when
# the silhouette changes. Runtime construction intentionally uses build().
func _build_procedural_geometry(install_baked_wells := true) -> void:
	if install_baked_wells:
		_ensure_baked_wheel_well_meshes()
	vehicle_id = "snow_plow_truck"
	paint = mat("paint", "e47a22", 0.28, 0.34)
	var rubber := mat("rubber", "161a1d", 0.0, 0.94)
	var trim := mat("trim", "2b3033", 0.34, 0.46)
	var glass := mat("glass", "2a4654", 0.32, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e9f6ff", 0.12, 0.18, 0.78)
	var tail := mat("taillight", "c9342d", 0.10, 0.22, 0.65)
	var blade := mat("plow_steel", "d79a25", 0.58, 0.34)
	var blade_edge := mat("plow_edge", "596168", 0.78, 0.28)
	var salt := mat("road_salt", "e7edf0", 0.0, 0.92)
	var amber := mat("amber_beacon", "ffb11f", 0.10, 0.12, 1.15)
	set_silhouette("forward_cab_v_plow_hopper", "single_high_cab")

	var front_axle: Array[float] = [-2.15]
	sculpted_shell([
		Vector3(-3.28, 0.76, 0.76), Vector3(-3.02, 1.08, 1.14),
		Vector3(-1.30, 1.13, 1.22), Vector3(-0.88, 0.95, 1.04),
	], front_axle, 0.46, 0.46, 0.045, 0.30)
	add_underbody(6.05, 1.90, 0.31)
	add_greenhouse(-2.98, -1.06, -2.74, -1.38, 1.20, 2.13, 1.03, 0.88, 1, 0.055)
	add_aero_mirrors(-2.65, 1.30, 1.50, Vector3(0.26, 0.34, 0.12))
	add_flush_handles([-1.73], 1.12, 1.03, trim)

	# Tapered salt hopper; it is vehicle volume, not a decorative roof prop.
	surface([Vector3(-1.03, 0.72, -0.55), Vector3(-0.74, 2.00, -0.30), Vector3(-0.74, 2.00, 2.72), Vector3(-1.03, 0.72, 2.92)], paint)
	surface([Vector3(1.03, 0.72, 2.92), Vector3(0.74, 2.00, 2.72), Vector3(0.74, 2.00, -0.30), Vector3(1.03, 0.72, -0.55)], paint)
	surface([Vector3(-1.03, 0.72, -0.55), Vector3(1.03, 0.72, -0.55), Vector3(0.74, 2.00, -0.30), Vector3(-0.74, 2.00, -0.30)], paint)
	surface([Vector3(1.03, 0.72, 2.92), Vector3(-1.03, 0.72, 2.92), Vector3(-0.74, 2.00, 2.72), Vector3(0.74, 2.00, 2.72)], paint)
	box(Vector3(0.0, 2.02, 1.20), Vector3(1.50, 0.06, 3.02), trim)
	box(Vector3(0.0, 2.06, 1.20), Vector3(1.24, 0.03, 2.76), salt)

	# Wide V blade projects ahead of the cab with real depth and braces.
	surface([
		Vector3(-1.72, 0.14, -3.72), Vector3(0.0, 0.14, -4.10),
		Vector3(0.0, 1.05, -4.10), Vector3(-1.72, 0.94, -3.72),
	], blade)
	surface([
		Vector3(0.0, 0.14, -4.10), Vector3(1.72, 0.14, -3.72),
		Vector3(1.72, 0.94, -3.72), Vector3(0.0, 1.05, -4.10),
	], blade)
	for side in [-1.0, 1.0]:
		tube([Vector3(side * 0.65, 0.52, -3.12), Vector3(side * 0.96, 0.55, -3.82)], 0.045, trim)
		box(Vector3(side * 1.24, 0.18, -3.83), Vector3(0.92, 0.11, 0.10), blade_edge)
		box(Vector3(side * 0.78, 0.86, -3.28), Vector3(0.34, 0.18, 0.045), head)
		box(Vector3(side * 0.86, 0.67, 2.93), Vector3(0.22, 0.14, 0.045), tail)

	add_lightbar(2.25, -1.82, Color("ffb11f"), Color("ffd45c"), 1.55)
	var axles: Array[float] = [-2.15, 1.60, 2.32]
	add_axles(axles, 1.04, 0.46, 0.46, 0.28, 0.27, 7, "aeb5b9")
	var wheel_well_resource := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	set_meta(
		"vehicle_wheel_clearance_signature",
		int(wheel_well_resource.get_meta("wheel_clearance_signature", 0))
	)


func _ensure_baked_wheel_well_meshes() -> void:
	if not _baked_wheel_well_meshes.is_empty():
		return
	var wheel_well_resource := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	assert(int(wheel_well_resource.get_meta("format_version", 0)) == 1)
	assert(String(wheel_well_resource.get_meta("model_id", "")) == "snow_plow_truck")
	var baked: Dictionary = wheel_well_resource.get_meta("meshes", {})
	assert(not baked.is_empty())
	for child_index in baked:
		var mesh := baked[child_index] as ArrayMesh
		assert(mesh != null)
		_baked_wheel_well_meshes[int(child_index)] = mesh
