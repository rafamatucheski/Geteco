extends SceneTree
## Real Main/.NET flow, isolated checkpoint and ordinary bank/getaway adapters.
## First pistol hit, guards, lockpick, cash and exit use production objects.
## Guard combat is finished deterministically after that hit; combat balance is
## not certified here. Wanted is never cleared and the Jetta never teleports.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const PROGRESS := preload("res://systems/campaign/JessicaProgress.gd")
const HEIST := preload("res://runtime/Robberies.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const COURT_PATH := preload("res://tests/fixtures/JessicaCourtyardFootpath.gd")
const PREFIX := ["primeiro_giro","cobra_contact","cobra_race","cobra_collection"]
var world
var checks := 0
var failures: Array[String] = []
var folder := ""
var parked_m8: CharacterBody3D
var report := {"fixture":"campaign prefix through cobra_collection, with corresponding real economy receipts",
	"combat_limit":"first shot real; remaining guard damage injected, combat balance not certified",
	"bank_navigation":"authored central corridors with ordinary direct movement and real Actor collision; exterior uses gameplay navigation",
	"wanted_artificially_cleared":false,"getaway_vehicle_teleported":false,"samples":[],"health_trace":[],"walk_failures":[]}
var _health_sample := 0
var _measure_getaway := false
var _perf_started := 0
var _perf_previous := 0
var _perf_warm: Array[float] = []
var _perf_frames: Array[float] = []
var _perf_cpu: Array[float] = []
var _perf_physics: Array[float] = []
var _perf_population: Array[Dictionary] = []
var _ride_captured := false

func _initialize() -> void:
	_measure_getaway = "--measure-getaway" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	create_timer(420).timeout.connect(func():
		check(false,"bounded integration timeout")
		write_report()
		quit(3))
	physics_frame.connect(sample_health)
	run.call_deferred()

func _process(_delta: float) -> bool:
	if not _measure_getaway or not is_instance_valid(world) or world.session == null or world.session.jessica == null: return false
	if not world.session.jessica.riding or world.session.dialogue_open:
		_perf_previous = 0
		return false
	var now := Time.get_ticks_usec()
	if _perf_started == 0: _perf_started = now
	if _perf_previous == 0:
		_perf_previous = now
		return false
	var interval := (now-_perf_previous)/1000.0
	_perf_previous = now
	if now-_perf_started < 5000000:
		_perf_warm.append(interval)
		return false
	_perf_frames.append(interval)
	_perf_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	_perf_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	if _perf_population.is_empty() or now-int(_perf_population[-1].t_us) >= 1000000:
		_perf_population.append({"t_us":now,"npcs":world.people.size(),"cars":world.production.vehicles.size(),"wanted":world.gameplay.stars})
	return false

func frame_stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"frames":0,"seconds":0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/total,
		"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],
		"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	print("JESSICA_INTEGRATION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func finish_dialogue() -> void:
	for i in 80:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
		await physics_frame

func walk(point: Vector3, seconds := 12.0, stop_for_debrief := false, direct := false) -> bool:
	var began := Time.get_ticks_msec()
	var place: String = world.session.state.place_id
	# The bank has narrow authored portal/aisle coordinates. A coarse nav grid
	# can put its waypoint into the open vault leaf; use the same ordinary
	# direct walking used by test_bank_gameplay inside that actual corridor.
	var path: PackedVector3Array = PackedVector3Array([point]) if direct or place == "harbor_bank" else world.gameplay.find_path(world.player.global_position,point)
	if path.is_empty() or path[-1].distance_to(point) > .1: path.append(point)
	for waypoint in path:
		while Time.get_ticks_msec()-began < seconds*1000:
			if world.session.rescue_pending or world.session.arrest_pending or world.gameplay.health <= 0:
				record_walk_failure("death_or_arrest",point,path)
				return false
			if world.session.state.place_id != place:
				record_walk_failure("place_changed",point,path)
				return false
			if stop_for_debrief and world.session.dialogue_open and PROGRESS.data(world.session.state.world_state).bank_phase == "returned":
				world.player.automatic_direction = Vector3.ZERO
				return true
			var direction: Vector3 = waypoint-world.player.global_position
			direction.y = 0
			if direction.length() < .16: break
			world.player.automatic_direction = direction.normalized()
			await physics_frame
		if Time.get_ticks_msec()-began >= seconds*1000:
			record_walk_failure("blocked",point,path)
			return false
	world.player.automatic_direction = Vector3.ZERO
	return true

func sample_health() -> void:
	_health_sample += 1
	if _health_sample < 15 or not is_instance_valid(world) or world.session == null or not world.session.ready_for_play: return
	_health_sample = 0
	if report.health_trace.size() >= 2500: return
	report.health_trace.append({"t_ms":Time.get_ticks_msec(),"health":world.gameplay.health,"wanted":world.gameplay.stars,
		"place":world.session.state.place_id,"position":str(world.player.global_position),
		"rescue":world.session.rescue_pending,"arrest":world.session.arrest_pending})

func record_walk_failure(reason: String, target: Vector3, path: PackedVector3Array) -> void:
	world.player.automatic_direction = Vector3.ZERO
	var contacts: Array = []
	for i in world.player.get_slide_collision_count():
		var collision = world.player.get_slide_collision(i)
		var collider = collision.get_collider()
		contacts.append({"collider":str(collider.get_path()) if collider is Node else str(collider),"position":str(collision.get_position()),"normal":str(collision.get_normal())})
	var query := PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP*.9,target+Vector3.UP*.9,7,[world.player.get_rid()])
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	var obstruction := ""
	if not hit.is_empty(): obstruction = str(hit.collider.get_path()) if hit.collider is Node else str(hit.collider)
	var diagnostic := {"reason":reason,"health":world.gameplay.health,"wanted":world.gameplay.stars,"place":world.session.state.place_id,
		"rescue":world.session.rescue_pending,"arrest":world.session.arrest_pending,"position":str(world.player.global_position),
		"target":str(target),"path":str(path),"frontal_collider":obstruction,"contacts":contacts}
	report.walk_failures.append(diagnostic)
	print("JESSICA WALK FAILURE ",JSON.stringify(diagnostic))

func prepare_fixture() -> bool:
	folder = "res://evidence/jessica-integration-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var state := STATE.new()
	var intro := state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): return false
	var campaign := state.campaign.snapshot()
	campaign.completed = PREFIX.duplicate()
	campaign.claimed_rewards = PREFIX.duplicate()
	campaign.flags = {}
	for id in PREFIX:
		for flag in MISSIONS.MISSIONS[id].sets_flags: campaign.flags[flag] = true
		if not state.economy.grant_reward("campaign:"+id,int(MISSIONS.MISSIONS[id].reward)): return false
	if not state.campaign.restore_snapshot(campaign): return false
	state.world_state.time = .45
	state.world_state.weather = 0
	state.world_state.robberies = HEIST.defaults()
	state.world_state.jessica = PROGRESS.fresh_snapshot()
	state.world_state.jessica_vehicle = {}
	var point: Vector3 = PLACES.get_definition("harbor_bank").exterior_position+Vector3(0,.08,22.0)
	state.world_state.pedestrian = {"region":"harbor","position":[point.x,point.y,point.z]}
	var store := STORE.new()
	store.path = folder.path_join("fixture-save.json")
	if store.save(state) != OK: return false
	report.fixture_path = store.path
	world.set_meta("menu_save_path",store.path)
	return true

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Jessica integration requires --no-save; it uses an isolated fixture, never a player save.")
		quit(2)
		return
	seed(5102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("jessica_diagnostics",true)
	check(prepare_fixture(),"isolated fixture has consistent campaign prefix and reward receipts")
	if not failures.is_empty(): await finish(); return
	root.add_child(world)
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"real Main and .NET world ready")
	if not failures.is_empty(): await finish(); return
	var session = world.session
	var jessica = session.jessica
	var heist = session.robberies
	check(session.controller.loaded_save and not session.controller.save_invalid,"fixture actually loaded and passed production save validation")
	check(session.controller.store.path == report.fixture_path,"all checkpoint persistence targets the isolated fixture")
	# The campaign prefix includes Maciota's completed arrival. Keep the real
	# cinematic hull in its bay, so the Jetta must park and admit its occupants
	# with both cars present. This fixture never moves either car during escape.
	parked_m8 = preload("res://runtime/ArrivalCar.gd").new()
	parked_m8.position = world.maciota_place.tour_parking+Vector3.UP*.02
	parked_m8.set_meta("fixture_parked_maciota",true)
	world.add_child(parked_m8)
	parked_m8.set_physics_process(false)
	report.parked_m8 = str(parked_m8.global_position)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.0
	session.weather.weather_timer = 99999
	for i in 240:
		await physics_frame
		if is_instance_valid(jessica.actor) and is_instance_valid(jessica.car): break
	check(is_instance_valid(jessica.actor) and is_instance_valid(jessica.car),"Jessica and exactly one Jetta appear in the streamed bank street")
	if not failures.is_empty(): await finish(); return
	var serial: int = jessica.car.get_instance_id()
	jessica._stream_contact()
	check(jessica.car.get_instance_id() == serial and owned_car_count() == 1,"repeated proximity admission preserves unique ownership")
	check(await walk(jessica.actor.global_position+Vector3(0,0,1.4)),"walk to Jessica on supported street ground")
	check(session.nearest().get("id","") == "jessica" and session.interact(),"real interaction opens first conversation")
	await capture("01-first-meeting")
	await finish_dialogue()
	check(PROGRESS.data(session.state.world_state).met,"conversation callback records acquaintance")
	check(session.mission_world.begin("jessica_bank"),"accept bank mission through the production campaign adapter")
	await finish_dialogue()
	await frames(3)
	report.acceptance_context = {"modal":session.modal,"dialogue_open":session.dialogue_open,
		"nearest":session.nearest(),"jessica_action":jessica.nearest_action(),"phase":PROGRESS.data(session.state.world_state).bank_phase,
		"player":str(world.player.global_position),"contact":str(jessica.actor.global_position),"step":session.state.campaign.step}
	check(jessica.nearest_action().get("target","") == "agree" and session.interact(),"talk to Jessica to agree to the actual bank job")
	await finish_dialogue()
	check(session.state.campaign.step == 1 and PROGRESS.data(session.state.world_state).bank_phase == "accepted","mission step and robbery-cycle baseline agree")
	if not failures.is_empty(): await finish(); return
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for("harbor_bank")
	var door: Vector3 = access._door_position("harbor_bank",definition)
	check(await walk(door+Vector3(0,0,1.7)),"walk from Jessica to the bank facade")
	if not failures.is_empty(): await finish(); return
	world.player.automatic_direction = Vector3.FORWARD
	for i in 240:
		await physics_frame
		if session.state.place_id == "harbor_bank": break
	world.player.automatic_direction = Vector3.ZERO
	await frames(45)
	check(session.state.place_id == "harbor_bank","real exterior doorway admits the player")
	check(PROGRESS.data(session.state.world_state).bank_phase == "accepted","normal bank transition preserves Jessica's accepted job")
	if not failures.is_empty(): await finish(); return
	var room = session.room
	session.state.grant_weapon("pistol")
	session.state.equip_weapon("pistol")
	check(await walk(room.to_global(Vector3(0,0,.5))),"walk through lobby collision corridors")
	if not failures.is_empty(): await finish(); return
	var guard = heist._actors[0]
	check(world.gameplay.fire_at(guard.global_position),"actual pistol shot starts bank alarm and police response")
	await frames(24)
	check(heist.data.bank_alarm and heist.data.bank_shots and guard.health < 160,"bank runtime observes the real first hit")
	if not failures.is_empty(): await finish(); return
	# Same controlled combat finish as test_bank_gameplay; all following spatial,
	# robbery, economic and getaway boundaries remain production paths.
	for actor in heist._actors:
		if actor.guard: actor.receive_damage(200,world.player)
	var card: Vector3 = room.to_global(Vector3(heist.data.keycard_position[0],0,heist.data.keycard_position[2]))
	check(await walk(card+Vector3(.6,0,0)),"walk to the guard's actual dropped keycard")
	check(heist.data.keycard_taken,"keycard is collected by real proximity and reachability")
	if not failures.is_empty(): await finish(); return
	check(await walk(room.to_global(Vector3(0,0,.5))) and await walk(room.to_global(HEIST.VAULT)),"reach closed vault through central aisle")
	if not failures.is_empty(): await finish(); return
	check(session.nearest().get("target","") == "bank_vault" and session.interact(),"ordinary interaction starts the actual vault hold")
	Input.action_press("interact")
	await frames(42)
	Input.action_release("interact")
	check(heist.lockpick.active and world.player.input_locked,"vault puzzle locks movement")
	if not failures.is_empty(): await finish(); return
	for i in 3:
		heist.lockpick.angle = heist.lockpick.target_angle
		heist.lockpick.attempt()
	await frames(195)
	check(heist.data.vault_open,"three puzzle pins open the physical vault")
	if not failures.is_empty(): await finish(); return
	var balance_before_loot: int = session.state.economy.balance
	check(await walk(room.to_global(Vector3(0,0,-4.2))),"walk through opened vault threshold")
	if not failures.is_empty(): await finish(); return
	check(await walk(room.to_global(HEIST.LOOT[0])) and await walk(room.to_global(HEIST.LOOT[2])),"walk to all three real cash piles")
	if not failures.is_empty(): await finish(); return
	check(heist.data.bank_pending == 15000 and session.state.economy.balance == balance_before_loot,"cash stays at risk inside bank and cannot fake Jessica escape")
	check(session.state.campaign.step == 1,"cash collection alone cannot advance the escape step")
	if not failures.is_empty(): await finish(); return
	await capture("02-real-bank-haul")
	check(await walk(room.to_global(Vector3(0,0,-4.2))) and await walk(room.to_global(Vector3(0,0,.5))),"leave vault via actual open doorway")
	if not failures.is_empty(): await finish(); return
	check(await walk(room.to_global(Vector3(.95,0,3.3))),"reach wide bank exit corridor")
	if not failures.is_empty(): await finish(); return
	world.player.automatic_direction = Vector3.BACK
	for i in 240:
		await physics_frame
		if session.state.place_id.is_empty(): break
	world.player.automatic_direction = Vector3.ZERO
	await frames(50)
	var receipt := "bank_haul:%d:7" % int(heist.data.bank_cycle)
	check(session.state.place_id.is_empty() and heist.data.bank_pending == 0 and session.state.economy.has_reward_receipt(receipt),"real bank departure secures the real robbery receipt")
	check(PROGRESS.data(session.state.world_state).haul_receipt == receipt and session.state.campaign.step == 2,"Jessica campaign advances from that exact economic receipt")
	if not failures.is_empty(): await finish(); return
	check(session.state.equip_weapon("fists"),"holster after the bank exit")
	check(await walk(jessica.passenger_point(),16.0),"reach Jetta passenger side without crossing its solid body")
	if not failures.is_empty(): await finish(); return
	await capture("03-getaway-boarding")
	check(jessica.nearest_action().get("target","") == "board" and session.interact(),"ordinary passenger interaction starts physical getaway")
	if not failures.is_empty(): await finish(); return
	check(jessica.route_native,"getaway route uses compiled C# graph search in the .NET runtime")
	report.route_native = jessica.route_native
	report.route_legs = jessica.route_legs.duplicate(true)
	check(jessica.route_legs.get("first_native",false) and jessica.route_legs.get("second_native",false) and jessica.route_legs.get("third_native",false),"all three directed road legs use compiled C# search")
	check(float(jessica.route_legs.get("seam_distance",INF)) <= .75 and float(jessica.route_legs.get("seam_direction_dot",-1)) >= .95,"native road legs join continuously in the same direction")
	check(jessica.route_legs.get("seams",[]).size() == 2,"both native waypoint joins are diagnosed")
	check(float(jessica.route_legs.get("safe_distance",INF)) <= 12,"courtyard endpoint remains within the actual safe-place radius")
	check(jessica.riding and world.player.input_locked and not world.player.is_physics_processing() and not world.driving.occupied,"Jessica owns driving and passenger control is locked")
	check(world.player.seated and world.player.visible and world.player.collision_layer == 0,"actual Dante rig remains visibly seated as passenger with collision disabled")
	check(not session.state.can_attack() and not session.save_game(true),"combat and in-flight save are blocked")
	if not failures.is_empty(): await finish(); return
	var held: Vector3 = jessica.car.global_position
	Input.action_press("move_up")
	await frames(30)
	Input.action_release("move_up")
	check(jessica.car.global_position.distance_to(held) < .05,"getaway dialogue holds the car despite movement input")
	await finish_dialogue()
	check(world.player.input_locked,"closing dialogue preserves passenger control ownership")
	var began := Time.get_ticks_msec()
	var sample_clock := 0
	while jessica.riding and Time.get_ticks_msec()-began < 180000:
		await physics_frame
		if not _ride_captured and Time.get_ticks_msec()-began >= 500:
			_ride_captured = true
			await capture("03b-actual-passenger-ride")
		sample_clock += 1
		if sample_clock >= 15:
			sample_clock = 0
			report.samples.append({"t_ms":Time.get_ticks_msec()-began,"position":str(jessica.car.global_position) if is_instance_valid(jessica.car) else "missing",
				"speed":jessica.car.speed if is_instance_valid(jessica.car) else 0,"car_health":jessica.car.health if is_instance_valid(jessica.car) else 0,
				"wanted":world.gameplay.stars,"player_health":world.gameplay.health,"on_floor":jessica.car.is_on_floor() if is_instance_valid(jessica.car) else false,
				"travelled":jessica._travelled,"route_offset":jessica.car.route_distance if is_instance_valid(jessica.car) else 0,
				"driver":jessica.driver.debug_snapshot()})
		if is_instance_valid(jessica.car) and jessica.car.global_position.y < -1.0:
			check(false,"surface getaway lost physical floor support")
			break
		if session.rescue_pending or session.arrest_pending: break
	check(not jessica.riding and PROGRESS.data(session.state.world_state).bank_phase == "returned","real road route and natural pursuit loss reach collision-safe return")
	check(not session.rescue_pending and not session.arrest_pending and world.gameplay.health > 0,"normal getaway survives without godmode or rescue")
	check(jessica._travelled >= 25 and world.gameplay.stars == 0,"actual travelled distance and natural zero-wanted state satisfy return")
	if not failures.is_empty(): await finish(); return
	check(world.player.visible and world.player.is_physics_processing() and world.camera.target == world.player,"safe exit restores visibility, physics and camera")
	check(not world.player.seated and not world.player.has_meta("seated_state") and world.player.visual.position.is_zero_approx(),"safe exit releases passenger pose and restores standing visual")
	check(session.position_clear(world.player.global_position),"exited passenger stands clear of car and solids")
	check(jessica._inside_courtyard(),"complete vehicle footprint rests inside the actual workshop court")
	await capture("04-safe-return")
	report.exit_diagnostic = jessica.last_exit_diagnostic.duplicate(true)
	var parked_position: Vector3 = jessica.car.global_position
	await frames(30)
	check(jessica.car.global_position.distance_to(parked_position) < .05 and jessica._inside_courtyard(),"desembarked actors preserve the stable collidable parked vehicle")
	var walkway: PackedVector3Array = COURT_PATH.path(world,jessica.car,jessica.actor)
	check(not walkway.is_empty(),"actual south walking corridor is admitted with both parked cars")
	for point: Vector3 in walkway:
		check(await walk(point,12.0,true,true),"ordinary walking follows the real south passage to Jessica")
	if not session.dialogue_open: check(jessica.perform("debrief"),"interaction opens the post-getaway conversation")
	var before_debrief: int = session.state.economy.balance
	await finish_dialogue()
	check(session.state.campaign.snapshot().completed.has("jessica_bank") and PROGRESS.data(session.state.world_state).bank_complete,"finished debrief completes both campaign and encounter record")
	check(session.state.economy.has_reward_receipt("campaign:jessica_bank") and session.state.economy.balance >= before_debrief+500,"campaign reward uses its own single receipt in addition to bank haul")
	check(owned_car_count() == 1,"getaway does not duplicate Jessica's personal vehicle")
	check(session.save_game(),"ordinary checkpoint snapshot is allowed after safe debrief")
	var snapshot: Dictionary = session.state.snapshot()
	check(STATE.new().restore_snapshot(JSON.parse_string(JSON.stringify(snapshot))),"completed getaway snapshot passes real GameState validation")
	var duplicated := false
	for vehicle in snapshot.world.vehicles:
		if vehicle.get("vehicle_id","") == PROGRESS.CAR_ID: duplicated = true
	check(not duplicated and snapshot.world.jessica_vehicle.vehicle_id == PROGRESS.CAR_ID,"owner record is unique and excluded from generic fleet")
	var store := STORE.new()
	store.path = folder.path_join("completed-save.json")
	var restored := STATE.new()
	check(store.save(session.state) == OK and store.load_into(restored).get("ok",false),"isolated final disk save and load preserve the completed bank mission")
	check(PROGRESS.data(restored.world_state).bank_complete and restored.economy.has_reward_receipt(receipt),"loaded state preserves both story completion and actual bank receipt")
	await capture("05-completed")
	await finish()

func owned_car_count() -> int:
	var count := 0
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and vehicle.vehicle_id == PROGRESS.CAR_ID: count += 1
	return count

func write_report() -> void:
	if folder.is_empty(): return
	report.checks = checks
	report.failures = failures.duplicate()
	if is_instance_valid(world) and world.session != null:
		report.story = PROGRESS.data(world.session.state.world_state)
		report.campaign = world.session.state.campaign.snapshot()
		report.vehicle = world.session.jessica.vehicle_snapshot()
		report.last_getaway_failure = world.session.jessica.last_failure_diagnostic.duplicate(true)
		if _measure_getaway:
			report.rendered_getaway = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
				"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,
				"summary":frame_stats(_perf_frames),"warmup":frame_stats(_perf_warm),"cpu_process":frame_stats(_perf_cpu),"physics":frame_stats(_perf_physics),
				"frame_intervals_ms":_perf_frames,"warmup_intervals_ms":_perf_warm,"population_trace":_perf_population,
				"limits":"Current route budget; no equivalent baseline. Five seconds of warmup; all remaining escape frames. CPU monitors do not isolate GPU cost. Captures are before steady sampling or after escape."}
	var file := FileAccess.open(folder.path_join("integration.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t"))

func finish() -> void:
	Input.action_release("interact")
	Input.action_release("move_up")
	write_report()
	print("JESSICA_INTEGRATION_RESULT checks=%d failures=%d evidence=%s" % [checks,failures.size(),folder])
	if is_instance_valid(world):
		if world.session != null and world.session.jessica != null: world.session.jessica.cancel_for_transition()
		world.queue_free()
		await frames(3)
	quit(0 if failures.is_empty() else 1)
