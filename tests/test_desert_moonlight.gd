extends SceneTree
## Productive Weather integration: regional scope, lunar phase, clouds and
## indoor restoration. Rendered temporal/performance validation is separate.
const WEATHER := preload("res://runtime/Weather.gd")
var failures: Array[String]=[]
var checks := 0

class FakeState extends RefCounted:
	var region_id := "desert"
	var place_id := ""
	var world_state := {"time":0.0,"weather":0,"moon_day":4}
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

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Desert moonlight validation requires --no-save"); quit(2); return
	var world := FakeWorld.new()
	world.player=Node3D.new()
	world.add_child(world.player)
	root.add_child(world)
	var controller := FakeController.new()
	world.add_child(controller)
	controller.world=world
	controller.sun=DirectionalLight3D.new()
	controller.sun.shadow_enabled=true
	world.add_child(controller.sun)
	controller.environment=WorldEnvironment.new()
	controller.environment.environment=Environment.new()
	world.add_child(controller.environment)
	controller.session=FakeSession.new()
	world.add_child(controller.session)
	var weather=WEATHER.new()
	weather.controller=controller
	world.add_child(weather)
	weather.set_process(false)
	var desert := Vector3(-528,0,-822)
	var harbor := Vector3(243.75,0,237.5)
	var full := sample(weather,controller,desert,0.0,4,0)
	var new_moon := sample(weather,controller,desert,0.0,0,0)
	check(float(full.energy)>float(new_moon.energy)*3.0,"Full moon must visibly illuminate the desert more than new moon")
	check(float(new_moon.energy)<=.06,"New moon stays dark rather than receiving a constant floodlight")
	check(float(full.energy)<.6,"Full moon remains night exposure")
	check(full.color.r/full.color.b>.85,"Silver moonlight preserves sand colour instead of a saturated blue wash")
	check(float(full.angle)<=-42.0 and controller.sun.shadow_enabled,"Elevated moon preserves directional shadows without grazing wedges")
	var harbor_full := sample(weather,controller,harbor,0.0,4,0)
	check(is_equal_approx(harbor_full.energy,WEATHER.MOON_LIGHT_FULL),"Harbor's authored lunar energy is unchanged")
	check(harbor_full.color.is_equal_approx(WEATHER.HARBOR_SUN_NIGHT),"Harbor's night colour is unchanged")
	check(is_equal_approx(harbor_full.angle,full.angle),"Regional grading keeps moon direction fixed across the desert approach")
	check(float(full.energy)>float(harbor_full.energy)*1.1,"Desert has its own readable lunar relief")
	var cloudy := sample(weather,controller,desert,0.0,4,3)
	check(float(cloudy.energy)<float(full.energy)*.75,"Cloud cover attenuates desert moonlight")
	var day_full := sample(weather,controller,desert,.45,4,0)
	var day_new := sample(weather,controller,desert,.45,0,0)
	check(is_equal_approx(day_full.energy,day_new.energy) and is_equal_approx(day_full.energy,1.6),"Desert daylight remains independent of lunar phase")
	var bridge_a := sample(weather,controller,Vector3(345,0,-414.99),0.0,4,0)
	var bridge_b := sample(weather,controller,Vector3(345,0,-415.01),0.0,4,0)
	check(absf(bridge_a.energy-bridge_b.energy)<.001,"Desert approach blends the lunar exposure without a seam")
	var dusk_a := sample(weather,controller,desert,.8799,4,0)
	var dusk_b := sample(weather,controller,desert,.8801,4,0)
	check(absf(dusk_a.energy-dusk_b.energy)<.002,"Twilight reaches moonlight without a light toggle")
	controller.state.place_id="desert_digo"
	var inside_desert := sample(weather,controller,desert,0.0,4,0)
	var inside_harbor := sample(weather,controller,harbor,0.0,4,0)
	check(inside_desert==inside_harbor,"Indoor lighting is independent of exterior desert moonlight")
	controller.state.place_id=""
	var restored := sample(weather,controller,desert,0.0,4,0)
	check(restored==full,"Leaving an interior restores the same moonlight without compounding energy")
	var lighting_count := 0
	for child in world.get_children():
		if child is Light3D: lighting_count+=1
	check(lighting_count==1,"Desert moonlight reuses the existing directional source")
	weather.rain_audio.stop(); weather.rain_audio.stream=null
	weather.wind_audio.stop(); weather.wind_audio.stream=null
	world.queue_free()
	for frame in 6: await process_frame
	print("DESERT_MOONLIGHT ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func sample(weather, controller: FakeController, point: Vector3, hour: float, moon_day: int, weather_state: int) -> Dictionary:
	controller.world.player.position=point
	controller.state.world_state.moon_day=moon_day
	weather.time_of_day=hour
	weather.weather_state=weather_state
	# Isolate each requested position's settled regional palette.
	weather.atmosphere.current.clear()
	weather._update()
	var env: Environment=controller.environment.environment
	return {"energy":controller.sun.light_energy,"color":controller.sun.light_color,
		"ambient":env.ambient_light_energy,"ambient_color":env.ambient_light_color,
		"sky":env.background_color,"angle":controller.sun.rotation_degrees.x}
