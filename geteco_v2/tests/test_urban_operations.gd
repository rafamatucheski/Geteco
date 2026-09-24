extends SceneTree
## Integrated, synthetic-only validation for productive Harbor routines. The
## launcher must pass --no-save; no fixture reads or writes a personal save.

const PORT_CENTER := Vector3(5800.0 / 16.0, .05, 4300.0 / 16.0)
const CEMETERY_CENTER := Vector3(-650.0 / 16.0, .05, 1740.0 / 16.0)

class SyntheticDeceased:
	extends Node3D
	func receive_damage(_amount: float, _source: Node = null) -> void: pass

class SyntheticCrew:
	extends Node
	var mode := "service"

class SyntheticTrafficBody:
	extends CharacterBody3D
	var traffic := true
	var health := 100.0
	var equipment: Node

var world
var session
var urban
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: return
	failures.append(label)
	push_error(label)

func settle(frames := 4) -> void:
	for _frame in frames: await physics_frame

func actor_count(persistent_id: String) -> int:
	var count := 0
	for child in world.get_children():
		if child.get_meta("persistent_id","") == persistent_id and not child.is_queued_for_deletion(): count += 1
	return count

func actor_prefix_count(prefix: String) -> int:
	var count := 0
	for child in world.get_children():
		if str(child.get_meta("persistent_id","")).begins_with(prefix) and not child.is_queued_for_deletion(): count += 1
	return count

func vehicle_prefix_count(prefix: String) -> int:
	var count := 0
	for child in world.get_children():
		var vehicle_id: Variant = child.get("vehicle_id")
		if vehicle_id is String and vehicle_id.begins_with(prefix) and not child.is_queued_for_deletion(): count += 1
	return count

func person_instance_present(instance_id: int) -> bool:
	for person in world.people:
		if is_instance_valid(person) and person.get_instance_id()==instance_id: return true
	return false

func vehicle_instance_present(instance_id: int) -> bool:
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and vehicle.get_instance_id()==instance_id: return true
	return false

func port_work_vehicle_count() -> int:
	var count := 0
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and vehicle.get_meta("port_work_vehicle",false): count += 1
	return count

func _initialize_world() -> bool:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 360:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: return false
	session = world.session
	urban = session.urban_operations
	return is_instance_valid(urban) and is_instance_valid(urban.port) and is_instance_valid(urban.cemetery) and is_instance_valid(urban.cargo_handling)

func run() -> void:
	check(await _initialize_world(),"Integrated Main exposes Harbor urban operations")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save,"Urban fixture cannot access a personal save")
	await _port_cycle()
	await _security_cycle()
	var economy_after_security: Dictionary = session.state.economy.snapshot()
	await _cemetery_cycle()
	await _snapshot_contract()
	check(session.state.economy.snapshot()==economy_after_security,"Port and cemetery operations do not duplicate or grant rewards")
	check(session.save_game(),"No-save session accepts an in-memory urban snapshot")
	check(session.state.world_state.get("urban_operations",{}).get("version",0)==1,"FullSession owns the urban snapshot connection")
	await _shutdown_contract()
	world.free()
	await process_frame
	print("URBAN_OPERATIONS ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _port_cycle() -> void:
	world.player.teleport(PORT_CENTER)
	world.production.region.set_focus(PORT_CENTER)
	urban.refresh_context()
	await settle(120)
	var port = urban.port
	check(port.active and port.boats.size()==2,"Both productive V1 launch berths stream in")
	var cargo = urban.cargo_handling
	check(cargo.cranes.size()==3,"All three productive V1 quay cranes are present")
	check(cargo.active,"The V1 quay crane operation streams in near the port")
	check(cargo.work_trucks.size()==3 and cargo.forklifts.size()==2 and port_work_vehicle_count()==5,"Three freight trucks and two driveable forklifts stream in as port work vehicles")
	check(cargo.forklift_crates.size()==6,"V1 forklift freight crates remain at their bays")
	var moving_load: Dictionary = cargo.cargo_pose(0,12.0)
	check(is_equal_approx(float(moving_load.along),.5) and is_equal_approx(float(moving_load.lift),70.0/16.0),"The quay crane lifts and transfers its container along the V1 cycle")
	check(actor_count("south_port_launch_loader_00")==1 and actor_count("south_port_launch_loader_01")==1,"Exactly one loader owns each launch")
	var boat: Dictionary = port.boats[0]
	var worker = boat.worker
	worker.crate_stock.assign([0,1])
	worker.carrying = false
	worker._set_activity("rest")
	boat.load = 29
	port._tick_boat(0,.1)
	check(boat.phase=="departing" and int(boat.load)==30 and worker.crate_total()==3,"Thirty loaded crates start departure and the V1 three-crate dock task")
	port._tick_boat(0,2.6)
	check(boat.phase=="away" and not boat.visual.visible,"Loaded launch leaves the rendered harbor")
	port._tick_boat(0,7.6)
	check(boat.phase=="returning" and int(boat.load)==0 and boat.visual.visible,"Launch returns empty after its productive away phase")
	port._tick_boat(0,2.6)
	check(boat.phase=="loading" and worker.crate_total()==30,"Returned launch begins a new thirty-crate cycle")
	# Exercise suspension in the middle of real loader progress.
	boat.load = 7
	worker.crate_stock.assign([22,1])
	worker.carrying = false
	worker._set_activity("rest")
	var interrupted: Dictionary = port.snapshot()
	world.player.teleport(Vector3.ZERO)
	urban.refresh_context()
	await settle()
	check(not port.active and actor_count("south_port_launch_loader_00")==0 and actor_count("south_port_launch_loader_01")==0,"Leaving the port suspends loader attachments")
	world.player.teleport(PORT_CENTER)
	urban.refresh_context()
	await settle()
	check(port.active and actor_count("south_port_launch_loader_00")==1 and actor_count("south_port_launch_loader_01")==1,"Returning recreates loaders exactly once")
	check(port.boats[0].phase=="loading" and int(port.boats[0].load)+port.boats[0].worker.crate_total()==30,"Return preserves cargo and interrupted loader state")
	# An authoritative restore must replace, rather than stack, live workers.
	port.boats[0].load = 18
	check(port.restore_snapshot(interrupted),"Synthetic port snapshot restores")
	await settle()
	check(actor_count("south_port_launch_loader_00")==1 and int(port.boats[0].load)+port.boats[0].worker.crate_total()==30,"Restore cannot duplicate a loader or its cargo")

func _security_cycle() -> void:
	var security = urban.security
	var routines = preload("res://gameplay/routines_v1/RoutineCatalog.gd").definitions()
	var port_workers := routines.filter(func(item): return str(item.id).begins_with("south_port_worker_"))
	check(port_workers.size()==32,"The V1 port keeps all 32 worker routines")
	var guard = security._staff[0]
	world.player.global_position = Vector3(3310.0/16.0,.05,3200.0/16.0)
	security._process(.3)
	await settle()
	var checkpoint: Vector3 = guard.global_position + Vector3(0,0,.75)
	world.player.teleport(checkpoint)
	world.production.region.set_focus(checkpoint)
	await settle()
	check(security.active and security._staff.size()==3,"The physical checkpoint and three security workers stream into Harbor")
	var gate_blocks_road := false
	for part in security._gate_parts:
		if not (part.collision as CollisionShape3D).disabled: gate_blocks_road = true
	check(not security.gate_open and gate_blocks_road,"The closed freight barriers physically block the access road")
	check(security.perform("south_port_checkpoint"),"The checkpoint opens its interaction at the guard")
	check(session.state.economy.grant_reward("test:south_port_bribe",100),"Synthetic fixture funds the port authorization")
	security._pay_bribe()
	security._process(.3)
	check(security.authorized_entry and security.gate_open,"A paid authorization opens the physical barrier")
	await settle()
	var gate_clear := true
	for part in security._gate_parts:
		if not (part.collision as CollisionShape3D).disabled: gate_clear = false
	check(gate_clear,"The authorization removes both physical collision barriers")
	world.player.global_position = Vector3(3500.0/16.0,.05,3500.0/16.0)
	security._process(.3)
	check(security.authorized_visit and not security.authorized_entry and not security.alerted,"Authorized crossing records a clean port visit")
	world.player.global_position = Vector3(3310.0/16.0,.05,3330.0/16.0)
	security._process(.3)
	await settle()
	check(not security.authorized_visit and not security.authorized_entry and not security.gate_open,"Leaving through the checkpoint closes the barrier and consumes the pass")
	world.production.set_population(0)
	var private_point := Vector3(3500.0/16.0,.05,3500.0/16.0)
	var pedestrian = preload("res://scripts/Actor.gd").new()
	world.add_child(pedestrian)
	pedestrian.global_position = private_point
	world.people.append(pedestrian)
	var pedestrian_instance_id: int = pedestrian.get_instance_id()
	var ambient_car := SyntheticTrafficBody.new()
	ambient_car.set_meta("ambient_traffic",true)
	world.add_child(ambient_car)
	ambient_car.global_position = private_point
	world.production.vehicles.append(ambient_car)
	var ambient_instance_id: int = ambient_car.get_instance_id()
	var mission_car := SyntheticTrafficBody.new()
	mission_car.set_meta("passenger_transport",true)
	world.add_child(mission_car)
	mission_car.equipment = Node.new()
	mission_car.add_child(mission_car.equipment)
	mission_car.global_position = private_point
	world.production.vehicles.append(mission_car)
	world.production._process(.3)
	await process_frame
	check(not person_instance_present(pedestrian_instance_id) and not is_instance_valid(pedestrian),"Ambient pedestrians are removed from the private port")
	check(not vehicle_instance_present(ambient_instance_id) and not is_instance_valid(ambient_car),"Ambient traffic cars are removed from the private port")
	check(world.production.vehicles.has(mission_car) and is_instance_valid(mission_car),"Scripted passenger traffic is preserved separately")
	world.production.vehicles.erase(mission_car)
	mission_car.queue_free()
	await process_frame

func _cemetery_cycle() -> void:
	# Exercise the real FullSession entry/exit path before the outdoor funeral.
	world.player.teleport(CEMETERY_CENTER)
	world.production.region.set_focus(CEMETERY_CENTER)
	urban.refresh_context()
	await settle()
	check(actor_count("cemetery_keeper")==1 and actor_count("cemetery_storyteller")==1,"Cemetery yard streams its two named residents")
	check(cemetery_story_color()==Color("514b43"),"Storyteller keeps the V1 coat color")
	check(await session.enter_place("cemetery_keeper",false),"Keeper house uses the existing place transition")
	await settle()
	var cemetery = urban.cemetery
	check(actor_count("cemetery_keeper")==1 and actor_count("cemetery_storyteller")==0,"House installs only the keeper attachment")
	world.player.teleport(cemetery.keeper.global_position+Vector3(.8,.04,0))
	await settle()
	check(cemetery.perform("cemetery_keeper"),"Keeper exposes the productive V1 secret conversation")
	check(cemetery.secret_known and session.dialogue_open,"Secret knowledge changes only after the physical conversation")
	session.close_menu()
	check(session.leave_place(),"Keeper house exits through FullSession")
	await settle()
	check(actor_count("cemetery_keeper")==1 and actor_count("cemetery_storyteller")==1,"Yard return reconstructs each cemetery resident exactly once")
	# Drive the adapter through the real EmergencyManager collection ledger.
	var deceased := SyntheticDeceased.new()
	deceased.name = "AlziraDoCais"
	deceased.set_meta("display_name","Alzira do Cais")
	world.add_child(deceased)
	deceased.global_position = CEMETERY_CENTER+Vector3(4,0,0)
	var emergency = world.gameplay.emergency
	emergency.report_injury(deceased,true)
	var incident_key: Variant = null
	for key in emergency.incidents:
		if emergency.incidents[key].actor == deceased: incident_key = key
	check(incident_key != null,"Fatal actor enters the real EmergencyManager ledger")
	if incident_key == null: return
	cemetery._observe_emergency()
	var burial_identity := str(deceased.get_meta("urban_burial_identity",""))
	check(not burial_identity.is_empty() and cemetery.cases[burial_identity].phase=="discovered","Fatal incident receives one stable cemetery identity")
	var collection := SyntheticCrew.new()
	emergency.add_child(collection)
	emergency.incidents[incident_key].crew = collection
	emergency.incidents[incident_key].assigned = true
	cemetery._observe_emergency()
	check(cemetery.cases[burial_identity].phase=="collection","Emergency service advances the same identity to collection")
	emergency.complete(incident_key)
	cemetery._observe_emergency()
	check(cemetery.cases[burial_identity].phase=="morgue","Collected identity reaches the funeral queue")
	check(not cemetery.incident_links.has(incident_key),"Completed emergency releases its actor link")
	check(not cemetery.register_synthetic_case(burial_identity,"Duplicada"),"Stable identity rejects a duplicate death")
	cemetery._try_start_trip()
	await settle()
	check(cemetery.trip_identity==burial_identity and cemetery.cases[burial_identity].phase=="burial","Mortician reserves one plot and starts a funeral")
	check(actor_count("cemetery_mortician")==1,"One funeral agent owns the active burial")
	check(actor_prefix_count("cemetery_mourner_")==5,"The five productive V1 funeral guests attend once")
	check(mourner_colors_match(),"Funeral guests keep the two alternating V1 coat colors")
	check(vehicle_prefix_count("funeral_hearse:")==1,"One hearse owns the active funeral")
	cemetery.mortician.route_index = cemetery.mortician.route.size()
	cemetery._tick_trip(.1)
	cemetery._tick_trip(5.1)
	check(cemetery.cases[burial_identity].phase=="buried" and cemetery.graves.has(burial_identity),"Completed service materializes one stable grave")
	cemetery.mortician.route_index = cemetery.mortician.route.size()
	cemetery._tick_trip(.1)
	await settle()
	check(cemetery.trip_identity.is_empty() and actor_count("cemetery_mortician")==0 and actor_prefix_count("cemetery_mourner_")==0,"Funeral attachments leave after burial")
	# Snapshot during the next funeral: the persisted owner normalizes it back
	# to the morgue, so restore can resume without a second hearse or grave.
	check(cemetery.register_synthetic_case("test:bento","Bento Maquinista"),"Second synthetic identity enters independently")
	cemetery._try_start_trip()
	var interrupted: Dictionary = cemetery.snapshot()
	check(interrupted.cases.any(func(record): return record.identity=="test:bento" and record.phase=="morgue"),"Interrupted burial serializes as resumable work")
	check(cemetery.restore_snapshot(interrupted),"Synthetic cemetery snapshot restores")
	await settle()
	check(actor_count("cemetery_mortician")==1 and actor_prefix_count("cemetery_mourner_")==5 and cemetery.trip_identity=="test:bento","Restore resumes exactly one funeral service")
	check(vehicle_prefix_count("funeral_hearse:")==1,"Restore replaces instead of stacking the hearse")
	check(cemetery.graves.size()==1 and cemetery.graves.has(burial_identity),"Restore neither loses nor duplicates completed graves")
	world.player.teleport(CEMETERY_CENTER+Vector3(100,0,0))
	urban.refresh_context()
	await settle()
	check(not cemetery.active and cemetery.cases["test:bento"].phase=="morgue" and actor_count("cemetery_mortician")==0 and actor_prefix_count("cemetery_mourner_")==0,"Afastamento interrompe o serviço sem perder identidade ou lote")
	world.player.teleport(CEMETERY_CENTER)
	urban.refresh_context()
	await settle()
	check(cemetery.active and cemetery.trip_identity=="test:bento" and actor_count("cemetery_mortician")==1 and actor_prefix_count("cemetery_mourner_")==5,"Retorno retoma o serviço uma única vez")
	check(vehicle_prefix_count("funeral_hearse:")==1,"Retorno retoma um único carro funerário")

func _snapshot_contract() -> void:
	var encoded: Variant = JSON.parse_string(JSON.stringify(urban.snapshot()))
	check(encoded is Dictionary and urban.validate_snapshot(encoded),"Urban snapshot survives the JSON boundary")
	check(urban.restore_snapshot(encoded),"Urban coordinator restores its complete synthetic state")
	await settle()
	check(actor_count("south_port_launch_loader_00")<=1 and actor_count("cemetery_mortician")==1 and actor_prefix_count("cemetery_mourner_")==5,"Coordinator restore owns one copy of every attachment")
	var invalid_port: Dictionary = encoded.duplicate(true)
	invalid_port.port.boats[0].worker.crate_stock[0] = 999
	check(not urban.validate_snapshot(invalid_port),"Impossible cargo is rejected before restore")
	var invalid_cemetery: Dictionary = encoded.duplicate(true)
	for record in invalid_cemetery.cemetery.cases:
		if record.phase=="buried": record.plot=-1
	check(not urban.validate_snapshot(invalid_cemetery),"A buried identity without a plot is rejected")
	var transient_case: Dictionary = urban.cemetery.cases.duplicate(true)
	urban.cemetery.cases["test:uncollected"]={"identity":"test:uncollected","name":"Sem coleta","phase":"dispatched","plot":-1}
	var normalized: Dictionary = urban.cemetery.snapshot()
	check(normalized.cases.any(func(record): return record.identity=="test:uncollected" and record.phase=="unrecovered"),"Unpersisted emergency attachments normalize to an unrecovered identity")
	urban.cemetery.cases=transient_case
	var stale_serial: Dictionary = encoded.duplicate(true)
	stale_serial.cemetery.serial = 0
	check(urban.validate_snapshot(stale_serial) and urban.restore_snapshot(stale_serial),"Legacy snapshot with a stale serial remains migratable")
	check(urban.cemetery._next_deceased_identity()!="harbor_deceased:00000001","Migrated identity allocator skips an occupied legacy id")

func _shutdown_contract() -> void:
	# Leave an active funeral in place, then remove its service. Sibling
	# attachments must not outlive the ledger that owns them.
	world.player.teleport(CEMETERY_CENTER)
	world.production.region.set_focus(CEMETERY_CENTER)
	urban.refresh_context()
	await settle()
	check(actor_count("cemetery_mortician")==1 and vehicle_prefix_count("funeral_hearse:")==1,"Shutdown fixture has live funeral attachments")
	urban.cemetery.queue_free()
	await settle()
	check(actor_count("cemetery_keeper")==0 and actor_count("cemetery_storyteller")==0,"Service shutdown releases named cemetery actors")
	check(actor_count("cemetery_mortician")==0 and actor_prefix_count("cemetery_mourner_")==0 and vehicle_prefix_count("funeral_hearse:")==0,"Service shutdown releases funeral attachments")
	world.player.teleport(PORT_CENTER)
	world.production.region.set_focus(PORT_CENTER)
	urban.refresh_context()
	await settle()
	check(actor_count("south_port_launch_loader_00")==1 and actor_count("south_port_launch_loader_01")==1,"Port shutdown fixture has both live loaders")
	urban.queue_free()
	await settle()
	check(actor_count("south_port_launch_loader_00")==0 and actor_count("south_port_launch_loader_01")==0,"Port service shutdown releases both loader attachments")

func cemetery_story_color() -> Color:
	for child in world.get_children():
		if child.get_meta("persistent_id","")=="cemetery_storyteller" and is_instance_valid(child.visual): return child.visual.shirt_color
	return Color.TRANSPARENT

func mourner_colors_match() -> bool:
	for index in 5:
		var expected := Color("343543") if index%2 else Color("45434b")
		var found := false
		for child in world.get_children():
			if child.get_meta("persistent_id","")=="cemetery_mourner_%02d" % index and is_instance_valid(child.visual):
				found = child.visual.shirt_color==expected
				break
		if not found: return false
	return true
