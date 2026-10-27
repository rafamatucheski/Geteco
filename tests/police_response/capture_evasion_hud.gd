extends SceneTree
## Directed HUD inspection in Main; no performance or end-to-end pursuit claim.
var out := "res://evidence/police-balance-20261002/hud"
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(150.0).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"real Main ready")
	if not failures.is_empty(): quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.set_physics_process(false)
	world.dispatch.set_physics_process(false)
	world.gameplay.police_air.set_physics_process(false)
	world.gameplay.register_crime(60,world.player.global_position)
	var hud = world.hud
	world.gameplay.report_contact(world.player.global_position)
	hud.refresh_from_state()
	check("Perseguição" in hud.stars_label.get_parsed_text() and not hud.search_progress.visible,"contact shows steady pursuit")
	world.gameplay.contact_age=2.0
	world.gameplay.hidden_time=world.gameplay.police_evasion_seconds()*.85
	hud.refresh_from_state()
	check(hud.search_progress.visible and is_equal_approx(hud.search_progress.value,.85),"search progress projects authoritative evasion")
	var samples: Array[Dictionary] = []
	for frame in 16:
		await create_timer(.125).timeout
		samples.append({"time":Time.get_ticks_msec(),"text":hud.stars_label.text,"value":hud.search_progress.value})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("search-%02d.png" % frame))
	check(samples[0].text != samples[4].text,"live HUD animates search over multiple rendered frames")
	world.gameplay.report_contact(world.player.global_position)
	hud.refresh_from_state()
	check(not hud.search_progress.visible and world.gameplay.police_evasion_progress()==0,"rediscovery clears progress without adding stars")
	world.gameplay.clear_wanted(true)
	hud.refresh_from_state()
	check(hud.stars_label.get_parsed_text()=="Investigação local","escape distinguishes local investigation")
	world.gameplay.clear_wanted()
	hud.refresh_from_state()
	check(not hud.stars_label.visible and not hud.search_progress.visible,"case cleanup removes all indicators")
	var file := FileAccess.open(out.path_join("temporal.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"\t")); file.close()
	print("EVASION_HUD failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
