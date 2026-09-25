extends SceneTree
## Real Main: authorized crane cargo -> physical drive -> explicit handback.
## Use --capture only during the coordinated visual window, never as an FPS test.
const FREIGHT := preload("res://gameplay/urban_v1/PortFreightDelivery.gd")
const URBAN := preload("res://gameplay/urban_v1/UrbanOperations.gd")
const EVIDENCE := "res://evidence/video-review-phase4-20260924/"
var OUTPUT := EVIDENCE
var world
var failures: Array[String] = []
var checks := 0
var photos := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): OUTPUT = argument.trim_prefix("--out=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	create_timer(230).timeout.connect(func(): push_error("FREIGHT timeout"); quit(3))
	run.call_deferred()
func frames(count: int) -> void:
	for _i in count: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	print("FREIGHT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func photograph(id: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + "phase4-port-after-" + id + ".png")
	print("FREIGHT_PHOTO ", id, " result=", result)
	if result == OK: photos += 1
	else: failures.append("photo " + id)
func place_actor(point: Vector3) -> void:
	world.production.region.set_focus(point)
	for _i in 180:
		await physics_frame
		if world.production.region.prepare_collision_at(point): break
	world.player.teleport(point)
	await frames(12)
func wait_transition() -> bool:
	for _i in 240:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	return false
func matching_trucks(id: String) -> int:
	var count := 0
	for car in world.get_children():
		if car.is_in_group("drivable") and car.get("vehicle_id") == id: count += 1
	return count
func saved_point(record: Dictionary) -> Vector3:
	var p: Array = record.get("position", [0,0,0])
	return Vector3(p[0],p[1],p[2])

func drive_to(truck, target: Vector3, limit: int) -> bool:
	truck.external_input = true
	for frame in limit:
		var offset: Vector3 = target - truck.global_position
		offset.y = 0
		if offset.length() < 2.5: return true
		var turn := wrapf(atan2(-offset.x, -offset.z) - truck.rotation.y, -PI, PI)
		truck.steer_input = clampf(turn * 1.5, -1, 1)
		var speed := 3.5 if absf(turn) > .5 else 5.5
		truck.throttle_input = .6 if truck.speed < speed else 0.0
		truck.brake_input = truck.speed > speed + .6
		await physics_frame
		if frame % 180 == 0: print("FREIGHT_DRIVE p=", truck.global_position, " target=", target, " speed=", truck.speed, " health=", truck.health)
	print("FREIGHT_DRIVE blocked p=", truck.global_position, " target=", target)
	for i in truck.get_slide_collision_count():
		var hit = truck.get_slide_collision(i).get_collider()
		print("FREIGHT_COLLIDER ", hit.get_path() if hit is Node else hit)
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	check(session != null and session.ready_for_play and world.production.no_save, "Main ready with personal save isolated")
	if not failures.is_empty(): await finish(); return
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.input_locked = false
	session.weather.time_of_day = .4
	session.weather.set_process(false)
	var ops = session.urban_operations
	var cargo = ops.cargo_handling
	var freight = ops.freight
	# Pay through the existing guard action, not by setting permission flags.
	await place_actor(Vector3(3390.0 / 16, .08, 3340.0 / 16 + .8))
	check(session.state.economy.grant_reward("video_phase4_funds", 500), "fixture funded through economy")
	check(session.interact() and session.modal, "existing port guard conversation opens")
	for child in session.column.get_children():
		if child is Button and child.text.begins_with("Pagar propina"): child.pressed.emit(); break
	check(ops.security.authorized_entry or ops.security.authorized_visit, "paid visit authorizes freight area")
	await place_actor(Vector3(4730.0 / 16, .08, 3430.0 / 16))
	var bay := 1
	for _i in 2700:
		await physics_frame
		if cargo.work_trucks[bay].loaded and cargo.work_trucks[bay].phase == "securing": break
	var entry: Dictionary = cargo.work_trucks[bay]
	var truck = entry.truck
	check(is_instance_valid(truck) and entry.loaded and entry.phase == "securing", "existing crane physically loads a stopped work truck")
	if not failures.is_empty(): await finish(); return
	await place_actor(truck.driver_door_anchor(-1) - truck.global_basis.x * .3)
	check(freight.nearest_action().is_empty(), "unfinished intro prevents conflicting freight acceptance")
	session.state.intro.set_location("harbor_garage")
	for target in ["maciota", "mechanic", "workbench", "maciota"]: session.state.intro.interact(target)
	session.state.intro.set_location("harbor_street")
	check(session.state.intro.stage == "complete", "fixture completes intro through its actual progression")
	check(session.state.campaign.begin("primeiro_giro"), "existing campaign starts normally")
	check(freight.nearest_action().is_empty(), "Primeiro Giro retains priority over freight")
	session.state.campaign.cancel("fixture")
	session.weather.time_of_day = .9
	check(freight.nearest_action().is_empty(), "closed work shift does not promise a truck")
	session.weather.time_of_day = .4
	await frames(20)
	for _i in 60:
		if not world.driving._entry_option(true).is_empty(): break
		await physics_frame
	print("FREIGHT_OFFER available=", freight._available(), " visit=", ops.security.authorized_visit, " shift=", cargo._shift_open(), " phase=", entry.phase, " loaded=", entry.loaded, " player=", world.player.global_position, " door=", truck.driver_door_anchor(-1), " floor=", truck.is_on_floor(), " locked=", world.player.input_locked, " option=", world.driving._entry_option(true), " stars=", world.gameplay.stars, " actor_speed=", world.player.velocity)
	check(session.nearest().get("target") == FREIGHT.PREFIX + str(bay), "normal interaction offers a reachable loaded freight")
	if not failures.is_empty(): await finish(); return
	world.camera.focus_on_store(truck.global_position + Vector3.UP, 16, .2)
	await frames(25)
	await photograph("offer")
	var crimes: float = world.gameplay.crime_points
	var previous_car: Dictionary = preload("res://runtime/FleetState.gd").capture(world.driving.car, "harbor")
	check(session.interact() and freight.active_bay == bay, "explicit acceptance transfers this work truck")
	check(entry.phase == "freight" and truck.get_meta("port_freight_claim", -1) == bay, "NPC route releases ownership until handback")
	check(not freight.perform(FREIGHT.PREFIX + "0"), "one active freight rejects another acceptance")
	check(session.save_game(), "active cargo is saved atomically with game state")
	var accepted: Dictionary = ops.snapshot()
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(accepted))
	print("FREIGHT_SAVE validate direct=", URBAN.validate_snapshot(accepted), " JSON=", URBAN.validate_snapshot(roundtrip), " freight=", FREIGHT.validate_snapshot(roundtrip.freight), " port=", preload("res://gameplay/urban_v1/PortOperations.gd").validate_snapshot(roundtrip.port), " cemetery=", preload("res://gameplay/urban_v1/CemeteryOperations.gd").validate_snapshot(roundtrip.cemetery))
	check(URBAN.validate_snapshot(roundtrip), "active freight survives JSON save roundtrip")
	var invalid := accepted.duplicate(true)
	invalid.freight.truck.vehicle_id = "story_tow_vehicle"
	var before_invalid: Dictionary = ops.snapshot()
	check(not ops.restore_snapshot(invalid) and ops.snapshot() == before_invalid, "foreign mission truck snapshot rejected without partial restore")
	var vehicle_count: int = matching_trucks(FREIGHT._vehicle_id(bay))
	check(ops.restore_snapshot(accepted), "active freight restore accepted")
	await frames(30)
	check(cargo.work_trucks[bay].truck == truck and matching_trucks(FREIGHT._vehicle_id(bay)) == vehicle_count, "restore adopts the same ID without a duplicate truck")
	check(cargo.cranes[bay].visual.get_parent() == truck, "restored container stays physically attached")
	check(world.driving.interact(true), "normal driver-door boarding succeeds")
	check(await wait_transition(), "truck boarding finishes")
	check(world.gameplay.crime_points == crimes, "authorized truck transfer does not register theft")
	await frames(20)
	check(session.freight_active and session.objective.text.contains("carga"), "session HUD exposes active freight objective")
	check(session.freight_target.is_finite(), "session exposes a finite freight minimap target")
	var hud = world.hud
	check(hud.objective_card.visible and hud.objective_label.text.contains("carga"), "visible ClassicGameplayHUD card contains freight objective")
	var depot: Vector3 = freight.depot_position(bay)
	check(hud.minimap.objective_target.distance_to(Vector2(depot.x, depot.z)) < .01, "HarborMinimap objective points to the real depot while driving")
	check(entry.phase == "freight", "player boarding no longer strands authorized cargo in interrupted phase")
	await photograph("loaded")
	world.camera.clear_store_focus()
	# Drive around the waiting trucks, using the open paved yard and authored
	# east freight road. Every metre uses Vehicle physics and collision.
	var route := [Vector3(310,0,216), Vector3(346,0,219), Vector3(357,0,231), Vector3(357,0,341), Vector3(349,0,351.25), freight.depot_position(bay)]
	for point in route:
		check(await drive_to(truck, point, 2100), "physical truck route reaches " + str(point))
		if not failures.is_empty(): await finish(); return
		if point == route[2]: await photograph("route")
	truck.throttle_input = 0
	truck.steer_input = 0
	truck.brake_input = true
	await frames(55)
	truck.external_input = false
	check(truck.is_on_floor() and truck.health > 0 and entry.loaded, "arrival preserves floor support, truck and physical cargo")
	check(not freight.perform("south_port_freight_deliver"), "payment requires explicit handback outside the vehicle")
	check(session.save_game(), "in-vehicle freight saved outside the quay")
	var saved_game: Dictionary = JSON.parse_string(JSON.stringify(session.state.snapshot()))
	var checkpoint := FileAccess.open(OUTPUT + "phase4-port-depot-save.json", FileAccess.WRITE)
	if checkpoint != null: checkpoint.store_string(JSON.stringify(saved_game)); checkpoint.close()
	var saved_position: Vector3 = truck.global_position
	world.queue_free()
	await frames(8)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	# ProductionWorld.build is deferred by World._ready. Seed the new session
	# before that build, without ever reading or replacing the personal save.
	check(world.production.state.restore_snapshot(saved_game), "new Main accepts the complete saved game")
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	session = world.session
	ops = session.urban_operations
	cargo = ops.cargo_handling
	freight = ops.freight
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.set_process(false)
	await frames(35)
	entry = cargo.work_trucks[bay]
	truck = entry.truck
	check(is_instance_valid(truck) and truck.global_position.distance_to(saved_position) < 1.0, "fresh-session reload keeps the loaded truck at the actual depot")
	if not is_instance_valid(truck): await finish(); return
	var matching := matching_trucks(FREIGHT._vehicle_id(bay))
	check(matching == 1 and world.driving.car == truck and world.driving.occupied, "fresh session adopts one saved driver vehicle without duplicate fleet")
	check(entry.loaded and cargo.cranes[bay].visual.get_parent() == truck, "fresh-session load restores the same shipment")
	check(ops.security.authorized_visit, "reload preserves the paid port visit")
	if not failures.is_empty(): await finish(); return
	check(world.driving.leave(), "depot exit admitted")
	check(await wait_transition(), "depot exit completes physically")
	await frames(20)
	check(session.nearest().get("target") == "south_port_freight_deliver", "delivery offered beside parked matching cargo")
	var balance: int = session.state.economy.balance
	await photograph("delivery")
	var returned_at: Vector3 = truck.global_position
	check(session.interact() and session.state.economy.balance == balance + 300, "delivery pays exactly R$300")
	check(freight.active_bay == -1 and freight.jobs[bay] == FREIGHT.DELIVERED and not entry.loaded, "delivery clears active cargo and persists completion")
	check(entry.phase == "approach" and truck.traffic, "explicit return resumes the existing NPC circuit")
	check(world.driving.car == null and not session.state.world_state.vehicles.any(func(record): return record.get("vehicle_id") == FREIGHT._vehicle_id(bay)), "returned work truck is no longer a duplicate personal-vehicle save")
	check(session.state.world_state.vehicles.size() == 1 and session.state.world_state.vehicles[0].vehicle_id == previous_car.vehicle_id and saved_point(session.state.world_state.vehicles[0]).distance_to(saved_point(previous_car)) < .01, "fresh-session handback preserves the previous personal car and position")
	check(not freight.perform("south_port_freight_deliver") and session.state.economy.balance == balance + 300, "repeated interaction cannot pay twice")
	var completed: Dictionary = ops.snapshot()
	check(ops.restore_snapshot(completed), "completed delivery restores")
	check(ops.restore_snapshot(accepted), "stale active snapshot reconciles against durable receipt")
	check(freight.active_bay == -1 and freight.jobs[bay] == FREIGHT.DELIVERED and session.state.economy.balance == balance + 300, "replayed cargo cannot resurrect or repeat payment")
	await frames(20)
	check(not session.freight_active, "paid freight clears HUD and map override")
	hud = world.hud
	check(not hud.objective_card.visible, "paid freight removes the ClassicGameplayHUD card")
	check(hud.minimap.objective_target.distance_to(Vector2(depot.x, depot.z)) > 1.0, "paid freight removes the depot minimap target")
	world.camera.focus_on_store(truck.global_position + Vector3.UP, 16, .2)
	await frames(25)
	check(truck.global_position.distance_to(returned_at) > .2 and world.player.visible and not world.driving.occupied, "returned truck physically resumes while Dante stays outside")
	await photograph("paid")
	var legacy: Dictionary = ops.snapshot()
	legacy.erase("freight")
	check(URBAN.validate_snapshot(legacy), "legacy urban saves remain accepted without freight field")
	check(ops.restore_snapshot(legacy) and not freight.bay_available(bay), "legacy world markers reconcile completed economy receipts")
	# Separate lifecycle branch: remove a different active truck, then replay its
	# resulting save. No explosions or protected characters are used by this test.
	var other = cargo.work_trucks[0].truck
	if is_instance_valid(other):
		var removed_job: Dictionary = freight.snapshot()
		removed_job.active_bay = 0
		removed_job.truck = preload("res://runtime/FleetState.gd").capture(other, "harbor")
		removed_job.previous_vehicle = previous_car.duplicate(true)
		check(freight.restore_snapshot(removed_job), "second authored shipment can restore independently")
		await frames(20)
		var before_loss: int = session.state.economy.balance
		world.driving.car = other
		world.driving._watch_car(other)
		world.production.capture_player_vehicle()
		other.queue_free()
		await frames(20)
		check(freight.active_bay == -1 and freight.jobs[0] == FREIGHT.LOST, "explicit vehicle removal retires its shipment")
		check(not session.state.world_state.vehicles.any(func(record): return record.get("vehicle_id") == FREIGHT._vehicle_id(0)), "removal save runs after Driving retires the selected truck")
		var loss: Dictionary = freight.snapshot()
		check(FREIGHT.validate_snapshot(loss) and loss.truck.is_empty(), "lost shipment save contains no resurrectable truck")
		check(freight.restore_snapshot(loss) and session.state.economy.balance == before_loss, "lost shipment reload never spawns cargo or pays")
		await frames(20)
		check(not session.freight_active, "vehicle loss clears the freight HUD override")
		check(not hud.objective_card.visible and session.state.world_state.vehicles[0].vehicle_id == previous_car.vehicle_id, "loss clears the card and retains the previous personal car")
	else:
		check(false, "second work truck remains available for lifecycle regression")
	await finish()

func finish() -> void:
	print("FREIGHT_RESULT checks=", checks, " failures=", failures.size(), " photos=", photos)
	if is_instance_valid(world): world.queue_free()
	await frames(8)
	quit(0 if failures.is_empty() else 1)
