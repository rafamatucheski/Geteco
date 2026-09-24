extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures.append(label)

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var camera_2d := Camera2D.new()
	camera_2d.position = root.size / 2.0
	camera_2d.enabled = true
	stage.add_child(camera_2d)
	var budget := root.get_node("PresentationBudget")
	await budget.prewarm_ambient_authored()
	budget.set_process(false)
	var actors: Array[AnimatedPedestrian3D] = []
	for index in 2:
		var actor := AnimatedPedestrian3D.new()
		actor.ambient_presentation_atlas = true
		actor.defer_presentation = true
		actor.appearance_seed = 15000 + index
		actor.position = Vector2(520.0 + index * 220.0, 360.0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.ensure_presentation()
		if actor.viewport == null:
			await actor.presentation_ready
		actor._viewport_cull_timer = 0.0
		actor._update_viewport_render_state(0.0)
		actors.append(actor)
	await process_frame
	var atlas_camera := actors[0].viewport.get_camera_3d()
	var size_before := atlas_camera.size
	var direct_shadows_before := actors[0].viewport.find_children("GroundShadow", "MeshInstance3D", false, false).size()
	actors[0].take_damage(1000)
	for frame in 80:
		actors[0]._physics_process(1.0 / 60.0)
		await physics_frame
	_check(not actors[0]._presentation_atlas_active and actors[0].viewport != actors[1].viewport, "Fallen resident leaves the shared atlas for an isolated viewport")
	_check(not actors[0].fall_presentation.shared_atlas_camera, "Fall uses its personal camera framing")
	_check(is_equal_approx(atlas_camera.size, size_before), "Falling resident cannot zoom the shared atlas camera")
	var survivor_region := actors[1].sprite_3d_display.region_rect
	_check(survivor_region.size == Vector2(104, 104) and survivor_region.position.x >= 0.0 and survivor_region.end.x <= actors[1].viewport.size.x, "Standing neighbor is repacked into one complete atlas region")
	_check(actors[1].viewport.find_children("GroundShadow", "MeshInstance3D", false, false).size() == direct_shadows_before, "Fall leaves no shadow debris in the shared atlas")
	_check(actors[0]._fallen_presentation_cached and actors[0].viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Settled corpse freezes its personal viewport after the final frame")
	if DisplayServer.get_name() != "headless":
		actors[0].sprite_3d_display.scale *= 3.0
		actors[1].sprite_3d_display.scale *= 3.0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c161-1d0d-7953-b49b-19a47d3c49cb/atlas-fall-isolation-after.png")
	print("ATLAS_CHARACTER_FALL_ISOLATION failures=", failures)
	quit(0 if failures.is_empty() else 1)
