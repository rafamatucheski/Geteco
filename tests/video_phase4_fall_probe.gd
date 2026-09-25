extends SceneTree
## Original coupe remains physical during second-car travel, interiors and rescue.
const OUTPUT := "res://evidence/video-review-phase4-20260924/"
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var coupe: CharacterBody3D
var sedan: CharacterBody3D
var records: Array[Dictionary] = []
var failures: Array[String] = []
var phase := "startup"
var minimum_y := INF
var maximum_y := -INF
var samples := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PHASE4_FALL ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		record(index % 30 == 0)

func record(force := false) -> void:
	if not is_instance_valid(coupe): return
	samples += 1
	minimum_y = minf(minimum_y, coupe.global_position.y)
	maximum_y = maxf(maximum_y, coupe.global_position.y)
	if not force and coupe.global_position.y > -.05: return
	var top := Vector3(coupe.global_position.x, .3, coupe.global_position.z)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - Vector3.UP * .8, 1))
	var floor_path := str(hit.collider.get_path()) if not hit.is_empty() else ""
	records.append({"phase":phase,"frame":Engine.get_physics_frames(),"coupe":str(coupe.global_position),"velocity":str(coupe.velocity),"speed":coupe.speed,"floor_contact":coupe.is_on_floor(),"floor_ray":floor_path,"platform_velocity":str(coupe.get_platform_velocity()),"layer":coupe.collision_layer,"mask":coupe.collision_mask,"physics_active":coupe.is_physics_processing(),"health":coupe.health,"traffic":coupe.traffic,"ambient":coupe.get_meta("ambient_traffic",false),"player":str(world.player.global_position),"place":world.session.state.place_id,"selected":world.driving.car == coupe,"focus":str(world.production.region.focus),"cell":str(world.production.region.current_cell)})

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	seed(240924)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false, "Main ready"); await finish(); return
	world.gameplay.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.set_population(0)
	coupe = world.driving.car
	# Explicit incident setup: the recorded coupe was left on Westgate,
	# unlike the clean-save startup parking spot beside Maciota.
	coupe.place(Vector3(26.7, .12, 109), 0.0)
	phase = "original_parked"
	await frames(20)
	check(coupe.is_on_floor() and coupe.health > 0, "original coupe grounded")
	sedan = world.production.spawn_vehicle("union_sedan", Vector3(26.7, .12, 99), 0.0)
	if not is_instance_valid(sedan):
		check(false, "second car admitted"); await finish(); return
	sedan.vehicle_id = "phase4_sedan"
	await frames(10)
	world.player.teleport(sedan.driver_door_anchor(-1))
	check(world.driving.interact(true), "board second car")
	await frames(150)
	phase = "drive_to_ammunation"
	if not await drive_path([Vector3(26.7, 0, 31), Vector3(31, 0, 26.7), Vector3(88, 0, 26.7), Vector3(96.8, 0, 26.7)]):
		await finish(); return
	check(world.driving.leave(), "leave sedan at Ammu-Nation")
	await frames(150)
	world.player.teleport(PLACES.get_definition("harbor_ammunation").entry_position + Vector3(0, .05, 1))
	phase = "ammunation_interior"
	check(await world.session.enter_place("harbor_ammunation", false), "enter real Ammu-Nation")
	await frames(180)
	check(await world.session.leave_place(), "leave real Ammu-Nation")
	await frames(15)
	world.player.teleport(sedan.driver_door_anchor(-1))
	check(world.driving.interact(true), "board sedan after Ammu-Nation")
	await frames(150)
	phase = "drive_to_bank"
	if not await drive_path([Vector3(42, 0, 26.7)], true):
		await finish(); return
	check(world.driving.leave(), "leave sedan near bank")
	await frames(150)
	world.player.teleport(PLACES.get_definition("harbor_bank").entry_position + Vector3(0, .05, 1))
	phase = "bank_interior"
	check(await world.session.enter_place("harbor_bank", false), "enter real bank")
	await frames(180)
	phase = "bank_death_rescue"
	world.gameplay.damage_player(1000.0)
	for frame in 900:
		await physics_frame
		record(frame % 30 == 0)
		if not world.session.rescue_pending and world.gameplay.health > 0: break
	check(world.gameplay.health > 0 and world.session.state.place_id.is_empty(), "bank death rescues to exterior")
	phase = "return_to_original"
	await frames(90)
	check(is_instance_valid(coupe) and coupe.health > 0 and coupe.global_position.y > -.25, "original coupe survives location cycle")
	if is_instance_valid(coupe) and coupe.health > 0:
		world.player.teleport(coupe.driver_door_anchor(-1))
		check(world.driving.interact(true), "board original coupe after rescue")
		await frames(240)
		check(world.driving.occupied and world.driving.car == coupe and coupe.is_on_floor(), "original coupe grounded after boarding")
	await finish()

func drive_path(points: Array[Vector3], reverse := false) -> bool:
	sedan.set_external_driver(true)
	for target in points:
		var reached := false
		for frame in 1200:
			var offset: Vector3 = target - sedan.global_position
			offset.y = 0
			if offset.length() < 5.0: reached = true; break
			var desired := atan2(-offset.x, -offset.z) + (PI if reverse else 0.0)
			var angle := angle_difference(sedan.rotation.y, desired)
			var drive_sign := -1.0 if reverse else 1.0
			sedan.steer_input = clampf(angle * 2.0 * drive_sign, -1.0, 1.0)
			sedan.throttle_input = drive_sign if absf(sedan.speed) < (3.0 if absf(angle) > .5 else 7.0) else 0.0
			sedan.brake_input = absf(angle) > .5 and absf(sedan.speed) > 3.0
			await physics_frame
			record(frame % 30 == 0)
			if not world.driving.occupied or sedan.health <= 0: break
		if not reached:
			check(false, "fixture blocked: target " + str(target) + " car " + str(sedan.global_position))
			return false
	sedan.stop_boarding_motion()
	return true

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "fall-route-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"samples":samples,"minimum_y":minimum_y,"maximum_y":maximum_y,"records":records,"notes":"Causal Main physics probe, no FPS claim. Actual vehicle driving; explicit foot setup at doors. All preexisting runtime changes retained."}, "\t"))
	file.close()
	if is_instance_valid(world):
		world.queue_free()
		for frame in 3: await physics_frame
	print("PHASE4_FALL samples=",samples," min_y=",minimum_y," max_y=",maximum_y," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
