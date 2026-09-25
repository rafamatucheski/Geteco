extends SceneTree

var failures: Array[String] = []

class FakeState extends RefCounted:
	var region_id := "harbor"
	var place_id := ""
	var world_state := {"time":.45, "weather":0}

class FakeSession extends Node:
	var cold: Node

class FakeWorld extends Node3D:
	var player: Node3D
	var production: Node

class FakeController extends Node:
	var state := FakeState.new()
	var world: FakeWorld
	var sun: DirectionalLight3D
	var environment: WorldEnvironment
	var session: FakeSession

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Weather lighting test requires --no-save")
		quit(2)
		return
	var stage := FakeWorld.new()
	stage.player = Node3D.new()
	stage.add_child(stage.player)
	root.add_child(stage)
	var controller := FakeController.new()
	stage.add_child(controller)
	controller.world = stage
	controller.sun = DirectionalLight3D.new()
	controller.sun.shadow_enabled = true
	stage.add_child(controller.sun)
	controller.environment = WorldEnvironment.new()
	controller.environment.environment = Environment.new()
	stage.add_child(controller.environment)
	controller.session = FakeSession.new()
	stage.add_child(controller.session)
	var weather = preload("res://runtime/Weather.gd").new()
	weather.controller = controller
	stage.add_child(weather)
	weather.set_process(false)
	weather.time_of_day = .45
	weather.weather_state = 0
	weather._update()
	var clear_energy: float = controller.sun.light_energy
	var clear_color: Color = controller.sun.light_color
	var clear_background: Color = controller.environment.environment.background_color
	check(weather.HARBOR_SUN_DAY.is_equal_approx(Color("fffdf5")) and absf(clear_color.r-clear_color.g)<.04 and clear_color.b>=clear_color.r*.9,"Clear Harbor daylight keeps the authored near-neutral tint after atmospheric grading")
	check(controller.sun.shadow_enabled,"Productive directional shadows remain enabled")
	weather.weather_state = 1
	weather._update()
	check(controller.sun.light_energy < clear_energy*.8,"Drizzle visibly reduces direct daylight instead of changing particles only")
	check(controller.sun.light_color.b > controller.sun.light_color.r,"Drizzle moves highlights toward the cool V1 overcast palette")
	check(not controller.environment.environment.background_color.is_equal_approx(clear_background),"Drizzle changes the environment palette")
	check(weather.precipitation.emitting,"Drizzle still emits precipitation outdoors")
	weather.time_of_day = .90
	weather.weather_state = 0
	weather._update()
	check(controller.environment.environment.ambient_light_color.b > controller.environment.environment.ambient_light_color.r,"Night keeps blue shadow fill")
	check(controller.sun.light_energy < clear_energy*.2,"Night remains materially darker than day")
	for failure in failures: push_error(failure)
	print("WEATHER_LIGHTING_PARITY ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	weather.rain_audio.stop()
	weather.rain_audio.stream = null
	weather.wind_audio.stop()
	weather.wind_audio.stream = null
	stage.queue_free()
	for frame in 6: await process_frame
	quit(0 if failures.is_empty() else 1)
