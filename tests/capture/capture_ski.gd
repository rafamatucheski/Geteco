extends "res://tests/measure/measure_ski.gd"
func run() -> void:
	await super.run()
	started = 0
	if world == null: return
	world.player.controlled_automatically = false
	world.camera.target_size = 14
	var ski = world.session.mountain_progression
	ski.data.rental = true
	ski.data.equipment = true
	world.session.apply_outfit()
	ski.perform("ski_start:ski_primeira_descida")
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ski/ski-equipped.png")
	ski.cancel_attempt()
	var point := DEFINITIONS.at(Vector2(7100,-4890),"mountain")+Vector3(0,.1,4)
	world.production.region.set_focus(point)
	world.player.teleport(point)
	for i in 20: await physics_frame
	ski.lift.board()
	for i in 60: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ski/ski-lift.png")
	ski.cancel_attempt()
	world.queue_free()
	await process_frame
	quit()
