extends "res://artifacts/rachas-implementation-20261018/measure_design.gd"
## Three finite Main windows: physical 800 m passes at day/night and a slow
## dusk return probe. Global storm never overrides the desert's dry climate.
const TEMPORAL:=preload("res://tests/capture/DesertDragTemporalCapture.gd")
const TRACE:=preload("res://runtime/StallWorkTrace.gd")
var failures: Array[String]=[]
var weather_events: Array[Dictionary]=[]
var startup_cost: Dictionary={}
var ground_report: Dictionary={}

func run() -> void:
	var fixture_only := "--validate-fixture" in OS.get_cmdline_user_args()
	if (DisplayServer.get_name()=="headless" and not fixture_only) or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	TranslationServer.set_locale("pt_BR")
	var headlights_only := "--night-headlights" in OS.get_cmdline_user_args()
	var slow_only := "--slow-cover" in OS.get_cmdline_user_args()
	output=FIXTURE.output_dir("drag-cover-temporal" if slow_only else ("drag-headlights" if headlights_only else "drag-environment"))
	var at: Vector3=LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary=FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.time=.45
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	if headlights_only:
		# Isolated prerequisite checkpoint, using the actual Digo time from the
		# preceding capture. The recorded scenario itself still drives the race.
		preload("res://activities/desert_drag/DesertDragProgress.gd").record_finish(data.world,"digo",true,19.9385238787293)
		preload("res://systems/campaign/DigoProgress.gd").complete_desert_race(data.world,"digo_desert_race",true)
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not prepared(not path.is_empty(),"isolated checkpoint validates through GameState and SaveStore"): return
	if fixture_only: quit(0); return
	if slow_only: TRACE.start_aggregate()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not prepared(world.session!=null and world.session.ready_for_play,"Main session ready"): return
	if not prepared(world.session.state.region_id=="desert" and not world.session.controller.save_invalid,"intended desert checkpoint restored"): return
	world.dispatch.router.nearest_edge(at)
	if not prepared(world.dispatch.router._native!=null,"native C# route backend active"): return
	root.mode=Window.MODE_WINDOWED
	var session=world.session
	var race=session.desert.drag
	race.open_meet.enabled=false
	world.gameplay.god_mode=true
	# Keep the pedestrian out of the admission hull; spawn_vehicle correctly
	# rejects a car created on top of the player.
	var car=world.production.spawn_vehicle("desert_mirage",at+Vector3(0,0,-6),-PI*.5)
	if not prepared(is_instance_valid(car),"player car admitted beside the pedestrian"): return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not prepared(world.driving.interact(),"ordinary boarding begins"): return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not prepared(world.driving.occupied and not car.input_locked,"ordinary boarding returns control"): return
	var region=world.production.regions.desert
	for i in 1800:
		await process_frame
		if region.is_streaming_idle(): break
	if not prepared(region.drag_view_cells.size()==26 and region.drag_view_pending.is_empty(),"26 course cells prepared"): return
	await RenderingServer.frame_post_draw
	if slow_only: startup_cost=TRACE.stop_aggregate()
	write_ground_inventory()
	var weather=session.weather
	weather.time_scale=0
	weather.weather_locked=true
	weather.weather_timer=10000
	if slow_only:
		await slow_window(race)
	elif headlights_only:
		await physical_window("night_headlights",.9,2,race)
	else:
		await physical_window("day_dry",.45,0,race)
		await slow_window(race)
		await physical_window("night_rain",.9,2,race)
	var file:=FileAccess.open(output.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"windows":results,"weather_events":weather_events,"ground_cover":ground_report,"startup_cost":startup_cost,"no_save":true,"native":true},"\t"))
	file.close()
	print("DRAG_ENVIRONMENT_DONE ",output," failures=",failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)

func prepared(ok: bool,label: String) -> bool:
	print("DRAG_ENVIRONMENT ","PASS " if ok else "FAIL ",label)
	if not ok: quit(1)
	return ok

func write_ground_inventory() -> void:
	# Record settled renderer AABBs, independently of the construction-time test.
	var inventory: Array[Dictionary] = []
	var instances:=0
	var invalid:=0
	var largest:=0.0
	for node in world.find_children("DesertGroundCover_*","MultiMeshInstance3D",true,false):
		var material = node.material_override as StandardMaterial3D
		if material==null or material.distance_fade_mode==BaseMaterial3D.DISTANCE_FADE_DISABLED: continue
		var bounds: AABB=node.get_aabb()
		var required: float=material.distance_fade_min_distance+bounds.size.length()*.5
		instances+=node.multimesh.instance_count
		largest=maxf(largest,maxf(bounds.size.x,bounds.size.z))
		if not bounds.has_volume() or node.visibility_range_end+0.0001<required+2.0: invalid+=1
		# The final name component is the kind for both historical and split lots.
		inventory.append({"path":str(node.get_path()),"kind":str(node.name).split("_")[-1],"instances":node.multimesh.instance_count,"aabb_position":[bounds.position.x,bounds.position.y,bounds.position.z],"aabb_size":[bounds.size.x,bounds.size.y,bounds.size.z],"computed_aabb":node.multimesh.custom_aabb.has_volume(),"end":node.visibility_range_end,"required_end":required,"fade_near":material.distance_fade_max_distance,"fade_far":material.distance_fade_min_distance})
	ground_report={"batches":inventory.size(),"instances":instances,"invalid_bounds_or_margin":invalid,"largest_planar_aabb_m":largest}
	if invalid>0: failures.append("ground cover bounds/margin invalid: %d"%invalid)
	var file:=FileAccess.open(output.path_join("ground_cover.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(inventory,"\t"))
	file.close()

func set_weather(hour: float,state: int) -> void:
	var weather=world.session.weather
	weather.time_of_day=hour
	weather.weather_state=state
	weather.weather_timer=10000
	weather._update()
	if is_instance_valid(weather.storm):
		weather.storm.cancel()
		weather.storm._rng.seed=18102026
		weather.storm.lightning_timer=14.0
	await hold(5)

func recorder(label: String,race):
	var capture_node:=TEMPORAL.new()
	root.add_child(capture_node)
	if not capture_node.begin(world,race,output.path_join(label),1200):
		failures.append("capture failed: "+label)
		return null
	capture_node.segment=label
	capture_node._report.clock_control="Fixed clock/weather in isolated Main fixture; day 0.45 clear, dusk 0.76 clear, night 0.90 global storm. Regional desert dryness is preserved, so this does not certify visible rain. Original game weather presentation keeps updating."
	capture_node._report.coverage=label+": actual Main lighting, scenery and retained course; 30-second finite window"
	capture_node._report.not_covered=["whole map","other vehicle profiles","audible mix preference","performance"]
	return capture_node

func physical_window(label: String,hour: float,state: int,race) -> void:
	await set_weather(hour,state)
	print("DRAG_ENVIRONMENT_WINDOW ",label)
	if not race.perform("start"):
		failures.append(label+": "+race.start_block_reason())
		return
	race._rng.seed=2247
	race._rival_wait=.32
	var capture_node=recorder(label,race)
	if capture_node==null: return
	var began:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-began<30200000:
		if race.active:
			race._throttle_override=.54 if race.phase=="staging" else 1.0
			race._nitro_override=race.phase=="racing"
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		capture_node.segment=label+"_"+(str(race.phase) if race.active else "result")
		var weather=world.session.weather
		weather_events.append({"window":label,"usec":Time.get_ticks_usec(),"state":weather.weather_state,"rain_level":weather.rain_level,"rain_at_player":weather.rain_strength_at(world.player.global_position),"precipitation_emitting":weather.precipitation.emitting,"flash_age":weather.storm.flash_age,"flashes":weather.storm.flashes})
		await physics_frame
	var report: Dictionary=capture_node.stop()
	# Capture windows stay bounded at 30 s. A slower rival may still be
	# braking; let the ordinary cleanup finish outside the recorded window.
	var finish_deadline:=Time.get_ticks_msec()+12000
	while race.active and Time.get_ticks_msec()<finish_deadline:
		race._throttle_override=1.0
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		await physics_frame
	results[label]={"frames":report.frame_count,"seconds":report.duration_seconds,"skipped":report.skipped_rendered_frames,"failure":report.failure,"race_result":race.last_result.duplicate(true)}
	if not str(report.failure).is_empty() or float(report.duration_seconds)<30.0: failures.append(label+": insufficient temporal evidence")
	if not bool(race.last_result.get("finished",false)): failures.append(label+": actual race did not finish")
	if race.active: race.cancel_attempt()
	if not world.session.modal: world.session._menu("Pausa")
	if not await race.return_to_entry(): failures.append(label+": return failed")
	world.session.close_menu()
	capture_node.queue_free()
	await hold(2)

func slow_window(race) -> void:
	await set_weather(.76,0)
	print("DRAG_ENVIRONMENT_WINDOW dusk_slow_return")
	var original_camera:=root.get_camera_3d()
	var camera:=Camera3D.new()
	camera.name="ProductionDragFrameSlowProbe"
	camera.fov=57
	camera.far=2200
	camera.near=.2
	world.add_child(camera)
	camera.make_current()
	var capture_node=recorder("dusk_slow_return",race)
	if capture_node==null: camera.queue_free(); return
	capture_node._report.coverage="Main at dusk; controlled 45 m side-camera approach/retreat using DesertDrag.camera_frame. Supplementary visual probe, not a physical reverse race."
	var began:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-began<30200000:
		var elapsed:=float(Time.get_ticks_usec()-began)/1000000.0
		var x: float=-630.0+sin(elapsed*TAU/30.0)*45.0
		var frame: Dictionary=race.camera_frame(Vector3(x,0,-1318),Vector3(x,0,-1322))
		camera.global_position=frame.position
		camera.look_at(frame.target,Vector3.UP)
		await process_frame
	var report: Dictionary=capture_node.stop()
	results.dusk_slow_return={"frames":report.frame_count,"seconds":report.duration_seconds,"skipped":report.skipped_rendered_frames,"failure":report.failure}
	if not str(report.failure).is_empty() or float(report.duration_seconds)<30.0: failures.append("dusk: insufficient temporal evidence")
	if is_instance_valid(original_camera): original_camera.make_current()
	camera.queue_free()
	capture_node.queue_free()
	await hold(2)
