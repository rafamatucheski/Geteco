extends SceneTree
var world
func _initialize() -> void: call_deferred("run")
func shot(label: String) -> void:
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	await create_timer(1).timeout
	world.player.teleport(world.maciota_place.exterior_return+Vector3.UP*.04)
	world.camera.heading = 0
	world.camera.target_size = 24
	await shot("v2-exterior")
	assert(world.session.transition(true,false))
	await shot("v2-interior-entry")
	world.player.teleport(world.maciota_place.interaction_points.maciota+Vector3.UP*.04)
	await create_timer(.2).timeout
	assert(world.session.interact_nearest())
	await shot("v2-dialogue")
	world.session.close_dialogue()
	world.player.teleport(world.maciota_place.interaction_points.mechanic+Vector3.UP*.04)
	await create_timer(.2).timeout
	assert(world.session.interact_nearest())
	world.session.close_dialogue()
	await shot("v2-mechanic-part")
	world.free()
	quit()
