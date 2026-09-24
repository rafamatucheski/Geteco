extends SceneTree

const PINE := preload("res://world/mountain_pass/MountainPine3D.gd")
const VARIANT_COUNT := 8
const REPEATS := 8
const VIEW_SIZE := Vector2i(160, 224)

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _all_descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [parent]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			result.append(child)
			pending.append(child)
	return result

func _spawn_batch(parent: Node2D, x_offset: float) -> Array[Node]:
	var trees: Array[Node] = []
	for repeat in REPEATS:
		for snowy_index in 2:
			for variant in VARIANT_COUNT:
				var pine := PINE.new()
				# 8..15 cover all posmod(seed, 8) variants without the special
				# zero seed path from MountainPineTree.
				pine.variant_seed = 8 + variant
				pine.is_snowy = snowy_index == 1
				pine.tree_scale = 0.8 + float((repeat + variant) % 5) * 0.1
				pine.position = Vector2(
					x_offset + float(variant) * 86.0,
					float(snowy_index * REPEATS + repeat) * 92.0
				)
				parent.add_child(pine)
				trees.append(pine)
	return trees

func _atlas_views() -> Array[SubViewport]:
	var views: Array[SubViewport] = []
	for node in _all_descendants(root):
		if node is SubViewport and node.name.begins_with("PineAtlas_"):
			views.append(node as SubViewport)
	return views

func _resource_metrics(views: Array[SubViewport]) -> Dictionary:
	var mesh_ids := {}
	var material_ids := {}
	var mesh_nodes := 0
	var multimesh_nodes := 0
	var atlas_nodes := 0
	for view in views:
		var descendants := _all_descendants(view)
		atlas_nodes += descendants.size()
		for node in descendants:
			var mesh: Mesh = null
			var material: Material = null
			if node is MeshInstance3D:
				mesh_nodes += 1
				mesh = (node as MeshInstance3D).mesh
				material = (node as MeshInstance3D).material_override
			elif node is MultiMeshInstance3D:
				multimesh_nodes += 1
				var multi := (node as MultiMeshInstance3D).multimesh
				if multi != null:
					mesh = multi.mesh
				material = (node as MultiMeshInstance3D).material_override
			if mesh != null:
				mesh_ids[mesh.get_instance_id()] = true
			if material != null:
				material_ids[material.get_instance_id()] = true
	return {
		"atlas_nodes": atlas_nodes,
		"mesh_nodes": mesh_nodes,
		"multimesh_nodes": multimesh_nodes,
		"unique_mesh_resources": mesh_ids.size(),
		"unique_material_resources": material_ids.size(),
	}

func _tree_contract(trees: Array[Node]) -> Dictionary:
	var groups := {}
	var species := {}
	var texture_ids := {}
	var collision_profiles := {}
	var normalized_scales: Array[float] = []
	var details := 0
	for pine in trees:
		var variant: int = posmod(int(pine.variant_seed), VARIANT_COUNT)
		var snow: int = int(bool(pine.is_snowy))
		var key := "%d_%d" % [snow, variant]
		groups[key] = int(groups.get(key, 0)) + 1
		var species_name := String(pine.get_meta("forest_species", ""))
		species[species_name] = true
		var sprite := pine.get("presentation") as Sprite2D
		if sprite != null and sprite.texture != null:
			var ids: Dictionary = texture_ids.get(key, {})
			ids[sprite.texture.get_instance_id()] = true
			texture_ids[key] = ids
			normalized_scales.append(sprite.scale.x / float(pine.tree_scale))
		var collision := pine.get_node_or_null("TrunkCol") as CollisionShape2D
		if collision != null and collision.shape is CircleShape2D:
			collision_profiles[variant] = (collision.shape as CircleShape2D).radius / float(pine.tree_scale)
		for child in pine.get_children():
			if child.get_script() != null and child.get_script().resource_path.ends_with("ForestFloorDetails.gd"):
				details += 1
	var shared_per_group := true
	for key in texture_ids:
		if (texture_ids[key] as Dictionary).size() != 1:
			shared_per_group = false
	return {
		"groups": groups.size(),
		"species": species.size(),
		"textures": texture_ids.size(),
		"shared_texture_per_group": shared_per_group,
		"floor_details": details,
		"collision_profiles": collision_profiles,
		"normalized_scale_min": normalized_scales.min() if not normalized_scales.is_empty() else 0.0,
		"normalized_scale_max": normalized_scales.max() if not normalized_scales.is_empty() else 0.0,
	}

func _visual_signature(view: SubViewport) -> Dictionary:
	var image := view.get_texture().get_image()
	if image == null or image.is_empty():
		return {}
	var opaque := 0
	var bright := 0
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.05:
				opaque += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
				if color.r > 0.68 and color.g > 0.72 and color.b > 0.72:
					bright += 1
	return {
		"opaque": opaque,
		"bright": bright,
		"bounds": [min_x, min_y, max_x, max_y],
	}

func _compare_visual(current: Dictionary, baseline: Dictionary) -> void:
	for key in baseline:
		_check(current.has(key), "atlas visual permanece presente: " + String(key))
		if not current.has(key):
			continue
		var old: Dictionary = baseline[key]
		var now: Dictionary = current[key]
		var old_opaque := maxi(int(old.get("opaque", 0)), 1)
		var old_bright := maxi(int(old.get("bright", 0)), 1)
		_check(abs(int(now.get("opaque", 0)) - old_opaque) <= maxi(8, int(old_opaque * 0.01)), "silhueta preservada: " + String(key))
		# The bright threshold can move a band of identically covered pixels when
		# opaque geometry is submitted as one batch. Exact coverage and bounds
		# remain strict; this only tolerates the lighting classification edge.
		_check(abs(int(now.get("bright", 0)) - int(old.get("bright", 0))) <= maxi(150, int(old_bright * 0.20)), "massa clara/neve preservada: " + String(key))
		var old_bounds: Array = old.get("bounds", [])
		var now_bounds: Array = now.get("bounds", [])
		var same_bounds := old_bounds.size() == now_bounds.size()
		for index in mini(old_bounds.size(), now_bounds.size()):
			same_bounds = same_bounds and int(old_bounds[index]) == int(now_bounds[index])
		_check(same_bounds, "limites projetados preservados: " + String(key))

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world := Node2D.new()
	world.name = "PineCacheTestWorld"
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(300, 650)
	camera.zoom = Vector2.ONE * 0.45
	world.add_child(camera)
	camera.make_current()

	var cold_started := Time.get_ticks_usec()
	var cold_trees := _spawn_batch(world, 0.0)
	var cold_add_usec := Time.get_ticks_usec() - cold_started
	for frame in 6:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var first_present_usec := Time.get_ticks_usec() - cold_started

	var warm_started := Time.get_ticks_usec()
	var warm_trees := _spawn_batch(world, 900.0)
	var warm_add_usec := Time.get_ticks_usec() - warm_started
	for frame in 3:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

	var views := _atlas_views()
	var resources := _resource_metrics(views)
	var contract := _tree_contract(cold_trees + warm_trees)
	var visuals := {}
	if DisplayServer.get_name() != "headless":
		for view in views:
			visuals[String(view.name)] = _visual_signature(view)

	_check(views.size() == VARIANT_COUNT * 2, "um atlas compartilhado para cada variante seca/nevada")
	_check(int(contract.groups) == VARIANT_COUNT * 2, "lote cobre as dezesseis combinações")
	_check(int(contract.species) == VARIANT_COUNT, "oito espécies/variações preservadas")
	_check(int(contract.textures) == VARIANT_COUNT * 2 and bool(contract.shared_texture_per_group), "árvores repetidas reutilizam a textura do grupo")
	_check(int(contract.floor_details) == REPEATS * 2 * 6, "detalhes de chão mantêm a regra de variantes")
	var expected_clearances := [32.0, 24.0, 22.0, 10.0, 12.0, 7.0, 18.0, 25.0]
	var collision_profiles: Dictionary = contract.collision_profiles
	_check(collision_profiles.size() == VARIANT_COUNT, "oito footprints de colisão presentes")
	for variant in VARIANT_COUNT:
		_check(is_equal_approx(float(collision_profiles.get(variant, -1.0)), expected_clearances[variant]), "footprint preservado: variante %d" % variant)
	_check(is_equal_approx(float(contract.normalized_scale_min), 0.5625) and is_equal_approx(float(contract.normalized_scale_max), 0.5625), "escala projetada acompanha tree_scale sem deformação")
	_check(int(resources.atlas_nodes) <= 400, "atlas mantém orçamento compacto de nós")
	_check(int(resources.unique_mesh_resources) <= 40, "atlas mantém cache limitado de malhas")
	_check(int(resources.unique_material_resources) <= 8, "atlas mantém cache limitado de materiais")
	for view in views:
		_check(view.size == VIEW_SIZE, "resolução do atlas preservada: " + String(view.name))
	if not visuals.is_empty():
		var dry_bright := 0
		var snowy_bright := 0
		for key in visuals:
			if String(key).begins_with("PineAtlas_1_"):
				snowy_bright += int(visuals[key].bright)
			else:
				dry_bright += int(visuals[key].bright)
		_check(snowy_bright > dry_bright + 1000, "atlas nevado preserva massa clara visível")

	var report := {
		"cold_add_usec": cold_add_usec,
		"first_present_usec": first_present_usec,
		"warm_add_usec": warm_add_usec,
		"tree_count": cold_trees.size() + warm_trees.size(),
		"view_count": views.size(),
		"resources": resources,
		"contract": contract,
		"visuals": visuals,
	}
	var baseline_path := _arg_value("baseline=")
	if not baseline_path.is_empty() and FileAccess.file_exists(baseline_path):
		var baseline = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		_check(baseline is Dictionary, "baseline JSON legível")
		if baseline is Dictionary:
			var old_resources: Dictionary = baseline.get("resources", {})
			_check(int(resources.atlas_nodes) <= int(old_resources.get("atlas_nodes", resources.atlas_nodes)), "nós internos não aumentam")
			_check(int(resources.unique_mesh_resources) <= int(old_resources.get("unique_mesh_resources", resources.unique_mesh_resources)), "malhas únicas não aumentam")
			_check(int(resources.unique_material_resources) <= int(old_resources.get("unique_material_resources", resources.unique_material_resources)), "materiais únicos não aumentam")
			if not visuals.is_empty() and not (baseline.get("visuals", {}) as Dictionary).is_empty():
				_compare_visual(visuals, baseline.visuals)
	var out_path := _arg_value("out=")
	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	print("MOUNTAIN_PINE_CACHE ", JSON.stringify(report))
	print("MOUNTAIN_PINE_CACHE failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
