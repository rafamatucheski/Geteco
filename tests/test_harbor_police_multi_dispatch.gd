extends SceneTree

## Regression for a real bug found reproducing the 2026-09-06 gameplay
## recording ("resposta policial real com wanted alto"): at high wanted
## levels, WantedManager._dispatch_police() intends up to five simultaneous
## cruisers and calls HarborEmergencyDirector.request_dispatch("police", ...)
## again every ~3s while under that cap to bring in backup. But
## request_dispatch deduplicated by "service:target_instance_id" alone and
## always handed back the first cruiser it ever dispatched for that target,
## as long as it was still visible/undamaged/still assigned to that target --
## which, mid-pursuit (target still fleeing, still valid), it always was.
##
## Reproduced live at 6 stars with a real, continuously player-driven car:
## only one cruiser was ever simultaneously active for ~12 seconds while the
## player's car took repeated solo ramming damage, even though the cap
## allowed four. Fixed by only deduplicating fire/ambulance/coroner (a
## burning car never needs a second engine); police dispatch now always
## attempts a fresh unit, relying on WantedManager's own
## active_police_count/max_active_cruisers cap (already checked before this
## is ever called) to bound how many actually spawn.
##
## This test drives a real HarborPreview.tscn, a real PlayerCar under
## continuous throttle (so the pursuit target stays valid, fleeing, and
## never lets the first cruiser complete its engagement and idle back into
## the pool -- the exact condition that hid this bug from a quick, static
## check), and counts genuinely simultaneous, visible, distinct cruisers.

const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var failures: Array[String] = []
	var packed := load(PREVIEW_PATH) as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	var build_deadline := Time.get_ticks_msec() + 60000
	while not scene.world_build_ready and Time.get_ticks_msec() < build_deadline:
		await process_frame
	if not scene.world_build_ready:
		printerr("Harbor preview did not finish building")
		quit(2)
		return

	var wanted = root.get_node("WantedManager")
	wanted.reset_crime()
	# Advance wanted time explicitly: headless process FPS is not fixed at 60.
	wanted.set_process(false)
	var player: CharacterBody2D = scene.get_node("Player")
	var car: CharacterBody2D = scene.get_node("PlayerCar")
	player.global_position = car.global_position + Vector2(-48, 0)
	car.enter_vehicle(player)
	for i in 5:
		await process_frame

	wanted.report_crime(240) # straight to 6 stars: cap allows 5 simultaneous cruisers

	var distinct_cruisers := {}
	var max_simultaneous := 0
	for i in 1500: # 25 simulated seconds: four-second dispatch cadence at six stars.
		Input.action_press("ui_up") # keep the target fleeing and valid
		wanted._process(1.0 / 60.0)
		await process_frame
		var active := 0
		for em in get_nodes_in_group("emergency_vehicle"):
			if is_instance_valid(em) and int(em.get("type")) == 0 and em.visible:
				active += 1
				distinct_cruisers[em.get_instance_id()] = true
		max_simultaneous = maxi(max_simultaneous, active)
	Input.action_release("ui_up")

	print("HARBOR_POLICE_MULTI_DISPATCH max_simultaneous=%d distinct_seen=%d (pursuit cap=5)" % [
		max_simultaneous, distinct_cruisers.size()
	])
	if max_simultaneous != 5:
		failures.append(
			"Expected the five-vehicle ceiling during a sustained 6-star pursuit, observed %d" % max_simultaneous
		)

	# Autoload pool units outlive this scene; stop their callbacks before
	# destroying their pursuit target and road network during test teardown.
	wanted.set_process(false)
	for vehicle in get_nodes_in_group("emergency_vehicle"):
		vehicle.set_physics_process(false)
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("HARBOR_POLICE_MULTI_DISPATCH: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("  - %s" % f)
		print("HARBOR_POLICE_MULTI_DISPATCH: FAIL (%d)" % failures.size())
		quit(1)
