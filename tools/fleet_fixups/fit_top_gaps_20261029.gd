extends "res://tools/fleet_fixups/build_utility_batch.gd"
## Fecha os vãos do topo nas cenas já instaladas (29/10, relatos do jogador: "as laterais do
## jeep não são grudadas no carro" e "a traseira da camionete não se fecha").
## Não refaz o modelo: um rebake perderia os ajustes posteriores ao lote utilitário (vehicle_fit
## de 23/10 nas ranch, lote de malha). Gera só os quads de top_gap_fill() com as mesmas fórmulas
## do gerador e acrescenta à superfície de tinta do Body da cena instalada. Só os ids pedidos:
## outros carros do mesmo gerador ficam como estão.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/fit_top_gaps_20261029.gd -- --ids=desert_jeep_4x4,ranch_pickup,ranch_single [--dry-run]
const REVISION := 20261029

func run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOLDER.path_join("baseline.json")))
	var ids: Array[String] = []
	var dry := "--dry-run" in OS.get_cmdline_user_args()
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ids="): ids.assign(argument.trim_prefix("--ids=").split(","))
		# --out=res://pasta grava candidatos lá (para medir antes de instalar).
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	var failures := 0
	for id in ids:
		if not baseline.has(id) or not id in IDS:
			push_error("TOP_GAP_FIT %s não é do lote utilitário" % id); failures += 1; continue
		setup(id, baseline[id])
		top_gap_fill()
		var tool: SurfaceTool = groups.get("Body/paint")
		var added: Array = tool.commit_to_arrays() if tool != null else []
		model.free()
		var path: String = preload("res://runtime/RedesignedFleet.gd").scene_path(id)
		var uid := ResourceLoader.get_resource_uid(path)
		var scene: Node3D = (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		if int(scene.get_meta("top_gap_fit_revision", 0)) == REVISION:
			print("TOP_GAP_FIT ", id, " já aplicado; nada a fazer")
			scene.free(); continue
		var body := scene.get_node_or_null("Body") as MeshInstance3D
		var source: ArrayMesh = body.mesh if body != null else null
		var paint := -1
		if source != null:
			for s in source.get_surface_count():
				var m := source.surface_get_material(s)
				if m != null and m.resource_name == "paint": paint = s
		if paint < 0 or added.is_empty() or source.get_blend_shape_count() > 0 or source.shadow_mesh != null:
			push_error("TOP_GAP_FIT %s: Body sem superfície de tinta reconhecível (ou com blend/shadow mesh)" % id)
			failures += 1; scene.free(); continue
		var add_vertices: PackedVector3Array = added[Mesh.ARRAY_VERTEX]
		var result := ArrayMesh.new()
		for s in source.get_surface_count():
			var arrays := source.surface_get_arrays(s)
			if s == paint: _append(arrays, added, body.transform)
			var flags := source.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
			result.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays, [], {}, flags)
			result.surface_set_material(s, source.surface_get_material(s))
			result.surface_set_name(s, source.surface_get_name(s))
		result.custom_aabb = source.custom_aabb
		body.mesh = result
		scene.set_meta("top_gap_fit_revision", REVISION)
		print("TOP_GAP_FIT ", id, " +", add_vertices.size() / 3, " triângulos na tinta do Body (superfície ", paint, ")")
		if not dry:
			var packed := PackedScene.new()
			var status := packed.pack(scene)
			var target := path if out.is_empty() else out.path_join(id + ".scn")
			if not out.is_empty(): DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
			if status == OK: status = ResourceSaver.save(packed, target, ResourceSaver.FLAG_BUNDLE_RESOURCES)
			# A cena é referenciada por caminho, mas preservar o uid evita surpresa em .tscn futuros.
			if status == OK and out.is_empty() and uid != ResourceUID.INVALID_ID: ResourceSaver.set_uid(path, uid)
			if status != OK: push_error("TOP_GAP_FIT %s: falha ao salvar (%d)" % [id, status]); failures += 1
		scene.free()
	quit(1 if failures > 0 else 0)

## Acrescenta triângulos sem índice ao fim da superfície, no mesmo formato de atributos.
## (Packed*Array é cópia ao escrever: cada atributo é extraído, estendido e devolvido.)
func _append(arrays: Array, added: Array, xf: Transform3D) -> void:
	for slot in [Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0]:
		assert(arrays[slot] == null, "atributo inesperado na tinta do Body")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base := vertices.size()
	var new_vertices: PackedVector3Array = added[Mesh.ARRAY_VERTEX]
	var new_normals: PackedVector3Array = added[Mesh.ARRAY_NORMAL]
	var new_colors: PackedColorArray = added[Mesh.ARRAY_COLOR] if added[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var new_uv: PackedVector2Array = added[Mesh.ARRAY_TEX_UV] if added[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var inverse := xf.affine_inverse()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	for i in new_vertices.size():
		vertices.append(inverse * new_vertices[i])
		var n := (xf.basis.transposed() * new_normals[i]).normalized()
		if arrays[Mesh.ARRAY_NORMAL] != null: normals.append(n)
		if arrays[Mesh.ARRAY_COLOR] != null: colors.append(new_colors[i] if i < new_colors.size() else Color.WHITE)
		if arrays[Mesh.ARRAY_TEX_UV] != null: uv.append(new_uv[i] if i < new_uv.size() else Vector2.ZERO)
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var t := (Vector3.RIGHT - n * n.dot(Vector3.RIGHT)).normalized()
			tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] != null: arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_COLOR] != null: arrays[Mesh.ARRAY_COLOR] = colors
	if arrays[Mesh.ARRAY_TEX_UV] != null: arrays[Mesh.ARRAY_TEX_UV] = uv
	if arrays[Mesh.ARRAY_TANGENT] != null: arrays[Mesh.ARRAY_TANGENT] = tangents
	if arrays[Mesh.ARRAY_INDEX] != null:
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in new_vertices.size(): indices.append(base + i)
		arrays[Mesh.ARRAY_INDEX] = indices
