extends "res://prototypes/living_cast/RearEngineCoupe.gd"

## Event-driven visual damage. Never rewrites vertices during normal driving.
var originals: Dictionary = {}
var damaged_vertices: Dictionary = {}
var broken_lamps := [false, false]
var impact_count := 0
var detached := false
var marks: Array[Node] = []

func _ready() -> void:
	super._ready()
	for node in get_children():
		if node is MeshInstance3D and node.material_override == paint:
			originals[node] = node.mesh

func apply_impact(hit: Vector3, inward: Vector3, speed: float) -> void:
	if speed < 2.5 or not is_finite(speed) or not hit.is_finite() or not inward.is_finite(): return
	impact_count += 1
	var depth := clampf((speed - 2.0) * 0.006, 0.012, 0.055)
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
			var weight := pow(maxf(0.0, 1.0 - world_point.distance_to(hit) / 0.85),2)
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
	for i in 2:
		var lamp := Vector3((-1.0 if i == 0 else 1.0)*0.67, 0.815, -1.80)
		if speed >= 6.0 and lamp.distance_to(hit) < 1.05:
			broken_lamps[i] = true
	# Never attach free-standing tubes using the coupe's roof equation: that
	# surface does not describe SUV, van or truck bodywork. Dents stay in the
	# authored mesh and leave no additional geometry outside the silhouette.
	update_lens_damage()

func add_mark(points: Array[Vector3], radius: float, material: Material) -> void:
	var start := get_child_count()
	tube(points,radius,material)
	for i in range(start,get_child_count()): marks.append(get_child(i))

func update_lens_damage() -> void:
	for node in get_children():
		if not node is MeshInstance3D: continue
		var index := 0 if node.position.x < 0 else 1
		if node.position.z < -1.65 and node.position.y > 0.75 and node.material_override in [materials["headlight"], materials.get("dead_led")]:
			node.material_override = mat("dead_led","25292b",0,0.8) if broken_lamps[index] else materials["headlight"]

func repair() -> void:
	for node in originals: node.mesh = originals[node]
	damaged_vertices.clear()
	broken_lamps = [false,false]
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
