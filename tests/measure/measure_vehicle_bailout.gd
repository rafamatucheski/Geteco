extends "res://tests/measure/measure_full.gd"
var home := Transform3D.IDENTITY
var next_exit := 0
var attempts := 0
var accepted := 0
var outcomes: Array = []

func run() -> void:
	await super.run()
	started = 0
	if not is_instance_valid(world) or not world.session.ready_for_play: return
	home = world.driving.car.global_transform
	world.player.speed = 0
	world.session.weather.time_of_day = 0.45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.look_at_from_position(home.origin+Vector3(9,8,10),home.origin+Vector3(0,0,-2))
	world.camera.size = 16
	for frame in 120: await physics_frame
	cold.clear()
	samples.clear()
	cpu.clear()
	physics.clear()
	measuring = false
	started = Time.get_ticks_usec()
	previous = started
	next_exit = started + 6000000

func _process(delta: float) -> bool:
	if started != 0 and Time.get_ticks_usec() >= next_exit:
		var car = world.driving.car
		world.driving.cancel_transition("benchmark_reset")
		car.global_transform = home
		car.stop_boarding_motion()
		car.traffic = false
		car.controlled = true
		car.input_locked = false
		car.speed = 9
		car.horizontal_velocity = -car.global_basis.z*9
		world.gameplay.health = 100
		world.driving.occupied = true
		world.player.set_physics_process(false)
		world.player.input_locked = false
		world.player.collision_layer = 0
		world.player.collision_mask = 0
		world.player.hide()
		attempts += 1
		if world.driving.leave():
			accepted += 1
			world.driving.transition.exited.connect(func(_point: Vector3):
				outcomes.append({"health":world.gameplay.health,"walking":not world.player.input_locked,"occupied":world.driving.occupied}),CONNECT_ONE_SHOT)
		next_exit += 6000000
	return super._process(delta)

func finish() -> void:
	print("BAILOUT_WORKLOAD attempts=",attempts," accepted=",accepted)
	var file := FileAccess.open(evidence_dir.path_join(label+"-workload.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"attempts":attempts,"accepted":accepted,"outcomes":outcomes},"\t"))
	file.close()
	await super.finish()
