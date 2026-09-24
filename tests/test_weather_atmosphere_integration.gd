extends SceneTree
var world
var errors: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.weather != null: break
	if world.session == null or world.session.weather == null: quit(2); return
	var weather = world.session.weather
	var env: Environment = world.production.environment.environment
	world.session.cold.set_process(false)
	weather.weather_state = 1
	weather.weather_timer = 10000
	weather.time_of_day = .9
	weather._update()
	check(weather.precipitation.emitting and not weather.snow.emitting,"Harbor rain without mountain snow")
	check(world.production.sun.rotation_degrees.x<=-42,"Actual night light raised")
	check(env.fog_enabled and env.adjustment_enabled,"Actual world receives atmosphere")
	var entered: bool = await world.session.enter_place("maciota",false)
	check(entered,"Real garage entry")
	weather._update()
	check(not env.fog_enabled and not env.adjustment_enabled,"Real room suspends exterior atmosphere")
	check(not weather.precipitation.emitting and not weather.snow.emitting and not weather.hail.emitting,"Room suppresses all precipitation")
	check(not world.session.state.weapons_allowed(),"Garage weapon restriction preserved")
	check(weather.weather_state==1,"Indoor weather ID preserved")
	if entered:
		check(await world.session.leave_place(),"Real garage exit")
	weather._update()
	check(env.fog_enabled and env.adjustment_enabled and weather.precipitation.emitting,"Exit restores rainy Harbor")
	var origin: Vector3 = world.player.position
	world.session.cold.model.weather_clock = 120
	# Synchronous samples on either side of the actual seam; no fake timer or
	# duplicate thermal state. This verifies presentation, not physical traversal.
	for x in [456.24,456.26]:
		world.player.teleport(Vector3(x,.08,-285))
		weather._update()
		check(weather.precipitation.emitting and weather.snow.emitting,"Rain/snow coexist across seam")
		check(weather.precipitation.amount_ratio>0 and weather.snow.amount_ratio>0,"Seam retains both emission weights")
		check(weather.weather_state==1,"Seam preserves saved Harbor weather")
	world.player.teleport(Vector3(718,.08,-479))
	weather._update()
	check(weather.snow.emitting and weather.hail.emitting and not weather.precipitation.emitting,"Thermal peak gives snow and hail")
	check(weather.snow.draw_pass_1!=weather.precipitation.draw_pass_1,"Rain and snow do not share a mutable mesh")
	world.player.teleport(Vector3(600,.08,-285))
	weather._update()
	check(not weather.snow.emitting and not weather.hail.emitting and not env.fog_enabled,"Tunnel suppresses snow, hail and fog")
	world.player.teleport(origin)
	weather._update()
	check(weather.precipitation.emitting and not weather.snow.emitting,"Return restores original rain")
	print("WEATHER_ATMOSPHERE_INTEGRATION ",checks," checks; errors=",errors)
	world.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
