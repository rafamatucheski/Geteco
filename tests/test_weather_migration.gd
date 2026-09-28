extends SceneTree
var world
var errors: Array[String] = []
var checks := 0
var capture_folder := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_folder = arg.trim_prefix("--capture-dir=")
	if not capture_folder.is_empty(): DirAccess.make_dir_recursive_absolute(capture_folder)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session!=null and world.session.weather!=null: break
	if world.session==null or world.session.weather==null: quit(2); return
	world.player.controlled_automatically = true
	world.session.cold.set_process(false)
	var weather = world.session.weather
	weather.set_process(false)
	weather._weather_rng.seed = 28092026
	var counts := [0,0,0,0]
	for i in 1000:
		weather.weather_timer = 0
		weather._process(0)
		counts[weather.weather_state] += 1
		check(weather.weather_timer>=90 and weather.weather_timer<=180,"Natural weather duration remains bounded")
	check(counts[2]>0 and counts[2]<counts[1] and counts[2]<counts[3],"Natural storms occur less often than drizzle and overcast")
	check(counts[0]>0 and counts[1]>0 and counts[3]>0,"Natural cycle retains clear, drizzle and overcast")
	weather.weather_timer = 10000
	weather.weather_state = 1
	weather.rain_intensity = .22
	weather._update()
	var mixer = weather.weather_audio
	mixer.set_process(false)
	mixer._process(3.1)
	check(mixer.layers.size()==3,"V1 three rain layers installed")
	check(mixer.layers[0].playing and mixer.layers[1].playing,"Rain bed and surface drops play")
	check(not mixer.layers[2].playing,"Drizzle does not play heavy sheets")
	var drizzle_ratio: float = weather.precipitation.amount_ratio
	var drizzle_sky: Color = weather.controller.environment.environment.background_color
	check(drizzle_ratio>0 and drizzle_ratio<.5,"Natural rain is visibly light")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(mixer.bus_name))==&"Ambient","Weather obeys Ambient slider")
	await capture("drizzle")
	weather.weather_state = 2
	weather._update()
	mixer._process(3.1)
	check(weather.controller.environment.environment.background_color.get_luminance()<drizzle_sky.get_luminance(),"Storm sky is darker than drizzle")
	check(mixer.layers[2].playing,"Storm adds heavy sheet layer")
	check(weather.precipitation.amount_ratio>drizzle_ratio*2,"Storm density differs from drizzle")
	var storm = weather.storm
	storm.set_process(false)
	var sun = weather.controller.sun
	var base: float = sun.light_energy
	check(storm.trigger_lightning(),"Explicit storm supports lightning")
	storm._process(.05)
	check(sun.light_energy>base,"Lightning illuminates world")
	check(not mixer.thunder.playing,"Thunder is delayed after flash")
	await capture("lightning")
	storm._process(3.3)
	check(mixer.thunder.playing and storm.thunder_count==1,"Delayed original thunder plays")
	check(is_equal_approx(sun.light_energy,base),"Flash restores light without accumulating energy")
	await capture("storm")
	var normal_gain: float = mixer.layers[0].volume_db
	mixer.set_dialogue_focus(true)
	mixer._process(.3)
	check(mixer.layers[0].volume_db<normal_gain-5,"Dialogue ducks rain")
	mixer.set_dialogue_focus(false)
	storm.trigger_lightning()
	var entered: bool = await world.session.enter_place("maciota",false)
	check(entered,"Real garage entry")
	weather._update()
	check(not weather.precipitation.visible and not weather.surface_effects.mist.visible,"Garage hides exterior particles")
	check(storm.thunder_delay<0 and not mixer.thunder.playing,"Entering garage cancels pending thunder")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(mixer.bus_name)),"Garage silences exterior weather bus")
	check(not world.session.state.weapons_allowed(),"Garage weapon restriction remains")
	check(weather.weather_state==2,"Shelter preserves storm state")
	await capture("garage")
	if entered: check(await world.session.leave_place(),"Real garage exit")
	weather._update()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(mixer.bus_name)),"Exit restores weather bus")
	check(weather.precipitation.emitting,"Exit restores storm rain")
	world.session.cold.model.weather_clock = 120
	world.player.teleport(Vector3(718,.08,-479))
	world.production._update_physical_residency(world.player.position)
	world.production._update_logical_region(world.player.position)
	weather._update()
	check(weather.hail.emitting and weather.snow.emitting,"Mountain preserves snow and hail together")
	check(not storm.trigger_lightning(),"Harbor lightning cannot leak into mountain")
	for i in 90: await physics_frame
	check(weather.surface_effects.impact_count>0,"Hail produces impacts on real mountain collision")
	check(weather.surface_effects.shards.multimesh.instance_count==120,"Shard pool remains bounded")
	check(weather.surface_effects.mist.emitting,"Mountain haze has local motion")
	await capture("hail")
	world.player.teleport(Vector3(600,.08,-285))
	weather._update()
	check(not weather.surface_effects.mist.visible and not weather.surface_effects.shards.visible,"Tunnel hides mist and ice immediately")
	var saved_time: float = weather.time_of_day
	weather._process(.25)
	check(weather.time_of_day>saved_time,"Clock advances under shelter")
	weather.time_of_day = .25
	weather._process(14.4)
	check(is_equal_approx(weather.time_of_day,.26),"Productive V1 day lasts 24 minutes")
	weather.time_of_day = .9999
	var previous_moon: int = weather.moon_day()
	weather._process(1.44)
	check(weather.moon_day()==previous_moon+1 and weather.time_of_day<.01,"Midnight preserves V2 lunar progression")
	var bus: StringName = mixer.bus_name
	world.queue_free()
	await process_frame
	await process_frame
	check(AudioServer.get_bus_index(bus)==-1,"Session cleanup removes private weather bus")
	print("WEATHER_MIGRATION ",checks," checks; errors=",errors)
	quit(0 if errors.is_empty() else 1)

func capture(label: String) -> void:
	if capture_folder.is_empty() or DisplayServer.get_name()=="headless": return
	world.session.weather._process(0)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_folder+"/"+label+".png")==OK,"Capture "+label)
