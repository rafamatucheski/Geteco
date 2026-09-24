extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"

## Vale Cross: compact AWD crossover with an arched roof and planted cladding.

const MAX_STEER_ANGLE := 0.58
const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/ValeCrossoverWheelWells.res"
const WHEEL_WELL_RESOURCE: Resource = preload(WHEEL_WELL_RESOURCE_PATH)



# The Vale has many symmetric trim and split-wheel pieces. Their transforms and
# materials stay per node, while the immutable primitive resources are shared.
# This preserves damage/lamp/wheel addressing without asking Godot to create and
# serialise 151 distinct primitive meshes for one cold presentation.
static var _shared_box_meshes: Dictionary = {}
static var _shared_cylinder_meshes: Dictionary = {}
static var _shared_sphere_mesh: SphereMesh
static var _baked_wheel_well_meshes: Dictionary = {}


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
	var final_mesh: Mesh = _baked_wheel_well_meshes.get(child_index, mesh)
	var node := MeshInstance3D.new()
	node.mesh = final_mesh
	node.position = position_value
	node.material_override = material
	if _baked_wheel_well_meshes.has(child_index):
		node.set_meta("vale_precarved_mesh", true)
		if final_mesh.get_surface_count() == 0:
			node.hide()
	add_child(node)
	return node


func build() -> void:
	_ensure_baked_wheel_well_meshes()
	vehicle_id = "vale_crossover"
	paint = mat("paint", "8e5b43", 0.28, 0.30)
	var rubber := mat("rubber", "171b1e", 0.0, 0.94)
	var trim := mat("trim", "2a3033", 0.18, 0.62)
	var glass := mat("glass", "284653", 0.34, 0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e1f5ff", 0.12, 0.16, 0.72)
	var tail := mat("taillight", "cf3531", 0.10, 0.22, 0.70)
	var alloy := mat("alloy", "bbc5c9", 0.76, 0.27)
	var amber := mat("amber", "f0a02b", 0.10, 0.22, 0.40)
	set_silhouette("arched_compact_crossover", "three_pane_fastback_suv")

	var axles: Array[float] = [-1.28, 1.30]
	sculpted_shell([
		Vector3(-2.18, 0.60, 0.68), Vector3(-1.94, 0.91, 0.91),
		Vector3(-0.90, 1.00, 1.03), Vector3(0.92, 0.99, 1.05),
		Vector3(2.00, 0.84, 0.88), Vector3(2.18, 0.58, 0.66),
	], axles, 0.43, 0.40, 0.065, 0.31)
	add_underbody(4.10, 1.72, 0.30)
	add_greenhouse(-1.15, 1.82, -0.66, 1.36, 1.04, 1.70, 0.92, 0.73, 3, 0.085)
	add_aero_mirrors(-0.92, 1.05, 1.10, Vector3(0.21, 0.10, 0.17))
	add_flush_handles([-0.28, 0.75], 1.005, 0.90, alloy)

	# Unpainted protection follows the rocker and wheel shoulders.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 1.005, 0.40, 0.0), Vector3(0.070, 0.14, 2.30), trim)
		for axle in axles:
			var arch: Array[Vector3] = []
			for step in 13:
				var angle := PI * float(step) / 12.0
				arch.append(Vector3(side * 1.006, 0.43 + sin(angle) * 0.43, axle + cos(angle) * 0.43))
			tube(arch, 0.027, trim)
			add_wheel(side * 0.98, 0.43, axle, 0.40, 0.245, 0.27, 7, "c1c9cc")
		box(Vector3(side * 0.68, 0.78, -2.17), Vector3(0.36, 0.09, 0.035), head)
		box(Vector3(side * 0.87, 0.69, -2.155), Vector3(0.07, 0.14, 0.035), amber)
		box(Vector3(side * 0.76, 0.91, 2.16), Vector3(0.22, 0.28, 0.035), tail)
		tube([Vector3(side * 0.60, 1.79, -0.26), Vector3(side * 0.60, 1.74, 1.34)], 0.021, alloy)
	box(Vector3(0.0, 0.47, -2.19), Vector3(0.82, 0.20, 0.045), trim)
	box(Vector3(0.0, 1.72, 1.48), Vector3(1.42, 0.045, 0.25), paint)

	# Install the authored, already-cut surfaces before VehicleGeometryCache
	# captures this cold model. No polygon subtraction is deferred to prewarm.
	_install_baked_wheel_wells()
	var wells := _wheel_wells()
	set_meta("vehicle_wheel_clearance_signature", _wells_signature(wells))


func _wheel_wells() -> Array[Dictionary]:
	var centers: Array[Vector3] = []
	for part in get_children():
		if part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	var min_z := INF
	var max_z := -INF
	for center in centers:
		min_z = minf(min_z, center.z)
		max_z = maxf(max_z, center.z)
	var front_limit := (min_z + max_z) * 0.5
	var wells: Array[Dictionary] = []
	for center in centers:
		var radius := 0.355
		var half_width := 0.0
		for part in get_children():
			if part is MeshInstance3D and part.get_meta("wheel_center", Vector3.INF) == center:
				radius = float(part.get_meta("wheel_radius", radius))
				var bounds: AABB = part.transform * part.mesh.get_aabb()
				half_width = maxf(half_width, maxf(absf(bounds.position.x - center.x), absf(bounds.end.x - center.x)))
		var angle := MAX_STEER_ANGLE if center.z < front_limit else 0.0
		var reach := radius * sin(angle) + half_width * cos(angle)
		wells.append({
			"center": center,
			"radius": sqrt(radius * radius + half_width * half_width) + 0.035,
			"inner": maxf(0.05, absf(center.x) - reach - 0.035),
		})
	return wells


func _install_baked_wheel_wells() -> void:
	_ensure_baked_wheel_well_meshes()
	for child_index in _baked_wheel_well_meshes:
		var part := get_child(int(child_index)) as MeshInstance3D
		assert(part != null)
		part.mesh = _baked_wheel_well_meshes[child_index]
		part.set_meta("vale_precarved_mesh", true)
		if part.mesh.get_surface_count() == 0:
			part.hide()


func _ensure_baked_wheel_well_meshes() -> void:
	if _baked_wheel_well_meshes.is_empty():
		assert(int(WHEEL_WELL_RESOURCE.get_meta("format_version", 0)) == 1)
		assert(String(WHEEL_WELL_RESOURCE.get_meta("model_id", "")) == "vale_crossover")
		var baked: Dictionary = WHEEL_WELL_RESOURCE.get_meta("meshes", {})
		assert(not baked.is_empty())
		for child_index in baked:
			var mesh := baked[child_index] as ArrayMesh
			assert(mesh != null)
			_baked_wheel_well_meshes[int(child_index)] = mesh

func _wells_signature(wells: Array[Dictionary]) -> int:
	var values: Array = []
	for well in wells:
		values.append([well.center, float(well.radius), float(well.inner)])
	return hash(values)
