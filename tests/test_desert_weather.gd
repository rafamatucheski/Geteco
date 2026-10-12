extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	create_timer(150).timeout.connect(func(): quit(3))
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var folder := FIXTURE.output_dir("desert-weather-contract")
	var path := FIXTURE.write_fixture(folder,"checkpoint.json",FIXTURE.full_snapshot(Vector3(77,.08,96),true))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(2); return
	world.player.controlled_automatically = true
	var weather = world.session.weather
	weather.set_process(false)
	weather.weather_state = 2
	weather.weather_timer = 10000
	world.player.teleport(Vector3(77,.08,96))
	weather._process(0)
	weather._update()
	check(weather.precipitation.emitting,"City storm rains")
	check(weather.storm.trigger_lightning(),"City storm can flash")
	for point in [Vector3(345,.08,-415),Vector3(345,.08,-742)]:
		world.player.teleport(point)
		weather._process(0)
		weather._update()
		if point.z == -415:
			check(weather.precipitation.amount_ratio>.1 and weather.precipitation.amount_ratio<.9,"Boundary crossfades rain")
	check(not weather.precipitation.visible and not weather.precipitation.emitting,"Desert hides existing drops and stops rain")
	check(weather.weather_audio.target_intensity==0,"Desert stops rain audio")
	check(not weather.storm.trigger_lightning() and weather.storm.thunder_delay<0,"Desert cancels thunder and lightning")
	check(not weather.surface_effects.mist.emitting and not weather.surface_effects.mist.visible,"Desert has no ground clouds")
	check(weather.rain_strength_at(Vector3(345,0,-742))==0,"Desert wheels remain dry")
	check(weather.rain_strength_at(Vector3(77,0,96))==1,"City rain is independent of current focus")
	check(weather.weather_state==2,"Regional weather preserves saved Harbor storm")
	world.player.set_meta("mountain_shelter",true)
	weather._process(0)
	check(not weather.surface_effects.mist.visible,"Cover hides dust in same frame")
	world.player.remove_meta("mountain_shelter")
	weather._process(0)
	check(not weather.surface_effects.mist.visible and not weather.surface_effects.mist.emitting,"Uncover keeps ground clouds disabled")
	world.player.teleport(Vector3(77,.08,96))
	weather._process(0)
	weather._update()
	check(weather.precipitation.emitting and weather.weather_audio.target_intensity==1,"Return recovers city storm")
	check(weather.storm.trigger_lightning(),"Return recovers lightning")
	var bus: StringName = weather.weather_audio.bus_name
	world.free()
	await process_frame
	check(AudioServer.get_bus_index(bus)==-1,"Session releases weather bus")
	print("DESERT_WEATHER ",checks," checks; errors=",failures)
	quit(0 if failures.is_empty() else 1)
