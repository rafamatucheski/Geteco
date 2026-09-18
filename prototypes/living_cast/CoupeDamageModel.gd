@tool
extends "res://prototypes/living_cast/RearEngineCoupe.gd"

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
	if get_script() != null and get_script().resource_path.ends_with("CoupeDamageModel.gd") and get_child_count() == 0:
		var cache = load("res://cars/VehicleGeometryCache.gd")
		if cache and not cache.restore(self):
			build()
			cache.capture(self)

func _ready() -> void:
	super._ready()
	for node in get_children():
		if node is MeshInstance3D and node.material_override == paint:
			originals[node] = node.mesh
	_capture_lamps(self)

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
