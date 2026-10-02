extends SceneTree
## Real pause save while the inventory holds the player, then fresh Main load.
## SaveStore is redirected before enabling writes; executor also isolates APPDATA.
var world
var checks := 0
var failures: Array[String] = []
var folder := ""
var save_path := ""
var frames_ms: Array[float] = []
var previous_usec := 0

func _initialize() -> void: run.call_deferred()
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if previous_usec > 0: frames_ms.append(float(now-previous_usec)/1000.0)
	previous_usec = now
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func capture_restored() -> bool:
	if DisplayServer.get_name()=="headless": return false
	# ready_for_play antecede oito frames de assentamento e o fade de .45 s.
	# Aguarda a saída real do nó; não esconde nem remove a cortina na fixture.
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and (world.get_node_or_null("LoadingCurtain") != null or root.get_node_or_null("LoadingCurtain") != null): await process_frame
	if world.get_node_or_null("LoadingCurtain") != null or root.get_node_or_null("LoadingCurtain") != null:
		failures.append("capture unavailable: loading curtain remained after restore")
		push_error(failures.back())
		return false
	await RenderingServer.frame_post_draw
	var error: int = root.get_texture().get_image().save_png(folder.path_join("restored.png"))
	if error != OK: failures.append("restored screenshot could not be written")
	return error == OK
func build(saved := false) -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	if saved: world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"native Main ready")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
	if folder.is_empty(): quit(2); return
	save_path = "user://tests/modal-position-%d/progress.json" % Time.get_ticks_usec()
	await build()
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var origin: Vector3 = world.player.position
	var expected := Vector3.INF
	for x in [18.0,-18.0,24.0,-24.0]:
		for z in [0.0,4.0,-4.0,8.0,-8.0]:
			var candidate: Vector3 = origin+Vector3(x,0,z)
			world.production.region.prepare_collision_at(candidate)
			await physics_frame
			if session.position_clear(candidate): expected = candidate; break
		if expected.is_finite(): break
	check(expected.is_finite(),"free foot position away from checkpoint")
	if not expected.is_finite(): quit(1); return
	world.player.teleport(expected)
	world.production.store.path = save_path
	world.production.no_save = false
	session.show_inventory()
	check(session.modal and world.player.input_locked,"inventory holds player outside interior")
	world.pause_panel.pause_game()
	var button: Button = world.pause_panel.get_node("%BtnSaveGame")
	check(not button.disabled,"pause offers manual save with inventory open")
	var began := Time.get_ticks_usec()
	button.pressed.emit()
	var save_usec := Time.get_ticks_usec()-began
	check(FileAccess.file_exists(save_path),"pause button publishes isolated save")
	var snapshot: Dictionary = preload("res://runtime/SaveStore.gd").read_valid(save_path)
	check(not snapshot.is_empty(),"SaveStore validates disk snapshot")
	check(snapshot.get("world",{}).has("pedestrian"),"modal save retains pedestrian position")
	var saved_text := FileAccess.get_file_as_string(save_path)
	FileAccess.open(folder.path_join("saved.json"),FileAccess.WRITE).store_string(saved_text)
	paused = false
	world.production.no_save = true
	session.close_menu()
	# Drain UI focus callbacks while their controls still belong to the old Main.
	await process_frame
	await process_frame
	world.free()
	await process_frame
	await build(true)
	var actual: Vector3 = world.player.position
	check(world.production.loaded_save,"fresh Main loads the isolated file")
	check(actual.distance_to(expected)<.35,"fresh load returns to saved position, not checkpoint")
	check(world.session.position_clear(actual),"loaded capsule stands on free floor")
	check(not world.session.modal and not world.player.input_locked,"loaded player is controllable")
	var captured: bool = await capture_restored()
	var result := {"checks":checks,"failures":failures,"expected":str(expected),"actual":str(actual),
		"capture_after_curtain":captured,
		"save_usec":save_usec,"save_path":ProjectSettings.globalize_path(save_path),"user_data_dir":OS.get_user_data_dir(),
		"frames_ms":frames_ms,"scope":"rendered save/load chain; frame series includes startup, not steady-state FPS"}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	world.free()
	await process_frame
	print("TRANSITION_MODAL_SAVE checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
