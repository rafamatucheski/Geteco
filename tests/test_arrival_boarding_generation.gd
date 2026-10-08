extends SceneTree
## Real Arrival coroutines, physics-frame suspension and door timer; lightweight
## actors isolate callback ownership from navigation, art and the city tour.
const ARRIVAL := preload("res://runtime/Arrival.gd")
class Actor extends CharacterBody3D:
	var input_locked := false
	func walk_step(destination: Vector3, delta: float) -> void:
		position = position.move_toward(destination,3.625*delta)
class Doors extends Node:
	var open := false
	func door(_index: int, value: bool) -> void: open = value
class Car extends CharacterBody3D:
	var health := 80.0
	var model := Doors.new()
	var traffic := false
	var controlled := false
	var route: Curve3D
	var route_distance := 0.0
	var occupants := false
	func _init() -> void: add_child(model)
	func door_point(side: int) -> Vector3: return global_position+Vector3(side*2.0,0,0)
	func show_occupants(value: bool) -> void: occupants = value
class Gameplay extends RefCounted:
	var health := 100.0
	func find_path(_from: Vector3, destination: Vector3) -> PackedVector3Array:
		return PackedVector3Array([destination])
class Camera extends Node:
	var target: Node
class Place extends RefCounted:
	var entry_position := Vector3(10,0,0)
class World extends Node3D:
	var player: Actor
	var camera := Camera.new()
	var gameplay := Gameplay.new()
	var maciota_place := Place.new()
	func install_arrival_actors(arrival) -> void:
		arrival.car = Car.new()
		arrival.maciota = Actor.new()
		add_child(arrival.car)
		add_child(arrival.maciota)
class RecoveryArrival extends "res://runtime/Arrival.gd":
	func _spawn_encounter() -> void:
		session.world.install_arrival_actors(self)
class Session extends RefCounted:
	var world: World
	var modal := false
	var ready_for_play := false
	var notice_time := 0.0
	var rescue_pending := false
	var respawn_busy := false
	func show_message(_message: String) -> void: pass
	func position_clear(_point: Vector3) -> bool: return true

var checks := 0
var failures := 0
var completed := false
var arrival_script: GDScript = ARRIVAL

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-reference="):
			arrival_script = GDScript.new()
			arrival_script.source_code = FileAccess.get_file_as_string(argument.trim_prefix("--arrival-reference="))
			if arrival_script.reload()!=OK: quit(2); return
	create_timer(15).timeout.connect(func(): push_error("ARRIVAL_BOARDING timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("ARRIVAL_BOARDING ","PASS " if ok else "FAIL ",label)

func fixture(recovery := false) -> Dictionary:
	var world := World.new()
	root.add_child(world)
	world.player = Actor.new()
	world.player.collision_layer = 2
	world.player.collision_mask = 7
	world.add_child(world.player)
	world.add_child(world.camera)
	world.camera.target = world.player
	var session := Session.new()
	session.world = world
	var arrival = RecoveryArrival.new() if recovery else arrival_script.new()
	world.add_child(arrival)
	arrival.configure(session)
	arrival.set_physics_process(false)
	arrival.active = true
	arrival.phase = "tour_board"
	arrival.route = Curve3D.new()
	arrival.route.add_point(Vector3.ZERO)
	arrival.route.add_point(Vector3(10,0,0))
	arrival.car = Car.new()
	arrival.maciota = Actor.new()
	world.add_child(arrival.car)
	world.add_child(arrival.maciota)
	world.player.position = arrival.car.door_point(1)
	arrival.maciota.position = arrival.car.door_point(-1)
	return {"world":world,"arrival":arrival}

func board(arrival) -> void:
	completed = false
	await arrival._board()
	completed = true

func drain() -> void:
	var deadline := Time.get_ticks_msec()+1500
	while not completed and Time.get_ticks_msec()<deadline: await physics_frame
	check(completed,"boarding coroutine completes within its bounded timer")

func release(f: Dictionary) -> void:
	f.arrival.riding = false
	f.world.free()

func run() -> void:
	var f := fixture()
	board(f.arrival)
	await drain()
	check(f.arrival.riding and f.arrival.phase=="city_tour","normal boarding still starts the tour")
	check(not f.world.player.visible and f.world.player.collision_layer==0 and f.world.camera.target==f.arrival.car,"normal boarding transfers capsule and camera")
	check(f.arrival.flags.get("harbor_city_tour_started",false),"normal boarding records its milestone")
	release(f)

	f = fixture()
	f.world.player.position += Vector3(0,0,4)
	board(f.arrival)
	await physics_frame
	check(not completed and f.arrival.controls_locked,"walking phase really suspends the boarding coroutine")
	f.arrival._generation += 1
	f.arrival.phase = "terminal_meeting"
	f.arrival.controls_locked = true
	await drain()
	check(f.arrival.phase=="terminal_meeting" and f.arrival.controls_locked,"cancelled walk cannot unlock or overwrite the newer phase")
	check(not f.arrival.riding and not f.arrival.flags.has("harbor_city_tour_started"),"cancelled walk grants no boarding milestone")
	release(f)

	f = fixture()
	board(f.arrival)
	check(f.arrival.car.model.open and not completed,"door timer really suspends after both walks finish")
	var previous_car: Car = f.arrival.car
	f.arrival._generation += 1
	f.arrival.car = Car.new()
	f.world.add_child(f.arrival.car)
	f.arrival.phase = "terminal_meeting"
	f.arrival.controls_locked = true
	await drain()
	check(not f.arrival.riding and f.arrival.phase=="terminal_meeting" and f.arrival.controls_locked,"stale door timer cannot board the replacement car or change newer state")
	check(f.world.player.visible and f.world.player.collision_layer==2 and f.world.player.collision_mask==7 and f.world.camera.target==f.world.player,"stale door timer leaves current capsule visibility and camera intact")
	check(not f.arrival.car.traffic and not f.arrival.car.occupants and not f.arrival.flags.has("harbor_city_tour_started"),"replacement car and milestones remain untouched")
	previous_car.queue_free()
	release(f)
	if arrival_script == ARRIVAL:
		# Actual deferred recovery, with only actor creation and floor admission
		# replaced by the lightweight fixture; no mocked recovery callback.
		f = fixture(true)
		board(f.arrival)
		f.arrival.car.health = 0
		await drain()
		await process_frame
		await process_frame
		check(not f.arrival.riding and not f.arrival.controls_locked and f.arrival.phase=="tour_board","destroyed current car requests recovery before boarding can start")
		check(f.world.player.visible and f.world.player.is_physics_processing() and not f.world.player.input_locked and f.world.player.collision_layer==2 and f.world.camera.target==f.world.player,"boarding recovery restores player controls capsule and camera")
		check(f.arrival.car.health>0 and not f.arrival.flags.has("harbor_city_tour_started") and not f.arrival._recovering,"boarding recovery supplies another healthy encounter without a false milestone")
		release(f)
	print("ARRIVAL_BOARDING checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
