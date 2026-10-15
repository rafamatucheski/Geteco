extends SceneTree
## Censo de draw calls por trecho (2026-10-14): quanto cada tipo de objeto custa em superfícies visíveis.
## Cada superfície de malha visível é ~1 draw call na passada principal; com sombra, mais 1 por cascata.
## Não mede culling da câmera nem GPU: é o teto do que o trecho entrega ao renderizador.
## Uso: "$GODOT" --headless --path . --script res://tests/measure/census_chunk_draws.gd -- --no-save --chunks=3,0;3,1;1,1
const REGION := preload("res://world/regions/NativeRegion.gd")

func _initialize() -> void: run.call_deferred()

func _category(node: Node, chunk: Node) -> String:
	# Sobe até o filho direto do trecho e tira os números: "Building_12" e "Building_3" contam juntos.
	var current := node
	while current.get_parent() != chunk and current.get_parent() != null: current = current.get_parent()
	var regex := RegEx.create_from_string("[0-9@_]+$")
	var name := regex.sub(str(current.name), "")
	var script: Script = current.get_script()
	if script != null: name += " <" + script.resource_path.get_file() + ">"
	return name

func run() -> void:
	# Fusão inteira de uma vez: aqui não se mede tempo de quadro.
	preload("res://world/chunk_bake/ChunkCellMerge.gd").slice_budget_usec = 0
	var keys: Array[Vector2i] = []
	var region_id := "harbor"
	var all_chunks := false
	var quiet := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--region="): region_id = argument.trim_prefix("--region=")
		if argument == "--chunks=all": all_chunks = true
		if argument == "--resumo": quiet = true
		if argument.begins_with("--chunks=") and argument != "--chunks=all":
			for pair in argument.trim_prefix("--chunks=").split(";"):
				var parts := pair.split(",")
				keys.append(Vector2i(int(parts[0]), int(parts[1])))
	var region = REGION.build_region(region_id, Vector3.INF) if region_id != "desert" else load("res://world/desert/DesertRegion.gd").build_region("desert", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	if all_chunks:
		for key in region.records.keys(): keys.append(key)
	var summary: Array = []
	for key in keys:
		if region_id == "desert":
			# O deserto monta pelo foco, em fatias: espera o trecho do foco existir e a fila esvaziar.
			region.set_focus(Vector3((key.x + .5) * region.CELL, 0, (key.y + .5) * region.CELL), true)
			for frame in 600:
				await process_frame
				if region.chunks.has(key) and region.pending.is_empty() and region.build_jobs.is_empty(): break
			if not region.chunks.has(key): continue
		else:
			region._build_chunk(key)
		var chunk: Node = region.chunks[key]
		for frame in 8: await process_frame
		var categories := {}
		var totals := {"surfaces": 0, "shadow_surfaces": 0, "instances": 0}
		for node in chunk.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if not geometry.is_visible_in_tree(): continue
			var surfaces := 0
			if geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
				surfaces = (geometry as MeshInstance3D).mesh.get_surface_count()
			elif geometry is MultiMeshInstance3D and (geometry as MultiMeshInstance3D).multimesh != null and (geometry as MultiMeshInstance3D).multimesh.mesh != null:
				surfaces = (geometry as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
			else:
				surfaces = 1
			var shadow := geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var category := _category(geometry, chunk)
			if not categories.has(category): categories[category] = {"surfaces": 0, "shadow": 0, "nodes": 0}
			categories[category].surfaces += surfaces
			categories[category].nodes += 1
			if shadow: categories[category].shadow += surfaces
			totals.surfaces += surfaces
			totals.instances += 1
			if shadow: totals.shadow_surfaces += surfaces
		var ranked := categories.keys()
		ranked.sort_custom(func(a, b): return categories[a].surfaces > categories[b].surfaces)
		print("CENSO trecho=%s x=%d z=%d %s" % [key, key.x * 64, key.y * 64, JSON.stringify(totals)])
		summary.append({"key": key, "surfaces": totals.surfaces, "shadow": totals.shadow_surfaces, "top": ranked.slice(0, 3)})
		# Trecho medido é liberado: medir a região inteira de uma vez não cabe na memória.
		if region_id != "desert":
			region.chunks.erase(key)
			region._detach_cached_records(chunk)
			chunk.free()
		if quiet: continue
		for category in ranked.slice(0, 18):
			print("  %5d superfícies  %4d com sombra  %4d nós  %s" % [categories[category].surfaces, categories[category].shadow, categories[category].nodes, category])
	var total := 0
	var shadow := 0
	for item in summary:
		total += item.surfaces
		shadow += item.shadow
	summary.sort_custom(func(a, b): return a.surfaces + a.shadow > b.surfaces + b.shadow)
	print("CENSO_RESUMO região=%s trechos=%d superfícies=%d sombra=%d" % [region_id, summary.size(), total, shadow])
	for item in summary.slice(0, 8): print("CENSO_TOPO %s superfícies=%d sombra=%d %s" % [item.key, item.surfaces, item.shadow, item.top])
	region.free()
	quit(0)
