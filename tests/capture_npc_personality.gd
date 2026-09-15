extends SceneTree
var label := "before"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="): label=arg.trim_prefix("label=")
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var stage=Node2D.new()
	root.add_child(stage)
	current_scene=stage
	var actors: Array=[]
	for i in 4:
		var actor=AnimatedPedestrian3D.new()
		actor.appearance_seed=i*10+2
		actor.archetype_override=1
		actor.position=Vector2(160+i*320,380)
		stage.add_child(actor)
		actor.set_physics_process(false)
		if actor.viewport==null: actor.ensure_presentation()
		actors.append(actor)
	for actor in actors:
		actor.viewport.size=Vector2i(384,384)
		actor.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		actor.sprite_3d_display.scale=Vector2.ONE*.82
		actor.model_root.rotation.y=PI
		var camera=actor.viewport.get_camera_3d()
		camera.look_at_from_position(Vector3(0,1.8,5),Vector3(0,.8,0))
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=1.85
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/npc-personality-0912/"+label+".png")
	quit()
