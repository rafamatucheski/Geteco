extends SceneTree
## Storm contract: visible world discharge, delayed thunder and shelter cleanup.
const STORM := preload("res://runtime/atmosphere/StormPresentation.gd")
var failures: Array[String] = []
var checks := 0

class TestWorld extends Node3D:
	var player := Node3D.new()
	var driving = null

class TestController extends RefCounted:
	var world: Node3D
	var sun := DirectionalLight3D.new()
	var environment := WorldEnvironment.new()

class TestWeather extends Node:
	var weather_state := 2
	var controller := TestController.new()
	func rain_strength_at(point: Vector3) -> float:
		return 1.0 if point.x < 100.0 else 0.0

class TestMixer extends Node:
	var thunder := AudioStreamPlayer.new()
	var played := 0
	func play_thunder() -> void: played += 1

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var stage := TestWorld.new()
	stage.add_child(stage.player)
	root.add_child(stage)
	var weather := TestWeather.new()
	weather.controller.world = stage
	weather.controller.environment.environment = Environment.new()
	stage.add_child(weather.controller.sun)
	stage.add_child(weather.controller.environment)
	stage.add_child(weather)
	var mixer := TestMixer.new()
	mixer.add_child(mixer.thunder)
	stage.add_child(mixer)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180, 1, 180)
	shape.shape = box
	ground.position.y = -.5
	ground.add_child(shape)
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	stage.add_child(camera)
	camera.position = Vector3(0,25.3,25.3)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var storm = STORM.new()
	storm.weather = weather
	storm.mixer = mixer
	stage.add_child(storm)
	storm.set_process(false)
	await physics_frame
	await physics_frame
	weather.controller.sun.light_energy = .4
	weather.controller.sun.light_color = Color(.9,.8,.7)
	weather.controller.environment.environment.ambient_light_energy = .3
	storm.sync(1.0,false)
	check(storm.trigger_lightning(),"Heavy rain starts a discharge")
	storm._process(.05)
	check(is_instance_valid(storm.bolt) and storm.bolt.visible,"World bolt is visible with the flash")
	check(weather.controller.sun.light_energy > .4,"Existing world flash accompanies the bolt")
	check(mixer.played == 0,"Thunder follows the flash with a delay")
	check(not storm.trigger_lightning(),"Pending thunder prevents overlapping discharges")
	check(storm.strike_position.is_finite(),"Strike has a valid world endpoint")
	check(absf(storm.strike_position.y) < .08,"Strike meets the actual collision surface")
	check(Vector2(storm.strike_position.x,storm.strike_position.z).length() >= 9.0,"Strike stays away from the player")
	storm._process(.20)
	check(not storm.trigger_lightning(),"Nearby thunder finishing early cannot overlap the visible flash")
	var first_bolt = storm.bolt
	var first_point: Vector3 = storm.strike_position
	storm._process(3.3)
	check(mixer.played == 1 and storm.thunder_count == 1,"Each accepted flash delivers one delayed thunder")
	check(not storm.bolt.visible,"Discharge disappears after the short flash")
	check(is_equal_approx(weather.controller.sun.light_energy,.4),"Sun energy returns to its baseline")
	check(weather.controller.sun.light_color.is_equal_approx(Color(.9,.8,.7)),"Sun color returns to its baseline")
	check(storm.trigger_lightning(),"A later discharge is accepted")
	storm._process(.05)
	check(storm.bolt == first_bolt,"Repeated discharges reuse the same presentation node")
	check(not storm.strike_position.is_equal_approx(first_point),"Later discharges vary their location")
	check(storm.bolt.find_children("*","Light3D",true,false).is_empty(),"Visible discharge adds no dynamic lights")
	# Weather rewrites its base before sync, as in the production _update path.
	weather.controller.sun.light_energy = .4
	weather.controller.sun.light_color = Color(.9,.8,.7)
	weather.controller.environment.environment.ambient_light_energy = .3
	storm.sync(1.0,true)
	check(not storm.bolt.visible and storm.thunder_delay < 0,"Shelter removes the bolt and cancels pending thunder")
	check(not storm.trigger_lightning(),"Shelter prevents new discharges")
	storm._process(4.0)
	check(mixer.played == 1,"Cancelled thunder never plays later")
	weather.weather_state = 0
	storm.sync(1.0,false)
	check(not storm.trigger_lightning(),"Clear weather prevents discharges")
	weather.weather_state = 2
	storm.sync(0.0,false)
	check(not storm.trigger_lightning(),"Dry regional exposure prevents coastal lightning")
	storm.sync(1.0,false)
	check(storm.trigger_lightning(),"Returning to the storm restores discharges")
	storm._process(.05)
	storm.cancel()
	check(not storm.bolt.visible,"Direct cancellation immediately hides the bolt")
	check(is_equal_approx(weather.controller.sun.light_energy,.4),"Direct cancellation immediately restores sunlight")
	var roof := StaticBody3D.new()
	var roof_shape := CollisionShape3D.new()
	roof_shape.shape = box
	roof.add_child(roof_shape)
	roof.position.y = 5.0
	stage.add_child(roof)
	await physics_frame
	await physics_frame
	check(storm.trigger_lightning(),"A roof is a valid exposed strike surface")
	check(is_equal_approx(storm.strike_position.y,5.525),"Strike stops on the roof instead of passing through it")
	storm.cancel()
	roof.collision_layer = 0
	ground.collision_layer = 0
	await physics_frame
	await physics_frame
	check(storm.trigger_lightning(),"Cloud flash remains possible when no world impact is available")
	check(not storm.bolt.visible and not storm.strike_position.is_finite(),"Missing collision never creates an imaginary ground strike")
	storm.cancel()
	var bolt_reference: WeakRef = weakref(storm.bolt)
	storm.queue_free()
	await process_frame
	await process_frame
	check(bolt_reference.get_ref() == null,"Storm disposal frees its visual resources")
	stage.queue_free()
	await process_frame
	print("LIGHTNING_STORM ",checks," checks; errors=",failures)
	quit(0 if failures.is_empty() else 1)
