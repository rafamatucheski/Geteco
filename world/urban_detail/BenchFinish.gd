extends RefCounted
## Shared furniture geometry. Dimensions describe the existing physical envelope;
## callers retain collisions, seat targets and their established orientation.
static var _meshes: Dictionary = {}
static var _materials: Array[StandardMaterial3D] = []

static func create(width: float, depth: float, seat_top: float, back_top := 0.0, wood := Color("806044"), frame := Color("343d39")) -> MeshInstance3D:
	var key := str([width, depth, seat_top, back_top, wood, frame])
	if not _meshes.has(key):
		var boards := SurfaceTool.new()
		boards.begin(Mesh.PRIMITIVE_TRIANGLES)
		var supports := SurfaceTool.new()
		supports.begin(Mesh.PRIMITIVE_TRIANGLES)
		_build(boards, supports, width, depth, seat_top, back_top, wood, frame)
		var mesh := boards.commit()
		supports.commit(mesh)
		if _materials.is_empty():
			for kind in ["wood", "metal"]:
				var material := StandardMaterial3D.new()
				material.vertex_color_use_as_albedo = true
				material.roughness = .85 if kind == "wood" else .58
				material.metallic = .0 if kind == "wood" else .35
				material.albedo_texture = preload("res://world/places/ShopInteriorMaterials.gd").texture("wood" if kind == "wood" else "plaster")
				material.uv1_triplanar = true
				material.uv1_scale = Vector3.ONE * 1.4
				_materials.append(material)
		for index in 2: mesh.surface_set_material(index, _materials[index])
		_meshes[key] = mesh
	var result := MeshInstance3D.new()
	result.name = "FinishedBench"
	result.mesh = _meshes[key]
	result.set_meta("bench_envelope", Vector3(width, maxf(seat_top, back_top), depth))
	result.set_meta("seat_top", seat_top)
	return result

static func append_to(surface: SurfaceTool, width: float, depth: float, seat_top: float, back_top: float) -> void:
	_build(surface, surface, width, depth, seat_top, back_top, Color("806044"), Color("343d39"))

static func add_collision(bench: MeshInstance3D, label: String) -> void:
	var size: Vector3 = bench.get_meta("bench_envelope")
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y*.5
	body.add_child(shape)
	bench.add_child(body)

static func _build(wood_surface: SurfaceTool, metal_surface: SurfaceTool, width: float, depth: float, seat_top: float, back_top: float, wood: Color, frame: Color) -> void:
	var plank := minf(.07, seat_top * .16)
	for i in 4:
		_box(wood_surface, Vector3(0, seat_top-plank*.5, -depth*.375+i*depth*.25), Vector3(width, plank, depth*.23), wood.lightened((i%3)*.025))
	for side in [-1.0, 1.0]:
		var x: float = side * (width*.5-minf(.18, width*.14))
		_box(metal_surface, Vector3(x, (seat_top-plank)*.5, 0), Vector3(.085, seat_top-plank, depth*.70), frame)
		_box(metal_surface, Vector3(x, .025, 0), Vector3(.18, .05, depth*.88), frame)
		_box(metal_surface, Vector3(x, seat_top-plank-.025, 0), Vector3(.10, .05, depth*.94), frame)
		if back_top > seat_top+.20:
			_box(metal_surface, Vector3(x, (back_top+.1)*.5, -depth*.44), Vector3(.07, back_top-.10, minf(.07, depth*.08)), frame)
			var arm_y := minf(back_top-.16, seat_top+.20)
			_box(metal_surface, Vector3(x, arm_y, 0), Vector3(.075, .055, depth*.84), frame)
			_box(metal_surface, Vector3(x, (arm_y+seat_top)*.5, depth*.31), Vector3(.06, arm_y-seat_top, .06), frame)
	if back_top > seat_top+.20:
		var back_bottom := seat_top+.06
		var step := (back_top-back_bottom)/3.0
		for i in 3:
			_box(wood_surface, Vector3(0, back_bottom+step*(i+.5), -depth*.42), Vector3(width, step*.84, minf(.065, depth*.12)), wood.lightened(i*.02))

static func _box(surface: SurfaceTool, point: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	for index in arrays[Mesh.ARRAY_INDEX]:
		surface.set_color(color)
		surface.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
		surface.set_uv(arrays[Mesh.ARRAY_TEX_UV][index])
		surface.add_vertex(arrays[Mesh.ARRAY_VERTEX][index]+point)
