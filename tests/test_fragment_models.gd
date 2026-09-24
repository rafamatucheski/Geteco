extends SceneTree
const REMAINS := preload("res://guns/combat/ExplosionRemains.gd")
const BUILDER := preload("res://guns/combat/BodyFragmentMesh.gd")
var failures := 0
var output := "D:/geteco/artifacts/remains-pain-revision"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	print(("PASS " if ok else "FAIL ") + label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	seed(13092026)
	root.size = Vector2i(1440, 900)
	RenderingServer.set_default_clear_color(Color("343d43"))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(5,5)
	var all_remains: Array = []
	var patterns := {}
	var trajectories := {}
	for i in 10:
		var actor: Node2D = load("res://characters/AnimatedPedestrian3D.gd").new()
		actor.position = Vector2(i*350, 0)
		world.add_child(actor)
		actor.ensure_presentation()
		actor.set_physics_process(false)
		actor.set_meta("fragment_seed", i+31)
		var rig_parent: Node = actor.model_root.get_parent()
		camera.position = actor.position
		if i == 0:
			actor.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			for frame in 5: await physics_frame
			await capture("original-character")
		var remains: Node2D = REMAINS.spawn(actor, actor.position-Vector2(25,0))
		while remains._build_index < remains._build_plans.size(): await process_frame
		if i == 0:
			print("ATLAS_SCALE source_view=", actor.viewport.size, " source_sprite=", actor.sprite_3d_display.scale, " fragment_sprite=", remains.pieces[0].fragment_sprite.scale)
		all_remains.append(remains)
		check(not actor.visible and actor.model_root.get_parent() == rig_parent, "Original rig remains intact and hidden")
		var used := {}
		var signature := ""
		for piece in remains.pieces:
			signature += str(piece.part_keys)
			for key in piece.part_keys: used[key] = used.get(key, 0)+1
			check(piece.fragment_model.get_child_count() > 0, "Fragment contains visible mesh geometry")
			var sources: Array = actor.model_root.find_children("*", "MeshInstance3D", true, false)
			var shared := 0
			for mesh in piece.fragment_model.get_children():
				for original in sources:
					if mesh.mesh == original.mesh and mesh.material_override == original.material_override:
						shared += 1
						break
			check(shared > 0, "Fragment preserves original mesh and clothing/skin material resources")
			var bounds: AABB = piece.fragment_model.get_meta("fragment_bounds")
			check(bounds.size.length() > .08 and bounds.size.length() < 1.65, "Fragment fits its detailed atlas cell at natural scale")
		for key in BUILDER.PARTS: check(used.get(key,0) == 1, "Anatomical branch represented once: " + key)
		patterns[signature] = true
		trajectories[str(remains.pieces[0].velocity)] = true
	check(patterns.size() >= 3, "Repeated explosions use at least three anatomical layouts")
	check(trajectories.size() == 10, "Launch direction and energy vary between casualties")
	for script in ["res://characters/CarjackedDriver.gd", "res://world/mountain_pass/WinterResident.gd"]:
		var alternate: Node2D = load("res://characters/CarjackedDriver.tscn").instantiate() if script.contains("Carjacked") else load(script).new()
		alternate.position = Vector2(-900, 0)
		world.add_child(alternate)
		alternate.set_physics_process(false)
		var parts := BUILDER.sources(alternate)
		for key in BUILDER.PARTS:
			check(parts.has(key) and not parts[key].is_empty(), "Alternate production rig retains " + key + ": " + script)
		var head_meshes := 0
		for branch in parts["head_node"]:
			if branch is MeshInstance3D: head_meshes += 1
			head_meshes += branch.find_children("*", "MeshInstance3D", true, false).size()
		check(head_meshes >= 5, "Alternate head retains face and hair, not just neck geometry")
		var remains := REMAINS.spawn(alternate, alternate.position-Vector2(20,0))
		while remains._build_index < remains._build_plans.size(): await process_frame
		check(remains != null and remains.pieces.size() >= 4, "Alternate production rig produces actual mesh fragments")
		if remains != null:
			var atlas: Node = remains.get_child(remains.get_child_count()-1)
			check(is_equal_approx(atlas._actor_scale(alternate), 15.0 if script.contains("Carjacked") else 13.0), "Alternate fragments retain the original on-screen body scale")
	camera.position = all_remains[0].position
	await create_timer(.22).timeout
	await capture("fragments-airborne")
	await create_timer(2).timeout
	for i in 3:
		var area := Rect2(all_remains[i].pieces[0].global_position, Vector2.ONE)
		for piece in all_remains[i].pieces: area = area.expand(piece.global_position)
		camera.position = area.get_center()
		camera.zoom = Vector2.ONE * minf(4.0, 650.0/(area.size.y+45))
		for frame in 3: await physics_frame
		await capture("fragments-settled-" + str(i))
	for remains in all_remains:
		var renderer: Node = remains.get_child(remains.get_child_count()-1)
		check(renderer.finalized and not renderer.is_processing(), "Settled fragments stop scheduling 3D frames")
		check(renderer.viewport.size == Vector2i(384,256), "A whole casualty shares one bounded atlas")
		for piece in remains.pieces:
			check(piece.height == 0 and piece.velocity == Vector2.ZERO, "Fragments settle on physical ground")
	# Variable counts remain collectable as one complete coroner incident.
	var worker := CharacterBody2D.new()
	world.add_child(worker)
	var job: Node2D = all_remains[0]
	var original_count: int = job.pieces.size()
	for i in original_count:
		worker.global_position = job.collection_position(worker)
		job.collect_piece(worker)
	check(job.pieces.is_empty() and job.is_queued_for_deletion(), "Every variable part can be collected and incident closes")
	world.queue_free()
	await process_frame
	await process_frame
	check(get_nodes_in_group("explosion_remains").is_empty(), "Scene teardown removes atlases and fragments")
	print("FRAGMENT_MODELS failures=", failures, " patterns=", patterns.size())
	quit(0 if failures == 0 else 1)
