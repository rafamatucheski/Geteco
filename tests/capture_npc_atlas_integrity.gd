extends SceneTree

const ACTOR_SCRIPT := preload("res://characters/AnimatedPedestrian3D.gd")

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("242c36"))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	camera.position = root.size / 2.0
	camera.enabled = true
	stage.add_child(camera)
	var budget := root.get_node("PresentationBudget")
	await budget.prewarm_ambient_authored()
	for index in 8:
		var actor := ACTOR_SCRIPT.new() as AnimatedPedestrian3D
		actor.name = "AtlasIntegrity_%02d" % index
		actor.ambient_presentation_atlas = true
		actor.defer_presentation = true
		actor.appearance_seed = 13000 + index
		actor.body_type_override = index % 5
		actor.archetype_override = [0, 1, 2, 4, 6, 7, 1, 4][index]
		actor.appearance_gender = 1 + index % 2
		actor.position = Vector2(150.0 + index * 140.0, 370.0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.ensure_presentation()
		if actor.viewport == null:
			await actor.presentation_ready
		actor.sprite_3d_display.scale = Vector2.ONE * 1.25
		actor._viewport_cull_timer = 0.0
		actor._update_viewport_render_state(0.0)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c161-1d0d-7953-b49b-19a47d3c49cb/npc-atlas-integrity-after.png"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.get_texture().get_image().save_png(output)
	print("NPC_ATLAS_INTEGRITY_CAPTURE output=", output)
	quit(0)
