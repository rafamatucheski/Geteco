extends SceneTree
## Main regression: a parked selection loses streaming support before the next
## distance-cleanup tick. Freight must not persist its unsupported falling pose.
const FLEET := preload("res://runtime/FleetState.gd")
const OUTPUT := "res://evidence/video-review-phase4-20260924/"

class LegacyCapture extends "res://gameplay/urban_v1/PortFreightDelivery.gd":
	# Diagnostic ablation: this is the prior, unconditional snapshot behavior.
	func _capture_supported_previous(vehicle: CharacterBody3D) -> void:
		previous_vehicle = FLEET.capture(vehicle, str(previous_vehicle.get("region", "harbor")))
		previous_vehicle.was_driven = false

var world
var prior: CharacterBody3D
var freight
var samples: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0
var initial: Dictionary = {}

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("PREVIOUS_FLOOR timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PREVIOUS_FLOOR ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func sample(label: String) -> void:
	if not is_instance_valid(prior):
		samples.append({"label":label,"frame":Engine.get_physics_frames(),"alive":false})
		return
	var origin := Vector3(prior.position.x, .35, prior.position.z)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * .9, 1))
	samples.append({"label":label,"frame":Engine.get_physics_frames(),"alive":true,"y":prior.position.y,"vy":prior.velocity.y,"on_floor":prior.is_on_floor(),"ground":str(hit.collider.get_path()) if not hit.is_empty() else "","selected":world.driving.car == prior,"queued":prior.is_queued_for_deletion(),"distance_despawn":prior.get_meta("distance_despawn",false),"population_clock":world.production.population_clock})

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main ready with isolated save")
	if not failures.is_empty(): await finish(); return
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	prior = world.driving.car
	freight = world.session.urban_operations.freight
	if "--legacy-capture" in OS.get_cmdline_user_args():
		freight = LegacyCapture.new()
		freight.configure(world.session, world.session.urban_operations.cargo_handling, world.session.urban_operations.security)
	for _i in 20: await physics_frame
	sample("startup_supported")
	check(prior.is_on_floor() and prior.position.y > -.05, "original personal car begins physically supported")
	# Set the far focus through ProductionWorld so the selected personal car
	# retains its existing support; do not unload its floor in fixture setup.
	var depot := Vector3(316.5, .12, 351.3)
	world.production._update_physical_residency(depot)
	world.player.teleport(depot + Vector3(0, 0, 10))
	for _i in 20: await physics_frame
	var truck = world.production.spawn_vehicle("cargo_flatbed_truck", depot, 1.50385)
	check(is_instance_valid(truck), "distant truck admitted on real port floor")
	if not is_instance_valid(truck): await finish(); return
	truck.vehicle_id = "phase4_previous_floor_truck"
	truck.set_meta("port_work_vehicle", true)
	for _i in 12: await physics_frame
	sample("before_selection_change")
	check(prior.is_on_floor() and prior.position.y > -.05, "far original remains supported while selected")
	check(prior.position.distance_to(world.player.position) > 145, "original is beyond ordinary distance-cleanup threshold")
	initial = FLEET.capture(prior, "harbor")
	freight.previous_vehicle = initial.duplicate(true)
	freight._previous_ref = weakref(prior)
	freight._watch_previous(prior)
	# Exercise the existing save owner and ordinary world streaming/despawn.
	# Neither vehicle is teleported below its floor, and no cleanup is mocked.
	world.production.population_clock = 0.0
	world.driving.car = truck
	world.driving._watch_car(truck)
	world.production._update_physical_residency(world.player.position)
	sample("selection_changed")
	for i in 24:
		await physics_frame
		sample("after_%02d" % i)
	var after: Dictionary = freight.snapshot().previous_vehicle
	var lowest := float(initial.position[1])
	for record in samples:
		if record.get("alive",false): lowest = minf(lowest,float(record.y))
	check(lowest >= float(initial.position[1]) - .02, "physical previous car never falls while awaiting distance cleanup")
	check(not is_instance_valid(prior), "ordinary distance cleanup retires the physical previous car")
	check(not after.is_empty() and after.vehicle_id == initial.vehicle_id, "previous selection remains available as a saved record")
	if not after.is_empty():
		check(absf(float(after.position[1]) - float(initial.position[1])) < .02, "saved prior pose stays at the last supported height")
		check(after.health == initial.health and after.equipment == initial.equipment, "damage and equipment survive streaming cleanup")
	print("PREVIOUS_FLOOR_RECORD initial=", initial, " final=", after)
	await finish(after)

func finish(after: Dictionary = {}) -> void:
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	var file := FileAccess.open(OUTPUT + "previous-floor-" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"initial":initial,"final":after,"samples":samples}, "\t"))
		file.close()
	if is_instance_valid(freight) and not freight.is_inside_tree(): freight.free()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	print("PREVIOUS_FLOOR_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
