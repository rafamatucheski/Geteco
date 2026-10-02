extends SceneTree
var world
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var point: Vector3 = world.session.activities._phone_position("harbor_foundry")+Vector3(1.2,.1,0)
	world.player.teleport(point)
	world.production.region.set_focus(point)
	world.camera.target_size = 22
	await create_timer(4).timeout
	var prompt = world.hud.interaction_row
	var ok: bool = prompt.visible and prompt.caption.text == "Atender" and prompt.key.visible and prompt.size.y < 45
	ok = ok and absf(prompt.position.x+prompt.size.x*.5-root.get_visible_rect().size.x*.5)<2
	var folder := "res://evidence/footer-prompt-20261002"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/phone.png")
	world.session.activities.perform("race:harbor_foundry")
	await create_timer(.3).timeout
	ok = ok and not prompt.is_visible_in_tree()
	world.session.close_menu()
	world.player.teleport(point+Vector3(12,0,0))
	await create_timer(.4).timeout
	ok = ok and not prompt.visible
	print("FOOTER_PROMPT ","PASS" if ok else "FAIL")
	world.free()
	await process_frame
	quit(0 if ok else 1)
