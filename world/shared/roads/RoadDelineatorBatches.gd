extends RefCounted
## Passive roadside reflectors: opaque geometry receives actual headlights.
## No emissive shader, extra light, collision or frame callback.
const CELL := 64.0
static var _parts: Array[Dictionary] = []

## Devolve, por célula, as poses e os lotes das peças (mesma ordem de _parts) para quem registra
## os balizadores como quebráveis (serra, MountainRoadside3D); o deserto ignora o retorno.
static func build(parent: Node3D, transforms: Array[Transform3D], prefix: String) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	if transforms.is_empty(): return built
	_prepare()
	var cells: Dictionary = {}
	for transform in transforms:
		var key := Vector2i(floori(transform.origin.x / CELL), floori(transform.origin.z / CELL))
		if not cells.has(key): cells[key] = []
		cells[key].append(transform)
	for key: Vector2i in cells:
		var poses: Array = cells[key]
		var batches: Array[MultiMesh] = []
		var offsets: Array[Vector3] = []
		for part_index in _parts.size():
			var part: Dictionary = _parts[part_index]
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.mesh = part.mesh
			batch.instance_count = poses.size()
			for i in poses.size():
				var pose: Transform3D = poses[i]
				batch.set_instance_transform(i, pose.translated_local(part.offset))
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_%d_%d_%d" % [prefix, key.x, key.y, part_index]
			instance.multimesh = batch
			instance.material_override = part.material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Small passive markers disappear into terrain naturally at this range.
			instance.visibility_range_end = 300.0
			instance.visibility_range_end_margin = 24.0
			parent.add_child(instance)
			batches.append(batch)
			offsets.append(part.offset)
		built.append({"poses": poses, "batches": batches, "offsets": offsets})
	return built


static func _prepare() -> void:
	if not _parts.is_empty(): return
	for definition in [
		[Vector3(0.14, 0.9, 0.10), Vector3(0, 0.45, 0), Color("ddd9c7")],
		[Vector3(0.15, 0.23, 0.112), Vector3(0, 0.72, 0), Color("30383a")],
		[Vector3(0.075, 0.09, 0.124), Vector3(0, 0.73, 0), Color("e5ac4c")],
	]:
		var mesh := BoxMesh.new()
		mesh.size = definition[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = definition[2]
		material.roughness = 0.65
		material.metallic_specular = 0.28
		_parts.append({"mesh": mesh, "material": material, "offset": definition[1]})
