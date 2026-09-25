extends "res://tests/measure/measure_full.gd"
## Main renderizado, câmera fixa e três explosões do mesmo carro em 30 segundos.
var wreck_car: CharacterBody3D
var wreck_pose: Transform3D
var next_blast := 0

func run() -> void:
	await super.run()
	started = 0
	if not is_instance_valid(world) or not world.session.ready_for_play: return
	wreck_car = world.driving.car
	wreck_car.traffic = false
	wreck_car.controlled = false
	wreck_car.speed = 0
	wreck_car.horizontal_velocity = Vector3.ZERO
	world.player.speed = 0
	world.session.weather.time_of_day = 0.45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.look_at_from_position(wreck_car.position + Vector3(10, 7, 12), wreck_car.position + Vector3.UP)
	world.camera.size = 18
	for frame in 120: await physics_frame
	wreck_pose = wreck_car.global_transform
	cold.clear()
	samples.clear()
	cpu.clear()
	physics.clear()
	measuring = false
	started = Time.get_ticks_usec()
	previous = started
	next_blast = started + 5000000

func _process(delta: float) -> bool:
	if started != 0 and is_instance_valid(wreck_car):
		if Time.get_ticks_usec() >= next_blast:
			wreck_car.repair()
			wreck_car.global_transform = wreck_pose
			wreck_car.velocity = Vector3.ZERO
			wreck_car.damage_look._rng.seed = 127
			wreck_car.receive_damage(wreck_car.max_health * 2)
			next_blast += 12000000
	return super._process(delta)
