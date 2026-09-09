extends SceneTree

## Regression for a real bug found reproducing the 2026-09-06 gameplay
## recording ("resposta policial real com wanted alto"): at high wanted
## levels, WantedManager._dispatch_police() intends up to
## min(current_stars, 4) simultaneous cruisers (EmergencyPool.POOL_SIZE_POLICE
## == 4) and calls HarborEmergencyDirector.request_dispatch("police", ...)
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

const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"

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
	for i in 90:
		await process_frame

	var wanted = root.get_node("WantedManager")
	wanted.reset_crime()
	var player: CharacterBody2D = scene.get_node("Player")
	var car: CharacterBody2D = scene.get_node("PlayerCar")
	player.global_position = car.global_position + Vector2(-48, 0)
	car.enter_vehicle(player)
	for i in 5:
		await process_frame

	wanted.report_crime(210) # straight to 6 stars: cap allows 4 simultaneous cruisers

	var distinct_cruisers := {}
	var max_simultaneous := 0
	for i in 1500: # 25s: real dispatch cadence is ~3s per attempt while under cap
		Input.action_press("ui_up") # keep the target fleeing and valid
		await process_frame
		var active := 0
		for em in get_nodes_in_group("emergency_vehicle"):
			if is_instance_valid(em) and int(em.get("type")) == 0 and em.visible:
				active += 1
				distinct_cruisers[em.get_instance_id()] = true
		max_simultaneous = maxi(max_simultaneous, active)
	Input.action_release("ui_up")

	print("HARBOR_POLICE_MULTI_DISPATCH max_simultaneous=%d distinct_seen=%d (pool cap=4)" % [
		max_simultaneous, distinct_cruisers.size()
	])
	if max_simultaneous < 3:
		failures.append(
			"Only %d cruiser(s) were ever simultaneously active during a sustained 6-star pursuit -- backup never properly escalates even though the pool allows up to 4" % max_simultaneous
		)

	# Fire/ambulance/coroner must still dedup to a single unit per target --
	# this fix must not weaken that contract (test_harbor_emergency_dispatch.gd
	# covers this fully; this is a quick, local double-check on this fix).
	var director := get_first_node_in_group("emergency_depot_director")
	var fire_target := Node2D.new()
	fire_target.position = Vector2(1200, 2100)
	scene.add_child(fire_target)
	var fire_a = director.request_dispatch("fire", fire_target, false)
	var fire_b = director.request_dispatch("fire", fire_target, false)
	if fire_a == null or fire_a != fire_b:
		failures.append("fire dispatch no longer deduplicates to one engine per target -- this fix must not touch that contract")

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
