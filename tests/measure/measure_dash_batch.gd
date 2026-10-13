extends SceneTree
## P8 (2026-10-13): conta os tracinhos da faixa num trecho do oeste do porto e grava as transformações.
## Não mede tempo: só nós e instâncias. Rodar uma vez com o lote ligado e outra com GETECO_DASH_BATCH=0,
## depois comparar as duas listas:
##   "$GODOT" --path . --script res://tests/measure/measure_dash_batch.gd -- --label=lote
##   GETECO_DASH_BATCH=0 "$GODOT" --path . --script res://tests/measure/measure_dash_batch.gd -- --label=soltos
##   "$GODOT" --path . --headless --script res://tests/measure/measure_dash_batch.gd -- --compare=soltos,lote
## Sem --headless na contagem: o servidor de renderização falso do headless não guarda as transformações
## do MultiMesh (voltam identidade) e a comparação acusaria diferença que não existe.
const REGION := preload("res://world/regions/NativeRegion.gd")
const ROAD := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const AREA := Rect2(64, 64, 128, 64)
const OUT_DIR := "res://evidence/claude-p8-20261013/"
const TOLERANCE := 0.0005

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "medicao"
	var whole := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		# --all: o porto inteiro, não só o trecho do oeste.
		if argument == "--all": whole = true
		if argument.begins_with("--compare="):
			var names := argument.trim_prefix("--compare=").split(",")
			quit(_compare(names[0], names[1]))
			return
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
	var chunk_count := 0
	var loose := 0
	var batches := 0
	var marks: Array = []
	for key in keys:
		var chunk_rect := Rect2(Vector2(key) * REGION.CELL, Vector2.ONE * REGION.CELL)
		if not whole and not chunk_rect.intersects(AREA): continue
		region._build_chunk(key)
		var chunk: Node3D = region.chunks[key]
		chunk_count += 1
		loose += chunk.find_children("Dash_*", "MeshInstance3D", true, false).size()
		batches += chunk.find_children("DashBatch_*", "MultiMeshInstance3D", true, false).size()
		for mark in ROAD.dash_marks(chunk):
			var xform: Transform3D = mark.transform
			marks.append([mark.color, int(mark.cast_shadow), xform.origin.x, xform.origin.y, xform.origin.z,
				xform.basis.x.x, xform.basis.x.y, xform.basis.x.z, xform.basis.y.x, xform.basis.y.y, xform.basis.y.z,
				xform.basis.z.x, xform.basis.z.y, xform.basis.z.z])
		region.chunks.erase(key)
		region._detach_cached_records(chunk)
		chunk.free()
	var report := {"label": label, "batch_enabled": ROAD.dash_batch_enabled, "area": "porto inteiro" if whole else [AREA.position.x, AREA.position.y, AREA.size.x, AREA.size.y],
		"chunks": chunk_count, "dash_mesh_instances": loose, "dash_multimesh_instances": batches, "dashes": marks.size(), "marks": marks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var file := FileAccess.open(OUT_DIR + "dash_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("DASH_BATCH label=", label, " porto_inteiro=", whole, " lote=", ROAD.dash_batch_enabled, " chunks=", chunk_count,
		" MeshInstance3D_Dash=", loose, " MultiMeshInstance3D_DashBatch=", batches, " tracinhos=", marks.size())
	quit(0)

func _load(label: String) -> Dictionary:
	var file := FileAccess.open(OUT_DIR + "dash_%s.json" % label, FileAccess.READ)
	if file == null: return {}
	return JSON.parse_string(file.get_as_text())

func _compare(a_label: String, b_label: String) -> int:
	var a := _load(a_label)
	var b := _load(b_label)
	if a.is_empty() or b.is_empty():
		print("DASH_COMPARE faltam arquivos")
		return 1
	# A ordem muda entre os modos (o lote separa por cor): ordena pela cor e pela posição.
	var order := func(x, y):
		if x[0] != y[0]: return x[0] < y[0]
		if absf(x[2] - y[2]) > TOLERANCE: return x[2] < y[2]
		return x[4] < y[4]
	var left: Array = a.marks.duplicate()
	var right: Array = b.marks.duplicate()
	left.sort_custom(order)
	right.sort_custom(order)
	var mismatches := 0
	var worst := 0.0
	if left.size() != right.size(): mismatches += 1
	for index in mini(left.size(), right.size()):
		var x: Array = left[index]
		var y: Array = right[index]
		if x[0] != y[0] or x[1] != y[1]: mismatches += 1; continue
		for field in range(2, x.size()):
			var difference := absf(float(x[field]) - float(y[field]))
			worst = maxf(worst, difference)
			if difference > TOLERANCE:
				mismatches += 1
				break
	print("DASH_COMPARE ", a_label, "=", left.size(), " ", b_label, "=", right.size(), " diferencas=", mismatches, " maior_desvio=", worst)
	return 0 if mismatches == 0 else 1
