extends SceneTree
class LocalBus extends Node2D:
	var distance_travelled := 0.0
	var doors := 1.0
	var dwelling := true
	func door_position() -> Vector2: return global_position + Vector2(37, -30)
	func depart() -> void: dwelling = false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var station := Node2D.new()
	world.add_child(station)
	station.set_script(preload("res://world/harbor/HarborArrivalStop.gd"))
	station.set_physics_process(false)
	station.position = Vector2(1700, 1060)
	var bus := LocalBus.new()
	world.add_child(bus)
	bus.position = Vector2(1699, 1220)
	station.bus = bus
	station._phase = "unload"
	for index in 4:
		var person := preload("res://world/harbor/HarborTransitPassenger.gd").new()
		person.ambient_running_enabled = false
		station.add_child(person)
		person.base_walk_speed = 40
		person.position = station._queue_slot(index)
		person.set_destination(person.global_position, "waiting" if index < 2 else "onboard")
		if index >= 2:
			person.hide()
			person.set_physics_process(false)
		station.passengers.append(person)
	Engine.time_scale = 6
	Engine.physics_ticks_per_second = 180
	var started := Time.get_ticks_msec()
	var reset := false
	while Time.get_ticks_msec() - started < 40000:
		await physics_frame
		station._physics_process(6.0 / 180.0)
		if station.departures == 1 and not reset:
			reset = true
			bus.dwelling = true
			station.bus_arrived()
		if station.departures == 2: break
	print("LOCAL_BUS_TWO_EXCHANGES status=", station.get_service_status(), " states=", station.passengers.map(func(p): return [p.transit_state,p.position,p.destination]))
	var passed: bool = station.departures == 2 and station.boarded == 4 and station.alighted == 4
	# The fixture bus does not have a lane parent owned by the station.
	station.bus = null
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)
