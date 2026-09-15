extends SceneTree
const SCHEDULE := preload("res://world/harbor/campaign/ChapterOneSchedule.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("SCHEDULE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func frames(n := 4) -> void:
	for i in n: await process_frame
func run() -> void:
	create_timer(180, true, false, true).timeout.connect(func(): quit(2))
	check(is_equal_approx(SCHEDULE.forward_days(.5,"cobra_race"), .375), "noon advances to 21:00")
	check(is_equal_approx(SCHEDULE.forward_days(23.5/24.0,"cobra_race"), 21.5/24.0), "late arrival waits forward to next evening")
	check(SCHEDULE.forward_days(22.0/24.0,"cobra_race") == 0, "same evening does not skip a day")
	check(SCHEDULE.forward_days(.5,"unknown") == 0, "unknown job does not mutate time")
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("chapter_schedule_%d" % OS.get_process_id()) + "/"
	saves.clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]: campaign.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var world = current_scene
	while not world.gameplay_ready: await process_frame
	var bridge = world.get_node("CobraCampaign")
	var player = world.get_node("Player")
	bridge.ledger.data.completed.cobra_contact = true
	bridge.ledger.data.day_elapsed = .15*600.0
	world.weather.time_of_day = .5
	await frames(3)
	var before: float = world.weather.time_of_day
	bridge._selected("cobra_race")
	check(bridge.runtime.active_id == "" and abs(world.weather.time_of_day-before)<.001, "remote acceptance does not start or skip time")
	var garage_door = world.get_node("District/Garage/Entrance")
	player.global_position = garage_door.get_node("OutsideReturn").global_position
	await frames(8)
	check(garage_door.request_interaction(player),"scheduled mission enters garage through real door")
	await create_timer(1.1).timeout
	check(bridge.garage.contains_point(player.global_position),"arrival at garage finishes before accepting scheduled mission")
	# The board node is the authored approach point. Adding 25px puts Dante
	# past this compact garage's front boundary, outside its valid floor.
	player.global_position = bridge.board.global_position
	bridge.ledger.data.day_elapsed = .15*600.0
	world.weather.time_of_day = .5
	before = .5
	var wanted = root.get_node("WantedManager")
	wanted.current_stars = 1
	bridge._selected("cobra_race")
	check(bridge.runtime.active_id == "" and abs(world.weather.time_of_day-before)<.001, "wanted cannot use time skip to escape police")
	while bridge._dialog.visible: bridge._next_message()
	wanted.current_stars = 0
	campaign.bank_incident = {"phase":"closed","elapsed_days":1.0}
	bridge._selected("cobra_race")
	check(bridge.runtime.active_id == "cobra_race", "board acceptance starts available mission")
	check(is_equal_approx(world.weather.time_of_day,21.0/24.0), "acceptance sets real night clock")
	check(absf(float(campaign.bank_incident.elapsed_days)-1.375)<.01,"scheduled wait also advances bank investigation days")
	check(bridge._fade.visible and bridge._time_transition, "time transition is visible")
	var day: int = bridge.ledger.data.day
	bridge._selected("cobra_race")
	check(bridge.ledger.data.day == day, "double acceptance cannot advance day twice")
	await create_timer(1.0, true).timeout
	while bridge._dialog.visible: bridge._next_message()
	await frames(5)
	check(world.weather.time_of_day >= .875 and world.weather.time_of_day < .89, "regular bridge tick preserves night")
	check(bridge._objective_card.visible and not player.is_control_disabled, "objective readable and controls return after briefing")
	check(not bridge.rest(), "rest unavailable in active mission")
	# The board is in the garage; let the event clear normal traffic before
	# placing the fixture car on the starting grid.
	var clear_deadline := Time.get_ticks_msec() + 95000
	while bridge.runtime.active_id == "cobra_race" and not bridge.runtime._race_traffic.is_clear() and Time.get_ticks_msec() < clear_deadline:
		await physics_frame
	check(bridge.runtime.active_id == "cobra_race" and bridge.runtime._race_traffic.is_clear(), "event clears real traffic before staging")
	if bridge.runtime.active_id != "cobra_race": quit(1); return
	bridge.ledger.data.day_elapsed = .15*600.0
	world.weather.time_of_day = .5
	check(bridge.ensure_race_night(), "late player can wait for next night at grid")
	check(is_equal_approx(world.weather.time_of_day,.875), "late grid arrival is still a night race")
	await create_timer(1.0,true).timeout
	var exited := [false]
	world.get_node("Interiors").actor_returned_to_exterior.connect(func(actor,_id):
		if actor == player: exited[0]=true
	, CONNECT_ONE_SHOT)
	player.global_position = bridge.garage.exit_door.global_position + Vector2(0,-20)
	player.reset_physics_interpolation()
	for i in 3: await physics_frame
	# This garage has a thin automatic threshold, not a broad E interaction.
	for i in 180:
		root.get_node("GameInput").touch_move = Vector2.DOWN
		await physics_frame
		if exited[0]: break
	root.get_node("GameInput").touch_move = Vector2.ZERO
	await create_timer(1.1).timeout
	check(exited[0],"night departure uses real garage exit")
	check(not world.weather.is_inside_interior and world.weather.color.r<.6,"outside lighting is night after scheduled departure")
	var car = world.get_node("PlayerCar")
	car.global_position = bridge.runtime.RACE_START
	car.global_rotation = -PI/2.0
	car.velocity = Vector2.ZERO
	player.global_position = car.global_position + Vector2(-45,0)
	car.enter_vehicle(player)
	while car.has_meta("vehicle_boarding"): await process_frame
	wanted.current_stars = 1
	check(not bridge.ensure_race_night() and bridge._dialog.visible,"wanted driver receives explicit reason instead of a silent R")
	while bridge._dialog.visible: bridge._next_message()
	wanted.current_stars = 0
	check(bridge.ensure_race_night(),"seated driver is allowed to stage the night trial")
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_R
		event.keycode = KEY_R
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)
	check(bridge.runtime._race_started and bridge._dialog.visible,"real R starts countdown through production bridge")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/chapter-one-0913/race-briefing.png")
	while bridge._dialog.visible: bridge._next_message()
	await frames(6)
	world.get_node("Minimap").call("_process", .8)
	check(bridge._objective_card.visible,"driving keeps the trial objective visible")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/chapter-one-0913/race-countdown.png")
	if "--measure-race" in OS.get_cmdline_user_args():
		var samples: Array[float] = []
		var started := Time.get_ticks_usec()
		var previous := started
		while Time.get_ticks_usec()-started < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous=now
		var sorted := samples.duplicate()
		sorted.sort()
		var report := {"scenario":"active trial, stationary driver, production HarborGame","seconds":float(previous-started)/1000000.0,"frames":samples.size(),"fps":samples.size()*1000000.0/(previous-started),"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted[-1],"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"viewport":str(root.size),"samples_ms":samples}
		FileAccess.open("D:/geteco/artifacts/chapter-one-0913/after-active-race.json",FileAccess.WRITE).store_string(JSON.stringify(report))
		print("ACTIVE_RACE_PERF fps=",report.fps," p95=",report.p95," p99=",report.p99)
		check(bridge.runtime.active_id == "cobra_race" and bridge.runtime._countdown<=0,"active trial stays valid during 30-second rendered sample")
	var saved_time: float = fposmod(.35+float(bridge.ledger.data.day_elapsed)/600.0,1.0)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	campaign.restore_from_save(snapshot)
	check(is_equal_approx(fposmod(.35+float(bridge.ledger.data.day_elapsed)/600.0,1.0),saved_time),"campaign snapshot retains the current scheduled clock after gameplay")
	bridge._toggle_journal()
	check(bridge._journal.visible and paused and bridge._cancel_race_button.visible,"driver can pause and cancel from journal")
	var wallet: int = player.money
	bridge._cancel_race_button.pressed.emit()
	check(bridge.runtime.active_id == "" and player.money == wallet,"cancel releases trial without charging player")
	while bridge._dialog.visible: bridge._next_message()
	check(car.is_physics_processing() and not paused,"cancel restores car physics and world pause")
	car.exit_vehicle()
	check(bridge.ledger.get_status("cobra_race").available,"failed trial is offered again")
	world.queue_free()
	await frames()
	check(not paused,"scene cleanup returns pause state")
	print("CHAPTER_SCHEDULE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
