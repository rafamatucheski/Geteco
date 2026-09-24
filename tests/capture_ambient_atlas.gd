extends SceneTree

var actors: Array[AnimatedPedestrian3D] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("242c36"))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	for index in 8:
		var actor := AnimatedPedestrian3D.new()
		actor.name = "AtlasResident_%d" % index
		actor.ambient_low_lod = true
		actor.defer_presentation = true
		actor.appearance_seed = index + 100
		actor.body_type_override = index % 5
		actor.archetype_override = [0, 1, 2, 4, 6, 7, 3, 5][index]
		actor.appearance_gender = 1 + index % 2
		actor.position = Vector2(82.0 + index * 160.0, 340.0)
		stage.add_child(actor)
		actor.ensure_presentation()
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.sprite_3d_display.scale = Vector2.ONE * 1.65
		actors.append(actor)
		var label := Label.new()
		label.text = "R%d" % (index + 1)
		label.position = Vector2(70.0 + index * 160.0, 220.0)
		stage.add_child(label)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var output := "D:/geteco/artifacts/ambient-atlas/gallery"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output + "/front.png")
	print("AMBIENT_ATLAS_CAPTURE actors=%d" % actors.size())
	quit(0)
