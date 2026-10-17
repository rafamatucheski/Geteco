extends SceneTree
## Real Main/.NET round trips, campaign gates, modal ownership and isolated save.
## Only initial positioning/campaign prerequisites are fixtures; normal rides are
## timed by the production controller and never advance route distance from here.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world
var transit
var checks := 0
var failures: Array[String] = []
var output := ""
var save_path := ""
var initial_collision := Vector2i.ZERO
var initial_camera: Dictionary = {}


func _initialize() -> void:
	create_timer(360).timeout.connect(func(): push_error("RAILWAY_RUNTIME bounded timeout"); quit(3))
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAILWAY_RUNTIME ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func frames(count: int) -> void:
	for index in count: await physics_frame


func boot(path: String) -> bool:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	for index in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play, "actual Main session ready")
	if world.session == null or not world.session.ready_for_play: return false
	check(world.production.no_save and world.production.loaded_save and not world.production.save_invalid and world.production.store.path == path and path.begins_with(output), "actual SaveStore isolated from personal saves")
	if world.production.store.path != path or not path.begins_with(output): return false
	transit = world.session.railway
	check(is_instance_valid(transit), "production owns RailwayTransit")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	return is_instance_valid(transit)


func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires --no-save and compiled .NET, with isolated APPDATA/LOCALAPPDATA.")
		quit(2)
		return
	output = FIXTURE.output_dir("railway-runtime")
	var initial := FIXTURE.full_snapshot(NETWORK.get_station("harbor_central").entry)
	initial.campaign = FIXTURE.prefix(0)
	save_path = FIXTURE.write_fixture(output, "railway-save.json", initial)
	check(not save_path.is_empty(), "fresh campaign fixture validated")
	if save_path.is_empty() or not await boot(save_path): finish(); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "compiled C# routing active; no silent fallback")
	var platform: Vector3 = NETWORK.get_station("harbor_central").arrival
	world.production.region.set_focus(platform)
	world.player.teleport(platform)
	await frames(40)
	check(world.player.is_on_floor() and world.session.position_clear(world.player.global_position), "initial station platform supports the actual player capsule")
	check(transit.can_interact(), "player on platform can open ordinary station interaction")
	if not transit.can_interact(): finish(); return
	initial_collision = Vector2i(world.player.collision_layer, world.player.collision_mask)
	initial_camera = {"projection": world.camera.projection, "size": world.camera.size, "fov": world.camera.fov, "process": world.camera.is_processing(), "target": world.camera.target, "locked": world.camera.locked}
	check(not transit.station_available(NETWORK.get_station("desert_copper")), "desert locked before final mission")
	check(transit.station_available(NETWORK.get_station("mountain_pines")), "mountain remains accessible before final mission")
	var before: Vector3 = world.player.global_position
	check(not transit.travel_to("missing") and not transit.travel_to("harbor_central"), "invalid and same-station trips rejected")
	check(not transit.travel_to("desert_copper", true) and not transit.travel_to("desert_copper", false), "neither scenic nor fast travel bypasses desert gate")
	check(world.player.global_position.is_equal_approx(before) and not transit.busy(), "rejected trips leave position and transition state unchanged")
	world.gameplay.stars = 1
	check(not transit.can_interact(), "wanted passenger cannot board")
	world.gameplay.stars = 0
	world.driving.occupied = true
	check(not transit.can_interact(), "occupied vehicle cannot board train")
	world.driving.occupied = false
	var health: float = world.gameplay.health
	world.gameplay.health = 0
	check(not transit.can_interact(), "dead passenger cannot board")
	world.gameplay.health = health
	var armored = world.session.armored_transport
	var pending_truck: int = int(armored.pending_truck)
	armored.pending_truck = 0
	check(not transit.can_interact() and not transit.travel_to("harbor_north", true), "unfinished armored interaction cannot escape through railway")
	armored.pending_truck = pending_truck
	check(transit.can_interact(), "cleared local activity restores station eligibility")
	check(await open_menu(), "ordinary interaction opens station selector")
	var ui: Node = world.find_child("RailwayUI", true, false)
	check(is_instance_valid(ui) and ui.is_station_open(), "production UI receives live destinations")
	var cancel := action("ui_cancel")
	check(transit.handle_input(cancel), "controller cancel consumed by station modal")
	check(not world.session.modal and not world.player.input_locked and not transit.busy() and not ui.is_station_open(), "closing selector releases modal, player and UI together")
	# Subsequent saves may only target the already-validated unique fixture path.
	world.production.no_save = false
	check(await ride("harbor_north", false, true), "normal outward city ride completes without skip or fixture movement")
	if not failures.is_empty(): finish(); return
	check(await ride("harbor_central", false, false), "normal return city ride completes without skip")
	if not failures.is_empty(): finish(); return
	check(await ride("mountain_pines", true, false), "fast travel reaches mountain before final city mission")
	check(await ride("harbor_central", true, false), "fast travel returns from mountain")
	if not failures.is_empty(): finish(); return
	# Use the supported legacy prefix: this scenario has not played Jessica's
	# independent quest and must not forge its completion/world-state cross ledger.
	check(world.session.state.campaign.restore_snapshot(FIXTURE.before_document(true)), "final-mission prerequisite fixture accepted")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(world.session.state.snapshot()), "campaign prerequisite fixture preserves full-save cross contracts")
	check(not transit.station_available(NETWORK.get_station("desert_copper")), "desert remains locked immediately before final document")
	var completed := FIXTURE.final_event(world.session.state.campaign)
	check(completed.ok and transit.station_available(NETWORK.get_station("desert_copper")), "actual final mission event opens desert destination")
	world.session.mission_world._update_aftermath()
	for index in 16:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
		await process_frame
	check(not world.session.dialogue_open and not world.session.modal, "final campaign conversation completes before station admission")
	check(await ride("desert_copper", true, false), "fast travel reaches unlocked desert station")
	check(await ride("harbor_central", true, false), "desert station supports return journey")
	if not failures.is_empty(): finish(); return
	await check_occupied_arrival()
	if not failures.is_empty(): finish(); return
	check(await open_menu() and transit.travel_to("harbor_north", false), "ride can start for interruption scenario")
	await frames(150)
	transit.cancel_trip()
	await await_arrival(10.0)
	check_arrival("harbor_central", "cancel returns to departure")
	check(await open_menu() and transit.travel_to("harbor_north", false), "ride restarts after cancellation")
	await frames(20)
	transit.cancel_for_transition()
	check(not transit.busy() and world.player.is_physics_processing() and world.player.collision_layer == initial_collision.x and world.player.collision_mask == initial_collision.y, "recovery cancellation releases train ownership and collision")
	check(not world.camera.locked and world.camera.is_processing() and transit.save_block_reason().is_empty(), "recovery cancellation restores camera and save eligibility")
	# Recovery owns the destination after cancel_for_transition. Return its test
	# fixture to the already verified safe platform before persisting a checkpoint.
	world.player.teleport(NETWORK.get_station("harbor_central").arrival)
	await frames(12)
	check(world.session.save_game(), "actual session saves supported station arrival")
	var persisted := STORE.read_valid(save_path)
	check(not persisted.is_empty() and persisted.region_id == "harbor", "saved arrival passes the production snapshot validator")
	world.queue_free()
	await frames(5)
	world = null
	if await boot(save_path):
		await frames(25)
		check(transit.can_interact() and not transit.busy() and world.session.state.place_id.is_empty(), "cold save reload restores ordinary station access without an orphan ride")
		check(world.player.is_on_floor() and world.session.position_clear(world.player.global_position), "cold reload station arrival is supported and clear")
		check(transit.station_available(NETWORK.get_station("desert_copper")), "campaign unlock survives isolated save and reload")
	finish()


func action(id: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = true
	return event


func check_occupied_arrival() -> void:
	var destination := NETWORK.get_station("harbor_north")
	var obstruction := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.3, 9.0)
	shape.shape = box
	obstruction.add_child(shape)
	world.add_child(obstruction)
	obstruction.global_position = destination.arrival + Vector3.UP * 1.0
	await frames(3)
	check(await open_menu() and transit.travel_to("harbor_north", false), "occupied-arrival scenario boards from safe departure")
	await frames(60)
	transit.skip_trip()
	await frames(12)
	check(transit.is_riding() and not transit.landing and world.player.input_locked and not world.player.is_physics_processing(), "fully occupied platform retains safe onboard ownership instead of spawning in solid")
	check(not transit.save_block_reason().is_empty(), "failed admission cannot save an unsafe platform pose")
	obstruction.queue_free()
	await frames(3)
	transit.skip_trip()
	check(await await_arrival(10.0), "retry after removing obstruction safely completes arrival")
	check_arrival("harbor_north", "recovered blocked platform")
	check(await ride("harbor_central", true, false), "recovered arrival can immediately return")


func open_menu() -> bool:
	var nearest: Dictionary = world.session.nearest()
	check(nearest.get("id", "") == "railway", "station joins ordinary interaction selection")
	var opened: bool = await world.session.interact()
	return opened and world.session.modal and transit.menu_open


func ride(destination: String, instant: bool, inspect: bool) -> bool:
	if not await open_menu(): return false
	var accepted: bool = transit.travel_to(destination, instant)
	check(accepted, "destination request admitted: " + destination)
	if not accepted: return false
	if inspect:
		await frames(150)
		check(transit.is_riding() and transit.distance > 0.0 and transit.speed > 0.0, "train moves through actual route under its own clock")
		check(world.player.input_locked and not world.player.is_physics_processing() and not world.session.modal, "passenger ownership blocks gameplay without pausing world")
		check(not world.gameplay.attack_allowed() and not world.gameplay.fire_at(world.player.global_position + Vector3.FORWARD * 8.0), "production combat cannot fire or melee from passenger mode")
		check(world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and world.camera.target == transit.train and world.camera.size >= 34.0, "boarding uses wide external view of moving train")
		transit.set_camera_mode(1)
		check(world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and transit.camera_mode == 1, "outside view uses the same moving train")
		transit.set_camera_mode("interior")
		check(transit.camera_mode == 1 and world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "legacy interior request cannot restore removed camera")
		transit.set_camera_mode("exterior")
		check(transit.camera_mode == 1, "named exterior camera mode is accepted")
		transit.set_camera_mode(0)
		for input_action in ["fire", "weapon_next", "inventory", "vehicle_interact", "world_map"]:
			check(transit.handle_input(action(input_action)), "onboard gameplay input intercepted: " + input_action)
		check(not transit.handle_input(action("pause_game")), "pause input remains available")
		var distance: float = transit.distance
		paused = true
		await create_timer(0.2, true).timeout
		check(is_equal_approx(float(transit.distance), distance), "pause freezes journey without advancing destination")
		paused = false
		var hash_before := FileAccess.get_sha256(save_path)
		check(not world.session.save_block_reason().is_empty() and not world.session.save_game(), "production save rejects checkpoint over moving tracks")
		check(FileAccess.get_sha256(save_path) == hash_before, "blocked onboard save leaves isolated checkpoint bytes unchanged")
	var finished := await await_arrival(90.0)
	check(finished, "bounded journey reaches arrival: " + destination)
	if not finished: return false
	check_arrival(destination, destination)
	return failures.is_empty()


func await_arrival(seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while transit.busy() and Time.get_ticks_msec() < deadline: await physics_frame
	await frames(10)
	return not transit.busy()


func check_arrival(id: String, label: String) -> void:
	var station := NETWORK.get_station(id)
	check(world.session.state.region_id == station.region and world.player.global_position.distance_to(station.arrival) < 3.5, "correct station and region: " + label)
	check(world.player.is_on_floor() and world.session.position_clear(world.player.global_position), "safe supported disembark: " + label)
	check(not world.player.input_locked and not world.session.modal and not paused and not transit.busy(), "controls and world resume: " + label)
	check(world.player.collision_layer == initial_collision.x and world.player.collision_mask == initial_collision.y and world.player.is_physics_processing(), "ordinary actor physics restored: " + label)
	check(world.camera.projection == int(initial_camera.projection) and world.camera.is_processing() == bool(initial_camera.process) and world.camera.locked == bool(initial_camera.locked), "ordinary camera restored: " + label)
	check(world.camera.target == initial_camera.target and is_equal_approx(float(world.camera.fov), float(initial_camera.fov)), "player camera target and FOV restored: " + label)
	check(not world.player.has_meta("mountain_shelter"), "temporary coach weather shelter removed: " + label)
	check(transit.save_block_reason().is_empty(), "station permits saving: " + label)


func finish() -> void:
	paused = false
	if is_instance_valid(transit): transit.cancel_for_transition()
	print("RAILWAY_RUNTIME_RESULT checks=%d failures=%d evidence=%s" % [checks, failures.size(), output])
	quit(0 if failures.is_empty() else 1)
