extends SceneTree
## Real Main/ProductionWorld, collision contact, native damage art and persistence.
## This headless test asserts state and physical bodies; rendered art is separate.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")
var world: Node3D
var checks := 0
var failures: Array[String] = []
var explosions: Dictionary = {}
var deaths: Dictionary = {}
var watched: Dictionary = {}
var authors: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("CRUSH_EXPLOSION PASS " if ok else "CRUSH_EXPLOSION FAIL ")+label)
	if not ok: failures.append(label)
func settle(frames := 2) -> void:
	for index in frames: await physics_frame

func tracked(car: CharacterBody3D) -> void:
	var id := car.get_instance_id()
	deaths[id] = 0
	explosions[id] = 0
	watched[id] = weakref(car)
	car.destroyed.connect(func(): deaths[id] += 1)
	car.set_physics_process(false)
	if car.has_node("TankDriverControls"): car.get_node("TankDriverControls").set_physics_process(false)

func add_car(archetype: String, point: Vector3, parent: Node3D = null) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = archetype
	car.vehicle_id = "crush_explosion_test_"+str(Time.get_ticks_usec())
	car.position = point
	(parent if parent != null else world).add_child(car)
	tracked(car)
	return car

func charred(car: CharacterBody3D) -> bool:
	var look: Node = car.damage_look
	if look == null or not look.wrecked or look._ember == null: return false
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.material_override == look._ember: return true
		if part.mesh != null:
			for index in part.mesh.get_surface_count():
				if part.get_surface_override_material(index) == look._ember: return true
	return false

func solid(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.position = point
	return body

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(120).timeout.connect(func(): push_error("CRUSH_EXPLOSION timeout"); quit(2))
	seed(28092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play and world.production.no_save,"Main starts without touching player saves")
	if not failures.is_empty(): world.free(); quit(1); return
	world.gameplay.set_physics_process(false)
	world.gameplay.police_air.set_physics_process(false)
	world.dispatch.set_physics_process(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.explosion_occurred.connect(func(point,radius,source):
		if not is_equal_approx(radius,5.0): return
		for id in watched:
			var car: Node3D = watched[id].get_ref()
			if car != null and car.global_position.distance_to(point) < 1.0:
				explosions[id] += 1
				authors[id] = source)
	var spot := Vector3.INF
	var yaw := 0.0
	for candidate in world.dispatch.router.spawn_candidates(world.player.global_position,12.0,95.0,14.0):
		world.production.region.prepare_collision_at(candidate.point)
		await settle()
		if not world.dispatch._space_clear(Vector3(8.0,4.0,18.0),candidate.point,candidate.yaw,world.dispatch.no_exclusions): continue
		# Road graph points lie on the surface. Dispatch also lifts vehicle
		# spawn by .12 m; Production's exact hull admission needs that clearance.
		spot = candidate.point+Vector3.UP*.12
		yaw = candidate.yaw
		break
	check(spot.is_finite(),"test uses physically clear real street")
	if not spot.is_finite(): world.free(); quit(1); return
	world.production.region.set_focus(spot)
	var victim: CharacterBody3D = world.production.spawn_vehicle("sport_coupe",spot,yaw)
	check(victim != null,"ProductionWorld creates vehicle with actual destruction handler")
	if victim == null: world.free(); quit(1); return
	tracked(victim)
	var tank := add_car("army_tank",spot)
	tank.controlled = true
	tank.rotation.y = yaw
	var forward := -tank.global_basis.z
	tank.position = spot-forward*(tank.half_length+victim.half_length+.10)
	await settle()
	var victim_id := victim.get_instance_id()
	var original_shape: Shape3D = victim.shape.shape
	var original_visual: Vector3 = victim.visual.scale
	var original_layer: int = victim.collision_layer
	var original_mask: int = victim.collision_mask
	var original_health: float = tank.health
	var found := CRUSH.prepare(tank,forward*9.0,1.0/60.0)
	check(found == victim,"tank contact triggers crushing through real shape sweep")
	check(victim.health == 0 and deaths[victim_id] == 1,"first crush destroys vehicle exactly once")
	check(explosions[victim_id] == 1,"Production destruction handler and fallback produce one explosion")
	check(authors.get(victim_id) == world.player,"crush explosion retains player authorship from controlled tank")
	check(tank.health == original_health,"crushed car explosion does not damage its crusher")
	check(charred(victim),"actual body mesh receives charred wreck materials")
	check(victim.shape.shape is ConvexPolygonShape3D and victim.collision_layer == original_layer and victim.collision_mask == original_mask,"flattened convex hull retains original physical collision layers")
	check(victim.damage_look._wreck_body == null and not victim.has_node("WreckBody"),"crushed wreck does not create a separate hopping rigid body")
	check(victim.damage_look._wreck_fire_time > 0 and victim.damage_look._wreck_fire_time <= victim.damage_look.WRECK_FIRE_SECONDS,"wreck fire has finite existing lifetime")
	await settle()
	var ray := PhysicsRayQueryParameters3D.create(victim.global_position+Vector3.UP*2.0,victim.global_position-Vector3.UP,4,[tank.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == victim,"charred crushed hull still physically supports a ray from above")
	for index in 3:
		CRUSH.prepare(tank,forward*9.0,1.0/60.0)
		victim.crush(tank)
	check(deaths[victim_id] == 1 and explosions[victim_id] == 1,"repeated tank contact cannot repeat destruction or explosion")
	victim.damage_look._physics_process(victim.damage_look.WRECK_FIRE_SECONDS+.1)
	check(not victim.damage_look.is_physics_processing() and not victim.damage_look._fire.emitting and not victim.damage_look._fire_light.visible,"wreck fire shuts down after its bounded lifetime")
	var snapshot := FLEET_STATE.capture(victim,"harbor")
	check(FLEET_STATE.validate(snapshot) and snapshot.health == 0 and snapshot.heavy_crush_ratio < .55,"save stores destroyed crushed hull as valid fleet state")
	victim.repair()
	victim.set_physics_process(false)
	check(victim.health == victim.max_health and victim.shape.shape == original_shape and victim.visual.scale == original_visual and not victim.damage_look.wrecked,"repair restores health, original collision and full visual scale")
	check(not victim.has_meta("heavy_crush_ratio") and not victim.has_meta("heavy_crush_exploded"),"repair clears crush and explosion deduplication state")
	world.driving.car = victim
	world.session.state.world_state.vehicles = [snapshot]
	world.production._restore_player_vehicle()
	check(victim.health == 0 and victim.shape.shape is ConvexPolygonShape3D and charred(victim),"Production load restores crushed carbonized wreck")
	check(victim.damage_look._wreck_body == null and victim.collision_layer == original_layer,"restore preserves flattened collider without creating hop body")
	check(deaths[victim_id] == 1 and explosions[victim_id] == 1,"loading wreck does not replay destruction or explosion")
	check(victim.damage_look._wreck_fire_time == 0,"loading old wreck does not restart its extinguished fire")
	victim.crush(tank)
	check(explosions[victim_id] == 1,"restored wreck remains quiet on further crush contact")
	victim.repair()
	victim.set_physics_process(false)
	check(victim.health == victim.max_health and victim.shape.shape == original_shape and not victim.engine_disabled,"restored wreck remains fully repairable")
	# Real vehicles created by scripts may have no ProductionWorld handler.
	var fallback := add_car("sport_coupe",spot+Vector3(0,15,0))
	var fallback_id := fallback.get_instance_id()
	tank.set_external_driver(true)
	CRUSH.apply_saved(fallback,.26)
	check(fallback.crush(tank) and deaths[fallback_id] == 1 and explosions[fallback_id] == 1,"standalone vehicle fallback also destroys and explodes exactly once")
	check(authors.get(fallback_id) == tank and authors.get(fallback_id) != world.player,"NPC-controlled tank retains NPC explosion authorship")
	fallback.crush(tank)
	check(explosions[fallback_id] == 1,"standalone fallback deduplicates repeated crush calls")
	var garage: Node = world.session.garage_rewards
	garage.set_physics_process(false)
	fallback.vehicle_id = "garage_guest_932"
	fallback.set_meta("garage_reward",true)
	fallback.set_meta("garage_place","")
	fallback.set_meta("garage_origin",Vector3.ZERO)
	fallback.set_meta("region_id","harbor")
	garage.cars[fallback.vehicle_id] = fallback
	garage._capture_all()
	var garage_snapshot: Dictionary = garage.snapshot()
	var garage_record: Dictionary = garage_snapshot.vehicles[fallback.vehicle_id]
	check(GARAGE.validate_snapshot(garage_snapshot) and garage_record.health == 0 and is_equal_approx(garage_record.heavy_crush_ratio,fallback.get_meta("heavy_crush_ratio")),"real garage capture preserves valid destroyed crushed guest vehicle")
	for invalid in [0.0,2.0,"invalid"]:
		var malformed: Dictionary = garage_snapshot.duplicate(true)
		malformed.vehicles[fallback.vehicle_id].heavy_crush_ratio = invalid
		check(not GARAGE.validate_snapshot(malformed),"garage rejects malformed crush ratio "+str(invalid))
	var garage_restored := add_car("sport_coupe",spot+Vector3(0,45,0))
	garage._restore_damage(garage_restored,garage_record)
	check(garage_restored.health == 0 and garage_restored.shape.shape is ConvexPolygonShape3D and charred(garage_restored),"garage damage restore rebuilds crushed carbonized collision body")
	check(explosions[garage_restored.get_instance_id()] == 0 and garage_restored.damage_look._wreck_body == null and garage_restored.damage_look._wreck_fire_time == 0,"garage load neither explodes nor starts new fire or hopping body")
	var original_place: String = world.session.state.place_id
	world.session.state.place_id = "maciota"
	var safe_car := add_car("sport_coupe",spot+Vector3(0,60,0))
	CRUSH.apply_saved(safe_car,.26)
	check(safe_car.crush(tank) and safe_car.health == 0,"safe-zone fixture reaches actual crush destruction")
	check(explosions[safe_car.get_instance_id()] == 0 and safe_car.damage_look._fire == null and safe_car.damage_look._fire_light == null and safe_car.damage_look._wreck_fire_time == 0,"Maciota garage suppresses explosion, residual flames and fire light")
	world.session.state.place_id = original_place
	var protected_parent := Node3D.new()
	protected_parent.set_meta("invulnerable",true)
	world.add_child(protected_parent)
	var protected := add_car("sport_coupe",spot+Vector3(0,30,0),protected_parent)
	var protected_id := protected.get_instance_id()
	CRUSH.apply_saved(protected,.26)
	check(not protected.crush(tank) and not protected.has_meta("heavy_crush_ratio") and protected.health == protected.max_health,"Maciota-style ancestor protection rejects crush and deformation")
	await settle()
	world.gameplay.explode(protected.global_position+Vector3.UP,3.0,1000.0,tank,false)
	check(protected.health == protected.max_health and deaths[protected_id] == 0 and explosions[protected_id] == 0,"protected ancestor remains invulnerable to nearby explosion")
	check(not charred(protected) and protected.shape.shape is BoxShape3D,"protected body's materials and collision remain intact")
	# An isolated physical low ceiling in Main proves shape admission, without
	# depending on furniture or changing an authored interior.
	var platform := spot+Vector3(0,90,0)
	solid(platform-Vector3.UP*.1,Vector3(22,.2,22))
	solid(platform+Vector3.UP,Vector3(10,.4,10))
	world.player.teleport(platform+Vector3(8,.12,8))
	world.player.set_physics_process(false)
	await settle()
	var under_roof := platform+Vector3.UP*.12
	var full: CharacterBody3D = world.production.spawn_vehicle("sport_coupe",under_roof,0.0)
	check(full == null,"low physical ceiling rejects full-height vehicle at saved point")
	if full != null: full.queue_free()
	await settle()
	var flattened: CharacterBody3D = world.production.spawn_vehicle("sport_coupe",under_roof,0.0,.26)
	check(flattened != null and flattened.shape.shape is ConvexPolygonShape3D and not flattened.has_meta("awaiting_ground"),"spawn applies crush ratio before admitting hull beneath low ceiling")
	if flattened != null:
		flattened.set_physics_process(false)
		flattened.restore_health(0.0)
		var roof_snapshot := FLEET_STATE.capture(flattened,"harbor")
		flattened.queue_free()
		await settle()
		var restore_under_roof := add_car("sport_coupe",platform+Vector3(8,.12,0))
		world.driving.car = restore_under_roof
		world.session.state.world_state.vehicles = [roof_snapshot]
		world.production._restore_player_vehicle()
		check(restore_under_roof.global_position.distance_to(under_roof) < .001 and restore_under_roof.shape.shape is ConvexPolygonShape3D,"load admits crushed geometry and retains exact original position under ceiling")
		check(restore_under_roof.health == 0 and charred(restore_under_roof) and explosions[restore_under_roof.get_instance_id()] == 0,"low-ceiling load restores carbonized wreck without replaying explosion")
	_probe_capture("before_world_free")
	world.queue_free()
	await settle(10)
	_probe_capture("before_quit")
	if "--crush-probe-collect-remaining" in OS.get_cmdline_user_args():
		_probe_collect_remaining()
		_probe_capture("after_collect_remaining")
	_probe_write()
	print("CRUSH_EXPLOSION checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)

# Instrumentação somente da fixture; nunca limpa caches nem inicia novos requests.
var _probe_report: Dictionary = {"snapshots": [], "collected_paths": []}

func _probe_paths() -> Array[String]:
	var result: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/tank_control/crush_request_candidates.json"))
	if parsed is Array:
		for path: String in parsed: result.append(path)
	return result

func _probe_object(object: Object) -> Dictionary:
	if not is_instance_valid(object): return {}
	var script: Script = object.get_script() as Script
	return {"id": str(object.get_instance_id()), "class": object.get_class(), "script": script.resource_path if script != null else "", "reference_count_with_probe_reference": (object as RefCounted).get_reference_count() if object is RefCounted else -1}

func _probe_owner(owner: Object) -> Dictionary:
	var references: Array[Dictionary] = []
	for property: Dictionary in owner.get_property_list():
		var value: Variant = owner.get(property.name)
		if value is RefCounted and not value is Resource:
			var entry: Dictionary = _probe_object(value)
			entry["property"] = str(property.name)
			references.append(entry)
	var signals: Array[Dictionary] = []
	for signal_info: Dictionary in owner.get_signal_list():
		for connection: Dictionary in owner.get_signal_connection_list(signal_info.name):
			var callback: Callable = connection.callable
			signals.append({"signal": str(signal_info.name), "method": str(callback.get_method()), "target": _probe_object(callback.get_object()), "callable": str(callback)})
	return {"owner": _probe_object(owner), "direct_refcounted_properties": references, "signals": signals}

func _probe_capture(label: String) -> void:
	var requests: Array[Dictionary] = []
	var pending := 0
	for path: String in _probe_paths():
		var status: int = ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: pending += 1
		requests.append({"path": path, "status": status})
	var owners: Array[Dictionary] = [_probe_owner(self)]
	if is_instance_valid(world):
		for owner: Node in [world,world.production,world.session,world.gameplay]:
			if is_instance_valid(owner): owners.append(_probe_owner(owner))
	var tracked_alive := 0
	for id in watched:
		var car: Node = (watched[id] as WeakRef).get_ref() as Node
		if is_instance_valid(car):
			tracked_alive += 1
			owners.append(_probe_owner(car))
			var look: Node = car.get("damage_look") as Node
			if is_instance_valid(look): owners.append(_probe_owner(look))
	_probe_report.snapshots.append({"label":label,"pending_user_request_paths":pending,"requests":requests,"owners":owners,"tracked_vehicle_nodes_alive":tracked_alive,"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"process_frames":Engine.get_process_frames(),"physics_frames":Engine.get_physics_frames()})
	print("CRUSH_ATTRIBUTION label=%s pending_request_paths=%d tracked_nodes_alive=%d" % [label,pending,tracked_alive])

func _probe_collect_remaining() -> void:
	# Contraprova explícita em processo separado: coleta só requests existentes.
	# Não é correção de produção nem torna o baseline aprovado.
	for path: String in _probe_paths():
		var status: int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: continue
		var resource: Resource = ResourceLoader.load_threaded_get(path)
		_probe_report.collected_paths.append({"path":path,"status_before":status,"resource_class":resource.get_class() if resource != null else ""})
		resource = null

func _probe_write() -> void:
	var mode: String = "collect-remaining" if "--crush-probe-collect-remaining" in OS.get_cmdline_user_args() else "observe"
	_probe_report["mode"] = mode
	_probe_report["godot"] = Engine.get_version_info()
	_probe_report["pid"] = OS.get_process_id()
	_probe_report["checks"] = checks
	_probe_report["failures"] = failures
	_probe_report["coverage"] = "Propriedades RefCounted diretas e sinais de donos selecionados; tokens C++ não expõem script/ID via ResourceLoader. Paths observados cobrem candidatos, não inventário global ObjectDB. IDs são strings para preservar uint64."
	var folder: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): folder = arg.trim_prefix("--evidence-dir=")
	if folder.is_empty():
		push_error("CRUSH_ATTRIBUTION requires unique evidence-dir")
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		push_error("CRUSH_ATTRIBUTION não criou diretório: %s" % error)
		return
	var output: FileAccess = FileAccess.open(folder + "/inventory.json",FileAccess.WRITE)
	if output == null:
		push_error("CRUSH_ATTRIBUTION não gravou inventário: %s" % FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(_probe_report,"\t")+"\n")
	output.close()
