extends RefCounted
## Cosmetic history derived from the persisted identity. No health changes or frame work.
const CIVILIAN := ["union_sedan", "sedan_classic", "metro_hatch", "station_wagon", "nordic_estate", "courier_van", "polar_van", "ranch_single", "ranch_pickup", "lumber_pickup_4x4", "atlas_crew_pickup", "sertao_trail_pickup", "sport_estate", "summit_suv", "vale_crossover"]
# Bed interior: floor height, center Z, usable width, usable length (model coordinates).
const BEDS := {
	"ranch_single": [.605, 1.35, 1.50, 1.70],
	"ranch_pickup": [.605, 1.35, 1.50, 1.70],
	"lumber_pickup_4x4": [.605, 1.35, 1.50, 1.70],
	"atlas_crew_pickup": [.745, 1.80, 1.60, 1.48],
	"sertao_trail_pickup": [.715, 1.57, 1.44, 1.30],
}
static var _textures: Dictionary = {}
static var _loads: Dictionary = {}
static var _cargo_material: StandardMaterial3D
static var _open_beds: Dictionary = {}
static var enabled := true # Process-local A/B control for the rendered measurement harness.

static func profile(id: String, identity: String) -> Vector2i:
	if id not in CIVILIAN or identity.is_empty(): return Vector2i.ZERO
	var value := (id + ":usage:" + identity).hash()
	var roll := value % 10
	return Vector2i(0 if roll < 4 else (1 if roll < 8 else 2), (int(float(value) / 10.0) % 4) if id in BEDS else 0)

static func apply(model: Node3D, id: String, identity: String, paints: Array[StandardMaterial3D]) -> void:
	if not enabled: return
	var choice := profile(id, identity)
	if id in ["atlas_crew_pickup", "sertao_trail_pickup"]: _open_bed(model, id)
	if model.get_meta("usage_profile", Vector2i(-1, -1)) == choice: return
	model.set_meta("usage_profile", choice)
	for paint in paints:
		if not paint.has_meta("usage_original"):
			paint.set_meta("usage_original", [paint.roughness, paint.clearcoat])
		var original: Array = paint.get_meta("usage_original")
		paint.detail_enabled = choice.x > 0
		paint.roughness = maxf(float(original[0]), .82 if choice.x == 2 else .7) if choice.x > 0 else float(original[0])
		paint.clearcoat = float(original[1]) * (.25 if choice.x == 2 else .6) if choice.x > 0 else float(original[1])
		if choice.x > 0:
			paint.detail_albedo = _texture(choice.x)
			paint.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			paint.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			paint.uv2_triplanar = true
			paint.uv2_scale = Vector3(.65, .65, .65)
	var old := model.get_node_or_null("BedLoad")
	if old != null: old.free()
	if choice.y == 0: return
	var cargo := MeshInstance3D.new()
	cargo.name = "BedLoad"
	cargo.mesh = _load_mesh(choice.y)
	cargo.material_override = _material()
	var bed: Array = BEDS[id]
	cargo.position = Vector3(0, float(bed[0]), float(bed[1]))
	cargo.scale = Vector3(float(bed[2]) / 1.6, 1, float(bed[3]) / 1.7)
	model.add_child(cargo)

static func _texture(level: int) -> ImageTexture:
	if _textures.has(level): return _textures[level]
	var image := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var noise := FastNoiseLite.new()
	noise.seed = 7123
	noise.frequency = .075
	var rng := RandomNumberGenerator.new()
	rng.seed = 8137
	for y in 128:
		for x in 128:
			var n := noise.get_noise_2d(x, y)
			var dust := Color("8b806a")
			dust.a = smoothstep(-.15, .5, n) * (.07 if level == 1 else .14)
			if level == 2 and n > .50:
				dust = Color("70412c").lerp(Color("a3734e"), rng.randf() * .6)
				dust.a = smoothstep(.50, .65, n) * .86
			image.set_pixel(x, y, dust)
	# Short, irregular scuffs; most of the factory paint stays exposed.
	for scratch in (14 if level == 1 else 30):
		var start := Vector2i(rng.randi_range(2, 110), rng.randi_range(2, 125))
		for step in rng.randi_range(3, 15):
			var at := start + Vector2i(step, floori(float(step) / 7.0))
			image.set_pixel(at.x, at.y, Color(.48, .46, .41, rng.randf_range(.3, .72)))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[level] = texture
	return texture

static func _material() -> StandardMaterial3D:
	if _cargo_material == null:
		_cargo_material = StandardMaterial3D.new()
		_cargo_material.vertex_color_use_as_albedo = true
		_cargo_material.roughness = .95
	return _cargo_material

static func _box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in arrays[Mesh.ARRAY_INDEX]:
		tool.set_normal(normals[index])
		tool.set_color(color)
		tool.add_vertex(vertices[index] + center)

static func _crate(tool: SurfaceTool, center: Vector3, size: Vector3) -> void:
	_box(tool, center, size, Color("775337"))
	for x in [-1, 1]:
		for z in [-1, 1]:
			_box(tool, center + Vector3(x * (size.x * .5 - .04), 0, z * size.z * .5), Vector3(.075, size.y, .035), Color("b08a58"))
	for y in [-.3, 0, .3]:
		for z in [-1, 1]:
			_box(tool, center + Vector3(0, y * size.y, z * (size.z * .5 + .022)), Vector3(size.x, .016, .009), Color("473624"))
	for x in [-.28, 0, .28]:
		_box(tool, center + Vector3(x * size.x, size.y * .5 + .005, 0), Vector3(.012, .008, size.z), Color("473624"))

static func _load_mesh(kind: int) -> ArrayMesh:
	if _loads.has(kind): return _loads[kind]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		1:
			_crate(tool, Vector3(-.36, .23, -.30), Vector3(.58, .46, .58))
			_crate(tool, Vector3(.32, .18, .18), Vector3(.55, .36, .65))
			_crate(tool, Vector3(-.33, .14, .38), Vector3(.50, .28, .48))
		2:
			for layer in 3:
				for plank in 4:
					_box(tool, Vector3(-.40 + plank * .23, .045 + layer * .09, (plank % 2) * .06), Vector3(.20, .08, 1.38), Color("a78250").darkened(layer * .06 + plank * .025))
			for z in [-.44, .44]:
				_box(tool, Vector3(-.055, .278, z), Vector3(.93, .025, .055), Color("343d38"))
				for x in [-.52, .41]: _box(tool, Vector3(x, .14, z), Vector3(.025, .28, .055), Color("343d38"))
		3:
			_crate(tool, Vector3(-.38, .20, -.25), Vector3(.52, .40, .58))
			# Closed metal toolbox with lid, latches and handle.
			_box(tool, Vector3(.30, .16, .20), Vector3(.66, .32, .43), Color("435c62"))
			_box(tool, Vector3(.30, .33, .20), Vector3(.69, .04, .46), Color("617778"))
			for x in [.08, .52]: _box(tool, Vector3(x, .25, .433), Vector3(.06, .12, .025), Color("b5aea0"))
			_box(tool, Vector3(.30, .39, .20), Vector3(.22, .04, .05), Color("303532"))
			for x in [.20, .40]: _box(tool, Vector3(x, .365, .20), Vector3(.03, .05, .05), Color("303532"))
	tool.index()
	var mesh := tool.commit()
	_loads[kind] = mesh
	return mesh

static func _open_bed(model: Node3D, id: String) -> void:
	if model.has_meta("usage_open_bed"): return
	model.set_meta("usage_open_bed", true)
	# These exports include a solid body cap above the authored liner. Open only
	# its rear upward faces, keeping the separate bed walls, tailgate and cabin.
	var body := model.get_child(0) as MeshInstance3D
	if body == null or not body.mesh is ArrayMesh: return
	if _open_beds.has(id):
		body.mesh = _open_beds[id]
		return
	var bed: Array = BEDS[id]
	var front := float(bed[1]) - float(bed[3]) * .5
	var source := body.mesh
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if indices.is_empty():
		for i in vertices.size(): indices.append(i)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for offset in range(0, indices.size(), 3):
		var polygon: Array = []
		for j in 3:
			var index := indices[offset + j]
			polygon.append([vertices[index], normals[index], uv[index] if not uv.is_empty() else Vector2.ZERO])
		if normals[indices[offset]].y > .7:
			var clipped: Array = []
			for j in polygon.size():
				var a: Array = polygon[j]
				var b: Array = polygon[(j + 1) % polygon.size()]
				var inside_a: bool = a[0].z <= front
				var inside_b: bool = b[0].z <= front
				if inside_a: clipped.append(a)
				if inside_a != inside_b:
					var weight: float = (front - a[0].z) / (b[0].z - a[0].z)
					clipped.append([a[0].lerp(b[0], weight), a[1].lerp(b[1], weight).normalized(), a[2].lerp(b[2], weight)])
			polygon = clipped
		for j in range(1, polygon.size() - 1):
			for index in [0, j, j + 1]:
				var vertex: Array = polygon[index]
				tool.set_normal(vertex[1])
				tool.set_uv(vertex[2])
				tool.add_vertex(vertex[0])
	tool.index()
	var mesh := tool.commit()
	mesh.surface_set_material(0, source.surface_get_material(0))
	_open_beds[id] = mesh
	body.mesh = mesh
