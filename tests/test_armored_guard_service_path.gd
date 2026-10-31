extends SceneTree
## Caminho físico do carregador: travessia perpendicular no próprio caminhão, depois a fachada
## do banco. Atribuições de serviço repetidas não podem reiniciar waypoints já passados.
const GUARD := preload("res://gameplay/armored/ArmoredGuard.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
class State extends RefCounted:
	var place_id := ""
	var equipped_weapon := "fists"
	func weapons_allowed() -> bool: return true
class Game extends RefCounted:
	var aiming := false
	var player: Node3D
	func pursuit_target() -> Node3D: return player
class World extends Node3D:
	var gameplay := Game.new()
	var player: Node3D
class Car extends Node3D:
	func door_point() -> Vector3: return global_position + Vector3.UP * .4
class Convoy extends Node3D:
	var session: Dictionary
	var banks := {"a":{"entry_position":Vector3(0, 0, -5)}, "b":{"entry_position":Vector3(0, 0, -10)}}
	var fleet: Array = []
	var data := {"phase":"loading", "hostile":false, "origin":"a", "destination":"b"}
	func crew_operational() -> bool: return true
	func provoke(_source: Node) -> void: pass
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	create_timer(35).timeout.connect(func(): check(false, "bounded carrier path watchdog"); quit(3))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARMORED_GUARD_SERVICE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, .2, 60)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -.1
	world.add_child(floor_body)
	world.player = Node3D.new()
	world.add_child(world.player)
	world.player.position = Vector3(100, 0, 100)
	world.gameplay.player = world.player
	var convoy := Convoy.new()
	convoy.session = {"world":world, "state":State.new()}
	world.add_child(convoy)
	var truck := Car.new()
	world.add_child(truck)
	truck.position = Vector3(4, 0, 0)
	convoy.fleet.append(truck)
	var guard := GUARD.new()
	guard.convoy = convoy
	guard.position = Vector3(4, .08, 0)
	guard.configure_security(SCHEDULE.security(0))
	guard.patrol_target = Vector3(-.5, .08, -4)
	convoy.add_child(guard)
	var worst_crossing_x := 0.0
	var corner_seen := false
	var corner_claimed_arrival := false
	for frame in 540:
		await physics_frame
		if frame % 15 == 0: guard.patrol_target = Vector3(-.5, .08, -4)
		if guard.position.z > -3.5: worst_crossing_x = maxf(worst_crossing_x, absf(guard.position.x - 4.0))
		if guard.position.distance_to(Vector3(4, 0, -4)) < .5:
			corner_seen = true
			corner_claimed_arrival = corner_claimed_arrival or guard.reached_target()
		if guard.reached_target(): break
	check(worst_crossing_x < .4 and corner_seen, "truck-to-bank carrier crosses perpendicular beside its vault before walking along the frontage")
	check(not corner_claimed_arrival, "the intermediate corner never completes the bank interaction")
	check(guard.reached_target() and guard.is_on_floor(), "same-target refreshes do not reset the route and the carrier reaches the bank physically")
	guard.patrol_target = truck.door_point()
	var premature_road_entry := false
	var return_corner_seen := false
	for frame in 540:
		await physics_frame
		if frame % 15 == 0: guard.patrol_target = truck.door_point()
		if guard.position.x < 3.5 and guard.position.z > -3.5: premature_road_entry = true
		if guard.position.distance_to(Vector3(4, 0, -4)) < .5: return_corner_seen = true
		if guard.reached_target(): break
	check(not premature_road_entry and return_corner_seen, "bank-to-truck carrier stays along the frontage until aligned with its vault")
	check(guard.reached_target() and guard.is_on_floor(), "carrier returns physically to the original cargo target")
	guard.set_physics_process(false)
	convoy.data.phase = "unloading"
	guard.patrol_target = Vector3(-.5, .08, -9)
	check(guard._service_navigation_target().is_equal_approx(Vector3(4, .08, -9)), "unloading uses the destination bank frontage")
	convoy.data.hostile = true
	check(guard._service_navigation_target() == guard.patrol_target, "combat does not force a bank-service detour")
	convoy.data.hostile = false
	guard.slot = 2
	check(guard._service_navigation_target() == guard.patrol_target, "escorts retain their ordinary movement targets")
	guard.slot = 0
	convoy.data.phase = "boarding"
	check(guard._service_navigation_target() == guard.patrol_target, "boarding does not walk back to the bank")
	convoy.data.phase = "loading"
	convoy.banks.clear()
	check(guard._service_navigation_target() == guard.patrol_target, "fixtures without authored bank geometry preserve direct movement")
	world.free()
	print("ARMORED_GUARD_SERVICE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
