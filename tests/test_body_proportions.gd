extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1000, 480)
	var actors: Array = []
	for i in 5:
		seed(42)
		var actor := AnimatedPedestrian3D.new()
		actor.district_theme = AnimatedPedestrian3D.DistrictTheme.CITY_DOWNTOWN
		actor.archetype_override = 1
		actor.body_type_override = i
		root.add_child(actor)
		actor.set_physics_process(false)
		actor.position = Vector2(100 + i * 200, 230)
		actor.sprite_3d_display.scale = Vector2(2.0, 2.0)
		actor.model_root.rotation.y = PI * 0.85
		actors.append(actor)
		var label := Label.new()
		label.text = ["MEDIO", "MAGRO", "GORDO", "ALTO", "BAIXO"][i]
		label.position = Vector2(65 + i * 200, 360)
		root.add_child(label)
	assert(actors[2].torso_node.scale.x > actors[1].torso_node.scale.x * 1.5)
	assert(actors[2].torso_node.scale.x < actors[1].torso_node.scale.x * 2.0)
	assert(actors[3].model_root.scale.y > actors[4].model_root.scale.y * 1.35)
	assert(actors[2].torso_node.get_node_or_null("Belly") == null)
	for actor in actors:
		assert(actor.head_node.scale.x > .9 and actor.head_node.scale.x < 1.1)
		assert(actor.head_node.has_node("Neck"))
		actor.velocity = Vector2(30, 0)
		actor._physics_process(0.016)
		actor.sprite_3d_display.show()
		actor.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 5: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var output := "res://docs/measurements/civilian-identity-0910/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		root.get_texture().get_image().save_png(output + "biotipos.png")
	print("BODY_PROPORTIONS PASS: distinct geometry, height, head proportions and animated rigs")
	quit()
