extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func quiet(car: Node) -> bool:
	if car.engine_audio and car.engine_audio.playing: return false
	if car.skid_audio and car.skid_audio.playing: return false
	for voice in car._engine_sound._layer_players:
		if voice.playing: return false
	for voice in [car._engine_sound._road_player, car._engine_sound._shift_player, car._engine_sound._air_player]:
		if is_instance_valid(voice) and voice.playing: return false
	return true
func exercise_exit(car: Node, actor: Node, label: String) -> void:
	if is_instance_valid(car._boarding) and car._boarding.active:
		car._boarding._finish()
	await process_frame
	car.set_physics_process(false)
	car._engine_sound.update(car.engine_audio, 200.0, 400.0, 1.0, .2, car.active_archetype_id)
	car.velocity = Vector2(150,100)
	car.lateral_speed = 100.0
	car.is_skidding = true
	car._update_skid_audio()
	check(car.skid_audio.playing and car.skid_audio.bus == &"SFX", label+" skid is audible on SFX")
	check(not quiet(car),label+" engine running before exit")
	car.exit_vehicle()
	check(is_instance_valid(car._boarding) and car._boarding.exiting,label+" real exit started")
	check(quiet(car), label+" all drive voices stop at start of exit")
	car.set_physics_process(true)
	for i in 8: await physics_frame
	check(quiet(car),label+" transition never restarts frozen RPM")
	if is_instance_valid(car._boarding): car._boarding._finish_exit()
	for i in 8: await physics_frame
	check(not car.is_driven_by_player and quiet(car),label+" empty vehicle stays off")
	check(not root.get_node("RegionTravel").snapshot_world().has("vehicle"), label+" on-foot snapshot has no running vehicle")
	actor.set_physics_process(false)
func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var actor = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 8
	actor.add_child(shape)
	world.add_child(actor)
	actor.set_physics_process(false)
	var travel := root.get_node("RegionTravel")
	for path in ["res://cars/traffic/SavedPlayerCar.tscn", "res://cars/traffic/TrafficVehicle.tscn"]:
		var car = load(path).instantiate()
		world.add_child(car)
		if car.has_method("configure_as_parked"): car.configure_as_parked()
		if car.has_method("ensure_presentation"): car.ensure_presentation()
		actor.global_position = car.global_position+Vector2(-8,-55)
		await physics_frame
		car.enter_vehicle(actor)
		if is_instance_valid(car._boarding): car._boarding._finish()
		await process_frame
		var saved: Dictionary = travel.snapshot_world()
		check(saved.has("vehicle"), path+" occupied snapshot")
		await exercise_exit(car,actor,path)
		car.queue_free()
		await process_frame
		travel.pending_world = saved
		travel._restore_saved_vehicle(world,actor)
		var restored: Node = travel.controlled_car()
		check(restored != null,path+" restored through production save path")
		if restored != null:
			await exercise_exit(restored,actor,path+" restored")
			restored.queue_free()
		await process_frame
		travel.pending_world = {}
	print("VEHICLE_AUDIO_EXIT failures=",failures)
	quit(0 if failures==0 else 1)
