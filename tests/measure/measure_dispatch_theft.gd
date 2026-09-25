extends "res://tests/measure/measure_full.gd"
## Main renderizado com uma viatura tomada e sua equipe a pé por 30 segundos.
## Executar antes/depois da mudança, na mesma máquina e com os mesmos argumentos.

func run() -> void:
	await super.run()
	started = 0
	if not is_instance_valid(world) or not is_instance_valid(world.dispatch):
		push_error("Dispatch benchmark could not start Main")
		quit(1)
		return
	var patrol: CharacterBody3D = world.dispatch._create_vehicle("police", world.player.global_position + Vector3(8, 0, 0), 0.0)
	var road: Curve3D = world.production.traffic_routes.route_near(world.player.global_position)
	if road == null:
		push_error("No road near player for dispatch theft benchmark")
		quit(1)
		return
	var found := false
	var offset: float = road.get_closest_offset(world.player.global_position)
	for attempt in 24:
		var distance: float = fposmod(offset + 8.0 + attempt * 5.0, road.get_baked_length())
		var point: Vector3 = road.sample_baked(distance, true)
		var ahead: Vector3 = road.sample_baked(minf(distance + 1.0, road.get_baked_length()), true) - point
		var yaw := atan2(-ahead.x, -ahead.z)
		var pose := point + Vector3.UP * 0.12
		if not world.production.vehicle_position_clear(patrol, pose, yaw): continue
		patrol.place(pose, yaw)
		await physics_frame
		var open_exits: Array[Vector3] = []
		var first: Dictionary = world.dispatch.exit_point(patrol, open_exits, false)
		if first.is_empty(): continue
		var reserved: Array[Vector3] = [first.point]
		if world.dispatch.exit_point(patrol, reserved, false).is_empty(): continue
		found = true
		break
	if not found:
		push_error("No road pose with two free officer exits")
		quit(1)
		return
	var unit: RefCounted = world.dispatch._make_unit("police", patrol, 8.0, 60.0)
	unit._set_state("parked")
	if not world.dispatch.vehicle_stolen(patrol, -1):
		push_error("Dispatch theft failed")
		quit(1)
		return
	world.dispatch.enabled = false # Mantém só a equipe do roubo; evita novos despachos aleatórios.
	print("THEFT_BENCH officers=", world.gameplay.police.size(), " crew_remaining=", unit.crew_remaining)
	cold.clear()
	samples.clear()
	cpu.clear()
	physics.clear()
	measuring = false
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if started != 0 and is_instance_valid(world) and is_instance_valid(world.gameplay):
		world.gameplay.health = 100
	return super._process(delta)
