extends SceneTree
## Camadas de chão empilhadas no porto (antes/depois da consolidação do chão).
## Monta todos os chunks do Harbor fora da sessão, pega os triângulos virados para cima perto do nível
## do chão e conta, num grid de CELL metros, quantas peças diferentes cobrem cada ponto. Não mede FPS:
## mede sobreposição de geometria (overdraw de chão, coplanaridade/z-fighting e colisão duplicada).
## Uso: "$GODOT" --path . --headless --script res://tests/measure/measure_harbor_ground_layers.gd -- --label=antes
const REGION := preload("res://world/regions/NativeRegion.gd")
const CELL := 0.5
const GROUND_MIN_Y := -0.06
const GROUND_MAX_Y := 0.30
const MIN_UP := 0.9
const SAMPLE_OFFSET := 0.4637

var layers: Dictionary = {} # Vector2i -> {label: true}
var label_area: Dictionary = {} # label -> células
var label_nodes: Dictionary = {} # label -> nós
var collision_layers: Dictionary = {} # Vector2i -> contagem de corpos estáticos com topo no chão

func _initialize() -> void: run.call_deferred()

func _label(node: Node, chunk: Node) -> String:
	var name := String(node.name).rstrip("0123456789_@").trim_prefix("@")
	var owner_script := ""
	var walk := node.get_parent()
	while walk != null and walk != chunk:
		if walk.get_script() != null:
			owner_script = String(walk.get_script().resource_path).get_file().get_basename()
			break
		walk = walk.get_parent()
	if node.get_script() != null: owner_script = String(node.get_script().resource_path).get_file().get_basename()
	return (owner_script + "/" if owner_script != "" else "") + (name if name != "" else node.get_class())

func _rasterize(points: Array, label: String) -> int:
	# Triângulo em XZ: marca as células cujo centro cai dentro dele.
	var a: Vector2 = points[0]; var b: Vector2 = points[1]; var c: Vector2 = points[2]
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	var marked := 0
	for x in range(floori(lo.x / CELL), ceili(hi.x / CELL)):
		for z in range(floori(lo.y / CELL), ceili(hi.y / CELL)):
			# Deslocado de 1/16 m: as peças do porto têm vértices em múltiplos de 1/16 e a amostra no
			# centro exato da célula caía em cima da costura entre duas peças (não conta em nenhuma).
			var p := Vector2((x + SAMPLE_OFFSET) * CELL, (z + SAMPLE_OFFSET) * CELL)
			if not Geometry2D.point_is_inside_triangle(p, a, b, c): continue
			var key := Vector2i(x, z)
			if not layers.has(key): layers[key] = {}
			if not layers[key].has(label):
				layers[key][label] = true
				label_area[label] = label_area.get(label, 0) + 1
				marked += 1
	return marked

func _mesh_faces(mesh: Mesh, xform: Transform3D, label: String) -> void:
	var faces := mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var p0: Vector3 = xform * faces[i]; var p1: Vector3 = xform * faces[i + 1]; var p2: Vector3 = xform * faces[i + 2]
		var normal := (p1 - p0).cross(p2 - p0)
		if normal.length_squared() < 1e-8: continue
		if absf(normal.normalized().y) < MIN_UP: continue
		var top := maxf(p0.y, maxf(p1.y, p2.y))
		var bottom := minf(p0.y, minf(p1.y, p2.y))
		if top > GROUND_MAX_Y or bottom < GROUND_MIN_Y: continue
		_rasterize([Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z)], label)

func _scan(chunk: Node3D) -> void:
	for found in chunk.find_children("*", "GeometryInstance3D", true, false):
		if not found.is_visible_in_tree(): continue
		var label := _label(found, chunk)
		if found is MeshInstance3D and found.mesh != null:
			var aabb: AABB = found.global_transform * found.get_aabb()
			if aabb.position.y > GROUND_MAX_Y or aabb.end.y < GROUND_MIN_Y: continue
			_mesh_faces(found.mesh, found.global_transform, label)
			label_nodes[label] = label_nodes.get(label, 0) + 1
		elif found is MultiMeshInstance3D and found.multimesh != null and found.multimesh.mesh != null:
			var multi: MultiMesh = found.multimesh
			# Só peças chatas (ladrilhos, faixas): grama e postes não são chão.
			if multi.mesh.get_aabb().size.y > 0.12: continue
			for index in multi.instance_count:
				_mesh_faces(multi.mesh, found.global_transform * multi.get_instance_transform(index), label)
			label_nodes[label] = label_nodes.get(label, 0) + 1

func run() -> void:
	var label_arg := "medicao"
	var probes: Array[Vector2i] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label_arg = argument.trim_prefix("--label=")
		# --probe=x,z (metros): lista as peças que cobrem esse ponto.
		if argument.begins_with("--probe="):
			var parts := argument.trim_prefix("--probe=").split(",")
			probes.append(Vector2i(floori(parts[0].to_float() / CELL), floori(parts[1].to_float() / CELL)))
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var keys: Dictionary = {}
	for key in region.records: keys[key] = true
	for land in region.source_data.harbor_land:
		var rect := Rect2(land[0] * REGION.SCALE, land[1] * REGION.SCALE, land[2] * REGION.SCALE, land[3] * REGION.SCALE)
		for x in range(floori(rect.position.x / REGION.CELL), ceili(rect.end.x / REGION.CELL)):
			for z in range(floori(rect.position.y / REGION.CELL), ceili(rect.end.y / REGION.CELL)):
				keys[Vector2i(x, z)] = true
	var began := Time.get_ticks_msec()
	for key in keys:
		region._build_chunk(key)
		var chunk: Node3D = region.chunks[key]
		_scan(chunk)
		region.chunks.erase(key)
		region._detach_cached_records(chunk)
		chunk.free()
	var cut := preload("res://world/urban_detail/GroundCut.gd")
	print("HARBOR_GROUND_TRIANGULATION falhas=", cut.failed_triangulations, " area_caixas_m2=", cut.failed_area)
	for probe in probes:
		print("HARBOR_GROUND_PROBE ", Vector2(probe) * CELL, " ", layers.get(probe, {}).keys())
	var histogram := {}
	var pairs := {}
	for key in layers:
		var labels: Array = layers[key].keys()
		var count := labels.size()
		histogram[count] = histogram.get(count, 0) + 1
		if count < 2: continue
		labels.sort()
		for i in labels.size():
			for j in range(i + 1, labels.size()):
				var pair: String = labels[i] + "  +  " + labels[j]
				pairs[pair] = pairs.get(pair, 0) + 1
	var cell_area := CELL * CELL
	var total := 0
	var weighted := 0
	for count in histogram:
		total += int(histogram[count])
		weighted += int(histogram[count]) * int(count)
	var top_pairs := pairs.keys()
	top_pairs.sort_custom(func(a, b): return pairs[a] > pairs[b])
	var top_labels := label_area.keys()
	top_labels.sort_custom(func(a, b): return label_area[a] > label_area[b])
	var report := {
		"label": label_arg, "chunks": keys.size(), "cell_m": CELL, "build_ms": Time.get_ticks_msec() - began,
		"ground_area_m2": total * cell_area,
		"mean_layers": float(weighted) / maxf(total, 1),
		"area_by_layer_count_m2": {},
		"layers_by_source_m2": {},
		"top_overlapping_pairs_m2": {},
		"scope": "triângulos virados para cima entre %.2f e %.2f m; uma peça conta uma vez por célula" % [GROUND_MIN_Y, GROUND_MAX_Y],
	}
	var counts := histogram.keys()
	counts.sort()
	for count in counts: report.area_by_layer_count_m2[str(count)] = int(histogram[count]) * cell_area
	for label in top_labels.slice(0, 40): report.layers_by_source_m2[label] = {"m2": int(label_area[label]) * cell_area, "nodes": label_nodes.get(label, 0)}
	for pair in top_pairs.slice(0, 40): report.top_overlapping_pairs_m2[pair] = int(pairs[pair]) * cell_area
	var folder := "res://evidence/harbor-ground-layers"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder + "/" + label_arg + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("HARBOR_GROUND_LAYERS ", JSON.stringify({"label": label_arg, "area_m2": report.ground_area_m2, "mean_layers": report.mean_layers, "by_count": report.area_by_layer_count_m2}))
	print("HARBOR_GROUND_LAYERS arquivo=", ProjectSettings.globalize_path(path))
	# Células cobertas para comparar furos entre duas medições (tmp/, fora do Git).
	var covered := PackedInt32Array()
	for key in layers: covered.append_array(PackedInt32Array([key.x, key.y]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var dump := FileAccess.open("res://tmp/harbor_ground_" + label_arg + ".bin", FileAccess.WRITE)
	dump.store_buffer(covered.to_byte_array())
	dump.close()
	region.queue_free()
	quit(0)
