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
	var keys: Array[Vector2i] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--chunks="):
			for pair in argument.trim_prefix("--chunks=").split(";"):
				var parts := pair.split(",")
				keys.append(Vector2i(int(parts[0]), int(parts[1])))
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	for key in keys:
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
		for category in ranked.slice(0, 18):
			print("  %5d superfícies  %4d com sombra  %4d nós  %s" % [categories[category].surfaces, categories[category].shadow, categories[category].nodes, category])
	region.free()
	quit(0)
