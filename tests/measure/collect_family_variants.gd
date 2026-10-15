extends SceneTree
## Gera data/family_shader_variants.json: monta todos os trechos do porto, da serra e do deserto com a fusão
## por trecho e grava cada combinação de opções dos materiais família (FamilyShaderVariants). Rodar de novo
## quando geradores de cenário ou a fusão mudarem materiais.
## Uso: "$GODOT" --headless --path . --script res://tests/measure/collect_family_variants.gd -- --no-save
const REGION := preload("res://world/regions/NativeRegion.gd")
const VARIANTS := preload("res://world/chunk_bake/FamilyShaderVariants.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for region_id in ["harbor", "mountain", "desert"]:
		var region = REGION.build_region(region_id, Vector3.INF) if region_id != "desert" else load("res://world/desert/DesertRegion.gd").build_region("desert", Vector3.INF)
		region.initial_prewarm_only = true
		root.add_child(region)
		while not region.prepared: await process_frame
		var keys: Array = region.records.keys()
		for key in keys:
			if region_id == "desert":
				region.set_focus(Vector3((key.x + .5) * region.CELL, 0, (key.y + .5) * region.CELL), true)
				for frame in 600:
					await process_frame
					if region.chunks.has(key) and region.pending.is_empty() and region.build_jobs.is_empty(): break
			else:
				region._build_chunk(key)
			# A fusão espera 2 quadros depois do marco do trecho.
			for frame in 6: await process_frame
			if region_id != "desert" and region.chunks.has(key):
				var chunk: Node3D = region.chunks[key]
				region.chunks.erase(key)
				region._detach_cached_records(chunk)
				chunk.free()
		print("VARIANTES região=%s trechos=%d acumuladas=%d" % [region_id, keys.size(), VARIANTS.seen.size()])
		region.free()
		await process_frame
	var file := FileAccess.open(ProjectSettings.globalize_path(VARIANTS.SHIPPED_PATH), FileAccess.WRITE)
	file.store_string(JSON.stringify(VARIANTS.seen, "\t"))
	file.close()
	print("VARIANTES gravadas=%d em %s" % [VARIANTS.seen.size(), VARIANTS.SHIPPED_PATH])
	quit(0)
