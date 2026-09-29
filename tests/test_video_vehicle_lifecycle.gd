extends SceneTree
## Regression for the recorded theft -> port despawn -> death/save failure,
## plus the accumulated boarding offset and the detached fallback door panels.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var world
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func wait_transition() -> bool:
	for index in 240:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	return false

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("Vehicle regression requires --no-save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "session ready")
	check(world.production.no_save, "test cannot overwrite a user save")
	if not failures.is_empty(): quit(1); return
	world.production.set_process(false)
	world.production.set_population(0)
	var driving = world.driving
	var original = driving.car
	var spawn: Vector3 = original.global_position
	var original_visual: Vector3 = world.player.visual.position
	for cycle in 2:
		world.player.teleport(original.driver_door_anchor(-1) - original.global_basis.x * .35)
		await frames(2)
		check(driving.interact(), "car entry %d admitted" % cycle)
		check(await wait_transition(), "car entry %d finishes" % cycle)
		# Sentado, o visual fica no banco (VehicleInterior); a linha de base volta na saída (abaixo).
		check(world.player.visual.position.is_equal_approx(original_visual) or world.player.seated, "entry clears temporary visual crouch %d" % cycle)
		check(world.player.visible and world.player.seated, "enclosed vehicle shows the seated driver through the glass")
		original.stop_boarding_motion()
		check(driving.leave(), "car exit %d admitted" % cycle)
		check(await wait_transition(), "car exit %d finishes" % cycle)
		check(world.player.visual.position.is_equal_approx(original_visual), "exit preserves standing baseline %d" % cycle)
		check(world.player.visible and world.player.collision_layer == 2, "exit restores visible physical actor")
	# A teleport into an interior must not inherit a lowered visual from driving.
	world.player.teleport(world.player.global_position + Vector3(3, 0, 0))
	check(world.player.visual.position.is_equal_approx(original_visual), "teleport after two trips preserves the body baseline")
	original.hide()
	original.set_physics_process(false)
	original.collision_layer = 0
	original.remove_from_group("drivable")
	var bike = VEHICLE.new()
	bike.archetype = "bike_urban"
	bike.vehicle_id = "video_vehicle_bike"
	bike.traffic = true
	bike.set_meta("ambient_traffic", true)
	bike.set_meta("region_id", "harbor")
	bike.position = spawn
	world.add_child(bike)
	bike.set_physics_process(false)
	world.production.vehicles.append(bike)
	check(bike._motorcycle_rider_parts.size() == 29, "all urban rider meshes separated, including helmet accessories")
	check(bike._motorcycle_rider_parts.all(func(part): return part.visible), "ambient motorcycle has its rider")
	world.player.teleport(bike.driver_door_anchor(-1))
	bike.speed = 5.0
	bike.horizontal_velocity = Vector3(4, 0, 2)
	check(driving._begin_entry(bike, -1), "moving motorcycle theft admitted")
	check(not bike.has_meta("ambient_traffic"), "stolen bike leaves ambient cleanup ownership")
	check(bike._motorcycle_rider_parts.all(func(part): return not part.visible), "original rider leaves the motorcycle on theft")
	await frames(3)
	driving.cancel_transition("death")
	await frames(30)
	check(not driving.occupied and not driving.is_body_transition_active(), "cancelled moving theft cannot resume boarding")
	check(world.player.visible and world.player.collision_layer == 2, "moving theft cancellation restores player")
	bike.speed = 0.0
	bike.horizontal_velocity = Vector3(4, 0, 2)
	bike.velocity = Vector3(4, -.5, 2)
	world.player.teleport(bike.driver_door_anchor(-1))
	check(driving._begin_entry(bike, -1), "stopped motorcycle boarding admitted")
	check(bike.horizontal_velocity == Vector3.ZERO and bike.velocity.x == 0 and bike.velocity.z == 0, "boarding clears residual horizontal drift")
	check(await wait_transition(), "motorcycle boarding completes")
	check(world.player.visible and world.player.global_position.distance_to(bike.driver_seat_anchor()) < .01, "Dante replaces the old pilot at the motorcycle seat")
	driving._process(.2)
	check(driving.prompt.text.contains("moto"), "motorcycle exit uses motorcycle wording")
	# Even legacy bikes retaining ambient metadata must survive entering the port.
	bike.set_meta("ambient_traffic", true)
	var land: Rect2 = preload("res://world/regions/OriginalSouthPortLayout.gd").LAND
	var private_point := land.get_center() / 16.0
	bike.position = Vector3(private_point.x, spawn.y, private_point.y)
	check(preload("res://gameplay/urban_v1/HarborPortPolicy.gd").contains_private_area(bike.position), "fixture is in the same private-port cleanup area")
	world.production._process(.3)
	check(not bike.is_queued_for_deletion(), "occupied stolen motorcycle survives private-port cleanup")
	bike.place(spawn, 0.0)
	bike.health = 17.0
	world.production.capture_player_vehicle()
	check(world.production.starting_vehicle().get("health") == 17.0, "live vehicle snapshot keeps its actual condition")
	bike.queue_free()
	await frames(3)
	check(driving.car == null and not driving.occupied, "removed vehicle clears driving reference and occupancy")
	world.production.capture_player_vehicle()
	check(world.production.starting_vehicle().is_empty(), "explicitly removed motorcycle is not resurrected on load")
	var previous: Dictionary = preload("res://runtime/FleetState.gd").capture(original, "harbor")
	world.production.state.world_state.vehicles = [previous.duplicate(true)]
	world.production.capture_player_vehicle()
	check(world.production.starting_vehicle() == previous, "missing selection preserves an unrelated valid stored vehicle")
	world.gameplay.health = 0.0
	await world.session._respawn()
	check(world.gameplay.health > 0.0 and not world.session.respawn_busy, "death/respawn completes and saves after selected vehicle removal")
	check(world.player.visible and world.player.collision_mask == 7, "respawn restores walking body after vehicle removal")
	# Probe the remaining prepared bikes without running their physics.
	for id in ["bike_sport", "bike_cruiser"]:
		var parked = VEHICLE.new()
		parked.archetype = id
		parked.vehicle_id = "video_vehicle_" + id
		world.add_child(parked)
		parked.set_physics_process(false)
		check(parked._motorcycle_rider_parts.size() == 29, "%s separates every baked rider part" % id)
		check(parked._motorcycle_rider_parts.all(func(part): return not part.visible), "%s parked bike has no phantom rider" % id)
		driving.car = parked
		driving._watch_car(parked)
		parked.queue_free()
		await frames(2)
		check(world.production.starting_vehicle() == previous, "removing %s preserves the stored vehicle with another ID" % id)
	var sedan = VEHICLE.new()
	sedan.archetype = "union_sedan"
	world.add_child(sedan)
	sedan.set_physics_process(false)
	sedan.animate_driver_door(-1, true, 0.0)
	check(sedan.door_presentation.hinges[-1].visible, "substitute door appears while open")
	sedan.animate_driver_door(-1, false, 0.0)
	check(not sedan.door_presentation.hinges[-1].visible and not sedan.door_presentation.hinges[1].visible, "closed substitute doors do not leave detached panels")
	sedan.queue_free()
	var route = preload("res://scripts/RouteActivity.gd").new()
	route.world = world
	world.add_child(route)
	route.stage = 0
	route._process(.2)
	var distance: int = roundi(world.player.position.distance_to(route.points[0]))
	check(route.label.text.contains("%d m" % distance), "sandbox route follows the player after the selected vehicle is removed")
	route.queue_free()
	var holder := Node3D.new()
	world.add_child(holder)
	driving.car = original
	driving._watch_car(original)
	original.reparent(holder)
	check(world.production.starting_vehicle().get("vehicle_id") == original.vehicle_id, "reparenting preserves the selected vehicle snapshot")
	driving.car = original
	driving._watch_car(original)
	original.health = 0.0
	world.production.capture_player_vehicle()
	check(world.production.starting_vehicle().get("health") == 0.0, "a destroyed body still in the world is saved as a wreck")
	var retained_state = world.production.state
	world.queue_free()
	await process_frame
	var final_snapshot: Dictionary = retained_state.world_state.vehicles[0]
	check(preload("res://runtime/FleetState.gd").validate(final_snapshot) and final_snapshot.health == 0.0, "world teardown leaves a valid snapshot without healing the wreck")
	retained_state = null
	print("VIDEO_VEHICLE_LIFECYCLE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)
