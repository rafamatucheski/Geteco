extends SceneTree
## Prepara um carro de IA (uma malha só, um material) para o formato da frota:
## carroceria + 4 rodas soltas com `wheel_center`, frente em -Z, metros, chão em y=0.
## Uso (a partir da raiz do projeto):
##   Godot --headless --path . --script res://tools/fleet_ingest/ingest_glb_car.gd -- \
##     --glb=<arquivo.glb> --albedo=res://assets/fleet/incoming/mirage_albedo.png \
##     --out=res://assets/fleet/incoming/mirage_test.scn --length=4.2 --front=-x
## `--front` diz para onde o GLB aponta a frente (-x, +x, -z ou +z). As rodas são as
## quatro componentes soltas (pneu) da malha, com as peças menores coladas a elas (calota).
var args := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg: args[arg.get_slice("=",0).trim_prefix("--")] = arg.get_slice("=",1)
	run.call_deferred()

func fail(message: String) -> void:
	push_error("INGEST " + message)
	quit(1)

func run() -> void:
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(str(args.get("glb","")), state) != OK: return fail("GLB não abriu")
	var scene := doc.generate_scene(state)
	var source: MeshInstance3D = null
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		source = node
		break
	if source == null: return fail("sem malha")
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var world: Transform3D = source.global_transform
	var raw_min := Vector3(INF, INF, INF)
	var raw_max := Vector3(-INF, -INF, -INF)
	for i in positions.size():
		positions[i] = world * positions[i]
		raw_min = raw_min.min(positions[i])
		raw_max = raw_max.max(positions[i])
	print("INGEST bruto min=", raw_min, " max=", raw_max, " tris=", indices.size() / 3)

	# 1) Orientação: frente para -Z; escala pelo comprimento; chão em y = 0.
	var yaw := {"-z": 0.0, "+z": PI, "-x": -PI * 0.5, "+x": PI * 0.5}.get(str(args.get("front", "-x")), 0.0) as float
	var basis := Basis(Vector3.UP, yaw)
	var extent := raw_max - raw_min
	var raw_length := maxf(extent.x, extent.z)
	var scale_factor := float(args.get("length", 4.2)) / raw_length
	# 2) Componentes soltos (soldando vértices repetidos pelas costuras de UV).
	var weld := {}
	var canonical := PackedInt32Array()
	canonical.resize(positions.size())
	for i in positions.size():
		var key := Vector3i((positions[i] * 100000.0).round())
		if not weld.has(key): weld[key] = i
		canonical[i] = weld[key]
	var parent := PackedInt32Array()
	parent.resize(positions.size())
	for i in parent.size(): parent[i] = i
	for t in range(0, indices.size(), 3):
		var a := _find(parent, canonical[indices[t]])
		for k in [1, 2]:
			var b := _find(parent, canonical[indices[t + k]])
			if a != b: parent[b] = a
	var groups := {}
	for t in range(0, indices.size(), 3):
		var root := _find(parent, canonical[indices[t]])
		if not groups.has(root): groups[root] = []
		groups[root].append(t)
	var comps: Array = []
	for root in groups:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for t in groups[root]:
			for k in 3:
				lo = lo.min(positions[indices[t + k]])
				hi = hi.max(positions[indices[t + k]])
		comps.append({"tris": groups[root], "lo": lo, "hi": hi, "size": hi - lo, "center": (lo + hi) * 0.5})
	# 3) Pneus: componentes cilíndricos (altura ≈ comprimento, fino no eixo do eixo).
	var axle := "z" if extent.x > extent.z else "x"
	var tires: Array = []
	for c in comps:
		var s: Vector3 = c.size
		var thin := s.z if axle == "z" else s.x
		var long_side := s.x if axle == "z" else s.z
		if c.tris.size() > 150 and absf(s.y - long_side) < 0.2 * s.y and thin < 0.6 * s.y and s.y < 0.5 * maxf(extent.x, extent.z):
			tires.append(c)
	print("INGEST componentes=", comps.size(), " pneus=", tires.size())
	if "--verbose" in OS.get_cmdline_user_args():
		for c in comps: if c.tris.size() > 40: print("  comp tris=", c.tris.size(), " centro=", c.center, " tamanho=", c.size)
	if tires.size() != 4: return fail("esperava 4 pneus, achei %d" % tires.size())
	var wheel_parts: Array = [[], [], [], []]
	var assigned := {}
	for w in 4:
		var tc: Vector3 = tires[w].center
		for c in comps:
			var cc: Vector3 = c.center
			var d_plane := Vector2(cc.x - tc.x, cc.y - tc.y).length() if axle == "z" else Vector2(cc.z - tc.z, cc.y - tc.y).length()
			var d_axle := absf(cc.z - tc.z) if axle == "z" else absf(cc.x - tc.x)
			if d_plane < 0.6 * tires[w].size.y and d_axle < 0.5 * tires[w].size.y and c.size.y < 1.3 * tires[w].size.y:
				if not assigned.has(c):
					assigned[c] = w
					wheel_parts[w].append(c)
	# 4) Malhas transformadas.
	var lowest := INF
	for c in tires: lowest = minf(lowest, c.lo.y)
	var offset := Vector3(0, -lowest * scale_factor, 0)
	var texture: Texture2D = null
	var image := Image.load_from_file(ProjectSettings.globalize_path(str(args.get("albedo", ""))))
	if image != null:
		image.generate_mipmaps()
		texture = ImageTexture.create_from_image(image)
	var paint := StandardMaterial3D.new()
	paint.resource_name = "paint"
	paint.albedo_texture = texture
	paint.roughness = 0.55
	paint.metallic = 0.1
	var rubber := StandardMaterial3D.new()
	rubber.resource_name = "wheel"
	rubber.albedo_texture = texture
	rubber.roughness = 0.75
	rubber.metallic = 0.05
	var root_node := Node3D.new()
	root_node.name = "MirageTest"
	# Faróis e lanternas: peças pequenas nas pontas. Ficam fora da carroceria para a tinta
	# do jogo não pintá-las e, depois, poderem acender.
	var lamp_tris: Array = []
	var body_tris: Array = []
	var long_axis_is_x := extent.x > extent.z
	for c in comps:
		if assigned.has(c): continue
		var along: float = absf(c.center.x if long_axis_is_x else c.center.z)
		if c.tris.size() < 250 and along > 0.38 * raw_length: lamp_tris.append_array(c.tris)
		else: body_tris.append_array(c.tris)
	var transform_point := func(p: Vector3) -> Vector3: return basis * p * scale_factor + offset
	var body := _mesh_node("Body", body_tris, indices, positions, normals, uvs, basis, transform_point, paint)
	root_node.add_child(body)
	var lamp_material := rubber.duplicate() as StandardMaterial3D
	lamp_material.resource_name = "lamp"
	lamp_material.roughness = 0.25
	if not lamp_tris.is_empty():
		root_node.add_child(_mesh_node("Lamps", lamp_tris, indices, positions, normals, uvs, basis, transform_point, lamp_material))
	print("INGEST corpo=", body_tris.size(), " lâmpadas=", lamp_tris.size(), " tris")
	var names := ["Wheel_A", "Wheel_B", "Wheel_C", "Wheel_D"]
	for w in 4:
		var tris_w: Array = []
		for c in wheel_parts[w]: tris_w.append_array(c.tris)
		var node := _mesh_node(names[w], tris_w, indices, positions, normals, uvs, basis, transform_point, rubber)
		var center: Vector3 = transform_point.call(tires[w].center)
		node.set_meta("wheel_center", center)
		root_node.add_child(node)
		print("INGEST roda ", w, " centro=", center, " raio=", tires[w].size.y * scale_factor * 0.5, " tris=", tris_w.size())
	for child in root_node.get_children(): child.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	var out := str(args.get("out", "res://assets/fleet/incoming/ingest_test.scn"))
	if ResourceSaver.save(packed, out) != OK: return fail("não salvou " + out)
	var total := 0
	var lo_all := Vector3(INF, INF, INF)
	var hi_all := Vector3(-INF, -INF, -INF)
	for child in root_node.get_children():
		var mesh := (child as MeshInstance3D).mesh
		total += (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var box := mesh.get_aabb()
		lo_all = lo_all.min(box.position)
		hi_all = hi_all.max(box.end)
	print("INGEST salvo ", out, " peças=", root_node.get_child_count(), " triângulos=", total, " caixa=", lo_all, " → ", hi_all, " tamanho=", hi_all - lo_all)
	quit(0)

func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func _mesh_node(node_name: String, tris: Array, indices: PackedInt32Array, positions: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, basis: Basis, transform_point: Callable, material: Material) -> MeshInstance3D:
	var remap := {}
	var out_positions := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_indices := PackedInt32Array()
	for t in tris:
		for k in 3:
			var source_index := indices[t + k]
			if not remap.has(source_index):
				remap[source_index] = out_positions.size()
				out_positions.append(transform_point.call(positions[source_index]))
				out_normals.append(basis * normals[source_index])
				out_uvs.append(uvs[source_index])
			out_indices.append(remap[source_index])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_positions
	arrays[Mesh.ARRAY_NORMAL] = out_normals
	arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	arrays[Mesh.ARRAY_INDEX] = out_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	return node
