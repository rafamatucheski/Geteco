extends SceneTree
## Integração real Main/Vehicle/.NET, só com entrada de teste de pedal/troca.
## Nunca avança carros nem injeta eventos de chegada depois da largada. Exige --no-save.
var world
var checks := 0
var failures: Array[String] = []
var temporal: Node
var _weather_was_processing := true
var capture_output := ""

func _initialize() -> void:
	create_timer(300 if "--temporal" in OS.get_cmdline_user_args() or "--replay" in OS.get_cmdline_user_args() else 180).timeout.connect(func():
		if is_instance_valid(temporal):
			temporal.failure="Runtime watchdog elapsed"
			temporal.stop()
		push_error("DESERT_DRAG bounded timeout")
		quit(3))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DESERT_DRAG ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("--no-save required to protect player saves")
		quit(2)
		return
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Use compiled Godot .NET; fallback cannot validate drag integration")
		quit(2)
		return
	if "--temporal" in OS.get_cmdline_user_args() and DisplayServer.get_name()=="headless":
		push_error("--temporal requires actual rendered Main; headless cannot record lighting")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-out="):
			capture_output=argument.trim_prefix("--capture-out=")
	if not capture_output.is_empty():
		check(DisplayServer.get_name()!="headless","UI screenshots require rendered runtime")
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_output))==OK,"UI capture directory available")
		if not failures.is_empty(): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"actual Main .NET session ready")
	if not failures.is_empty(): finish(); return
	var session = world.session
	check(session.controller.no_save,"save protection enabled")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"actual .NET route backend loaded; fallback cannot pass")
	var intro: Dictionary = session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(session.state.intro.restore_snapshot(intro),"completed-intro fixture accepted")
	var fixture: Dictionary = preload("res://tests/fixtures/NorthGatewayFixtures.gd").full_snapshot(world.player.global_position,true,true)
	check(not fixture.is_empty() and session.state.campaign.restore_snapshot(fixture.campaign),"valid final campaign checkpoint unlocks desert without bypassing bridge policy")
	var desert = session.get("desert")
	check(is_instance_valid(desert) and is_instance_valid(desert.drag),"production coordinator installs real drag")
	if not failures.is_empty(): finish(); return
	var race = desert.drag
	# Ranked race isolation; physical queue admission is covered separately.
	race.open_meet.enabled = false
	check(world.production.travel("desert",race.staging_point),"desert region travel admitted")
	for i in 900:
		await physics_frame
		if not world.production.travel_busy and session.ready_for_play: break
	check(session.state.region_id=="desert","desert has supported ground")
	await frames(120)
	# O estacionamento da aproximação fica livre dos moradores autorais do encontro e do grid de largada.
	var style_car := "desert_mirage_gt" if "--style-car" in OS.get_cmdline_user_args() else "desert_mirage"
	if "--street-profile" in OS.get_cmdline_user_args(): style_car="porto_rosso"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--car="): style_car=argument.trim_prefix("--car=")
	var car = world.production.spawn_vehicle(style_car,race.staging_point+Vector3(0,.1,-6),-PI*.5)
	check(is_instance_valid(car),"production desert car spawned")
	if not is_instance_valid(car): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	await frames(4)
	check(world.driving.interact(),"ordinary vehicle interaction boards drag car")
	for i in 600:
		await physics_frame
		if world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	check(world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(),"ordinary boarding finishes and releases selected car controls")
	if not failures.is_empty(): finish(); return
	for hour in [8.0,15.0,23.0]:
		session.weather.time_of_day = hour/24.0
		check(race.nearest_action().get("target","")=="board","race board available at %dh"%int(hour))
		check(race.perform("start") and race.active,"ordinary race starts at %dh"%int(hour))
		check(is_equal_approx(session.weather.time_of_day,hour/24.0),"starting preserves world clock at %dh"%int(hour))
		race.cancel_attempt()
		await frames(3)
		check(not race.active and not car.input_locked and car.is_physics_processing(),"cancelling restores driving at %dh"%int(hour))
	session.weather.time_of_day = .9
	var previous_camera := root.get_camera_3d()
	var previous_listener := root.get_audio_listener_3d()
	var was_physics: bool = car.is_physics_processing()
	var previous_power: Variant = powertrain(car)
	check(race.perform("start"),"nearby night action builds two-car grid")
	if not race.active: finish(); return
	# O panorama cobre 42 células. Permite até 60 segundos para a prontidão;
	# o limite antigo de 900 ticks de física só permitia 15 segundos.
	var preparation_deadline := Time.get_ticks_msec()+60000
	check(is_zero_approx(race.elapsed) and is_equal_approx(race.countdown,3.0),"cold scenery preparation never advances the race clock or countdown")
	while race.phase=="preparing" and Time.get_ticks_msec()<preparation_deadline:
		await physics_frame
	check(race.phase=="staging" and world.production.regions.desert.drag_view_ready(),"full visible course is ready before countdown")
	if race.phase!="staging": finish(); return
	check(race.hud.rival=="Digo" and is_equal_approx(race.hud.remaining,800.0) and race.hud.headline=="3","HUD contains real rival distance and countdown before first render")
	await check_normal_ui(false,"race hides ordinary HUD and both objective indicators")
	check(race.racers.size()==2,"exactly Dante and one physical rival")
	check(race.racers[0].drive.car_id==style_car,"actual race drivetrain preserves the selected car profile")
	check(is_equal_approx(race.distance,800.0),"800 m category supports both stock and fully prepared 15–30 second builds")
	check(race.racers[1].car.archetype=="digo_gol_1993","first rival really drives Digo's Gol")
	check(race.racers.all(func(e): return e.car.collision_layer!=0 and e.car.collision_mask!=0),"both bodies retain collision")
	check(root.get_camera_3d()==race.race_camera,"dedicated race camera owns countdown and side view")
	check(root.get_audio_listener_3d()==race.race_listener and race.race_listener.get_parent()==car,"engine listener follows Dante instead of the expanding camera")
	await frames(2)
	check(race.racers.all(func(e): return e.car.equipment.lamps.any(func(mount): return mount.lamp.is_visible_in_tree() and mount.lamp.light_energy>0)),"both racers have an actual enabled headlight source")
	var near_camera: Dictionary = race.camera_frame(race.grid(0).origin,race.grid(1).origin)
	var far_camera: Dictionary = race.camera_frame(race.grid(0).origin,race.grid(1).origin-race.direction*150)
	check(is_equal_approx(float(near_camera.setback),16.5) and is_equal_approx(float(far_camera.setback),25.5),"side camera brings start closer and bounds far-gap framing")
	var view := root.get_visible_rect().grow(-40)
	check(race.racers.all(func(e): return view.has_point(race.race_camera.unproject_position(e.car.global_position+Vector3.UP*.7))),"both physical cars fit the close starting camera")
	var grid_center: Vector3 = (race.racers[0].car.global_position+race.racers[1].car.global_position)*.5
	check((race.race_camera.global_position-grid_center).dot(race.direction)<-12 and race.race_camera.global_position.y-grid_center.y>9,"countdown camera is high behind both cars")
	var tree_side: Vector3 = race.direction.cross(Vector3.UP).normalized()
	check([1.73,2.65].all(func(height): return view.has_point(race.race_camera.unproject_position(race.start_point+tree_side*6.2+Vector3.UP*height))),"whole physical traffic-light countdown fits rear view")
	check(session.blocks_driving_change() and not race.save_block_reason().is_empty(),"race owns boarding and save gates")
	var before: float = race.countdown
	session._menu("Pausa")
	await frames(15)
	check(is_equal_approx(race.countdown,before),"modal pauses countdown")
	session.close_menu()
	press_key(KEY_SPACE)
	check(not race.active and race.last_result.get("reason","")=="false_start","physical Space before green routes through Main input and disqualifies without result")
	await frames(3)
	check(root.get_camera_3d()==previous_camera and car.is_physics_processing()==was_physics and not car.input_locked,"false start restores camera normal physics controls")
	check(root.get_audio_listener_3d()==previous_listener,"false start restores previous listener or camera-based listening")
	check(race.snapshot().finishes==0,"false start grants no reward")
	await check_normal_ui(true,"false start restores ordinary HUD")
	check(race.perform("start"),"restart admitted after recovery")
	if not race.active: finish(); return
	await check_normal_ui(false,"restart suppresses ordinary HUD before public Q")
	var rivals: Array = race.racers.duplicate()
	press_key(KEY_Q)
	await frames(3)
	check(not race.active and race.last_result.get("reason","")=="cancelled" and not is_instance_valid(rivals[1].car),"physical Q abandons through Main input and removes only owned rival")
	check(powertrain(car)==previous_power and not world.player.input_locked,"abandon restores original powertrain audio and player lock")
	await check_normal_ui(true,"public Q cancellation restores ordinary HUD")
	if "--temporal" in OS.get_cmdline_user_args():
		if not failures.is_empty(): finish(); return
		if not await begin_temporal(race): finish(); return
	if "--drive" in OS.get_cmdline_user_args() or "--temporal" in OS.get_cmdline_user_args():
		check(race.perform("start"),"physical completion attempt starts")
		var result_action := "rematch" if "--replay" in OS.get_cmdline_user_args() else ("entry" if "--return-entry" in OS.get_cmdline_user_args() else "stay")
		await drive_race(race,car,result_action)
		if "--replay" in OS.get_cmdline_user_args() and race.active:
			check(race.rival_id=="digo","result rematch retains original opponent after ladder advances")
			await drive_race(race,car,"entry")
			check(race.perform("board"),"return-to-entry permits board reopening")
			race.board_controller.board.select_rival("digo")
			await capture_ui("rivals-rematch")
			race.board_controller.board.race_button.pressed.emit()
			check(race.active and race.rival_id=="digo","board can replay beaten rival without replaying the ladder")
			await drive_race(race,car,"stay")
	if is_instance_valid(temporal):
		temporal.segment = "night_cleanup"
		await temporal_hold(6.0,.9,.9)
		var report: Dictionary = temporal.stop()
		session.weather.set_process(_weather_was_processing)
		check(str(report.failure).is_empty() and float(report.duration_seconds)>=30.0,"continuous rendered temporal evidence spans at least30s without capture errors")
	await check_destruction(race,car)
	finish()

func check_destruction(race,car) -> void:
	# O caos só roda depois da sequência temporal limpa. Este reposicionamento da fixture fica
	# fora de toda tentativa; a corrida cronometrada acima é guiada inteiramente pela física dela.
	if race.active: return
	var at: Vector3 = race.staging_point+Vector3(0,.1,-6)
	var region = world.production.region
	check(region.prepare_collision_at(at),"post-capture return has physical staging support")
	await frames(3)
	car.global_position=at
	car.velocity=Vector3.ZERO
	car.horizontal_velocity=Vector3.ZERO
	car.speed=0
	world.player.teleport(at)
	region.set_focus(at)
	await frames(12)
	var finishes_before: int = race.snapshot().finishes
	check(race.perform("start"),"post-capture destruction attempt starts")
	if race.active:
		await check_normal_ui(false,"destruction attempt first suppresses ordinary HUD")
		race.racers[1].car.receive_damage(100000.0)
		await frames(3)
		check(not race.active and race.last_result.get("reason","")=="rival_interrupted","actual destroyed rival interrupts race without fabricated victory")
		check(race.snapshot().finishes==finishes_before and not car.input_locked and car.is_physics_processing(),"destruction preserves existing finish count and restores driver")
		await check_normal_ui(true,"rival destruction restores ordinary HUD")

func check_normal_ui(visible: bool, label: String) -> void:
	# Production HUD refreshes every80ms; allow its real lifecycle to update.
	# Do not call refresh manually, which would mask a broken restoration hook.
	var matched := false
	for i in 60:
		matched=world.hud.root_control.visible==visible
		if not visible: matched=matched and not world.session.marker.visible and not world.session.arrow.visible
		if matched: break
		await physics_frame
	check(matched,label)

func begin_temporal(race) -> bool:
	var requested := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--temporal-out="): requested=arg.trim_prefix("--temporal-out=")
	# Load only in capture mode; normal --drive does no capture setup or I/O.
	temporal = load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(temporal)
	_weather_was_processing = world.session.weather.is_processing()
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .5
	world.session.weather._update()
	await frames(15)
	var started: bool = temporal.begin(world,race,requested)
	check(started,"new isolated rendered temporal sequence opened")
	if not started:
		world.session.weather.set_process(_weather_was_processing)
		temporal.queue_free()
		temporal=null
		return false
	temporal.segment = "day_static"
	await temporal_hold(6.0,.5,.5)
	temporal.segment = "dusk_transition"
	await temporal_hold(6.0,.72,.90)
	temporal.segment = "night_static"
	await temporal_hold(6.0,.90,.90)
	check(temporal.recording,"temporal sequence remains writable through day/night transition")
	if not temporal.recording:
		world.session.weather.set_process(_weather_was_processing)
		return false
	temporal.segment = "drag"
	return true

func temporal_hold(seconds: float, from_time: float, to_time: float) -> void:
	var began := Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-began)/1000000.0<seconds:
		var ratio := clampf(float(Time.get_ticks_usec()-began)/(seconds*1000000.0),0,1)
		world.session.weather.time_of_day = lerpf(from_time,to_time,ratio)
		world.session.weather._update()
		await process_frame
	world.session.weather.time_of_day = to_time
	world.session.weather._update()

func drive_race(race,car,result_action: String = "stay") -> void:
	if not race.active: return
	var finishes_before: int=race.snapshot().finishes
	var rival_before: String=race.rival_id
	if finishes_before==0: await capture_ui("staging")
	var previous_power: Variant = race.racers[0].previous_power
	var previous_listener: AudioListener3D = race.previous_listener
	var deadline := Time.get_ticks_msec()+80000
	var paused := false
	var camera_bounded := true
	var far_gap_seen := false
	var far_indicator_correct := true
	var lamps_stayed_on := true
	var ordinary_ui_stayed_hidden := true
	while race.active and Time.get_ticks_msec()<deadline:
		if race.phase=="staging": race._throttle_override = .54
		else:
			race._throttle_override = 1.0
			race._nitro_override = true
			var drive = race.racers[0].drive
			if race.phase=="racing" and race.elapsed>.1:
				ordinary_ui_stayed_hidden=ordinary_ui_stayed_hidden and not world.hud.root_control.visible and not world.session.marker.visible and not world.session.arrow.visible
				var a: Vector3 = race.racers[0].car.global_position
				var b: Vector3 = race.racers[1].car.global_position
				var side: Vector3 = race.direction.cross(Vector3.UP).normalized()
				camera_bounded=camera_bounded and absf((race.race_camera.global_position-(a+b)*.5).dot(side))<=27.01
				lamps_stayed_on=lamps_stayed_on and race.racers.all(func(e): return e.car.equipment.lamps.any(func(mount): return mount.lamp.is_visible_in_tree() and mount.lamp.light_energy>0))
				var lead: float=(a-b).dot(race.direction)
				if absf(lead)>70:
					far_gap_seen=true
					far_indicator_correct=far_indicator_correct and race.hud.rival_offscreen==(-1 if lead>0 else 1)
			if drive.rpm>=drive.ideal_shift_rpm and race.phase=="racing": press_key(KEY_SPACE)
			if race.elapsed>.65 and not paused:
				paused = true
				if finishes_before==0: await capture_ui("racing")
				var before: float = race.elapsed
				var pose: Vector3 = car.global_position
				var camera_pose: Transform3D = race.race_camera.global_transform
				press_key(KEY_ESCAPE)
				for frame in 15: await process_frame
				check(paused and world.pause_panel.visible and not race.layer.visible,"actual pause hides drag instruments under readable pause controls")
				check(is_equal_approx(race.elapsed,before) and car.global_position.distance_to(pose)<.01,"pause freezes both motion and race clock")
				check(race.race_camera.global_transform.is_equal_approx(camera_pose),"pause freezes launch camera sweep and resumes from same pose")
				var resume: Button=world.pause_panel.get_node("%BtnResume")
				check(resume.is_visible_in_tree() and root.get_visible_rect().encloses(resume.get_global_rect()),"pause resume button stays visible within viewport")
				if finishes_before==0: await capture_ui("paused")
				press_key(KEY_ESCAPE)
				check(not world.pause_panel.visible and race.layer.visible,"resume restores race instruments")
		await physics_frame
	check(not race.active and race.last_result.get("finished",false),"physical distance crossing produces completed race")
	check(camera_bounded,"actual moving camera stays within27m lateral setback")
	check(lamps_stayed_on,"both real headlight sources remain enabled throughout race")
	check(ordinary_ui_stayed_hidden,"ordinary HUD and objective indicators remain suppressed during moving race")
	if far_gap_seen: check(far_indicator_correct,"large real lead displays opponent arrow on the correct screen side")
	print("DESERT_DRAG_RESULT ",JSON.stringify(race.last_result))
	if race.last_result.get("finished",false):
		check(race.last_result.seconds>=15 and race.last_result.seconds<=30,"entry-class physical race lasts 15–30 seconds")
		check(race.snapshot().finishes==finishes_before+1 and rival_before in race.snapshot().completed_rivals,"actual finish persisted exactly once")
	# Every physical finish stays open, including defeats and repeat victories.
	await frames(3)
	var flow=race.board_controller
	check(race.session.modal and is_instance_valid(flow.results_layer) and flow.results_layer.visible,"every finish opens persistent result actions")
	var finished_pose: Vector3=car.global_position
	var finished_count: int=race.snapshot().finishes
	race._finish()
	check(race.snapshot().finishes==finished_count,"duplicate finish callback cannot record a second race")
	await frames(60)
	check(flow.results_layer.visible and car.global_position.distance_to(finished_pose)<.1,"result waits for a decision without rolling away")
	check(flow.results.buttons.size()==3,"result offers rematch return-to-entry and stay")
	await capture_ui("result-%d"%finished_count)
	flow.results.get_node(result_action).pressed.emit()
	for i in 120:
		await physics_frame
		if result_action=="rematch" and race.active: break
		if result_action!="rematch" and not race.session.modal: break
	if result_action=="rematch":
		check(race.active and race.rival_id==rival_before and not race.session.modal,"rematch button starts same rival with fresh race state")
		return
	check(not race.session.modal and not flow.results_layer.visible,"result action restores free driving")
	if result_action=="entry":
		check(car.global_position.distance_to(race.staging_point)<16,"return-to-entry places car on supported staging ground")
	else:
		check(car.global_position.distance_to(finished_pose)<.2,"stay keeps the driver at the physical finish")
	check(car.is_physics_processing() and not car.input_locked and powertrain(car)==previous_power,"finish restores car ownership and normal drivetrain")
	check(root.get_audio_listener_3d()==previous_listener,"finish restores previous audio listener")
	check(not car.has_meta("desert_drag_physics") and not Input.is_physical_key_pressed(KEY_SPACE) and not Input.is_physical_key_pressed(KEY_Q),"finish clears race ownership and injected physical keys are released")
	await check_normal_ui(true,"real finish restores ordinary HUD")

func session_menu(session,title: String) -> void:
	session._menu(title)

func capture_ui(label: String) -> void:
	if capture_output.is_empty(): return
	await RenderingServer.frame_post_draw
	var path := capture_output.path_join(label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"captured "+label)

func press_key(code: int) -> void:
	# Exercise Main's actual input routing, including handled-event ownership.
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		event.echo = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func powertrain(car) -> Variant:
	return car.get_meta("desert_powertrain") if car.has_meta("desert_powertrain") else null

func finish() -> void:
	if is_instance_valid(temporal) and temporal.recording: temporal.stop()
	print("DESERT_DRAG_RUNTIME checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
