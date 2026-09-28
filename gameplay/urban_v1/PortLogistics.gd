extends "res://gameplay/urban_v1/PortCargoOperations.gd"
## One conserved truck per quay. Only destroyed trucks enter the 24-hour queue.
const HAUL := preload("res://gameplay/urban_v1/PortHaulRoutes.gd")
const DEPOT := preload("res://gameplay/urban_v1/VerticeCompany.gd")
var depot: Node3D
var outskirts: Node3D
var _save_queued := false
var _game_clock := -1.0
var _clock_phase := -1.0

func _ready() -> void:
	super._ready()
	depot = DEPOT.new()
	depot.session = session
	add_child(depot)
	outskirts = preload("res://gameplay/urban_v1/FreightOutskirts.gd").new()
	add_child(outskirts)
	for state in work_trucks:
		state.respawn_at = -1.0
		state.unload_origin = Vector3.ZERO
		state.ground_ready = true
	set_process(false)
	set_physics_process(true)

func game_seconds() -> float:
	# Virtual units: one complete visible day = 600, regardless of the weather
	# system's real-time day length. Sleeping advances the same visible clock;
	# the activities calendar has its own unrelated 600-second quota period.
	if session.weather == null: return maxf(0,_game_clock)
	var phase := fposmod(float(session.weather.time_of_day),1.0)
	if _game_clock<0:
		var data: Dictionary = session.activities._data
		_game_clock = float(data.day)*600.0+float(data.day_clock)
	if _clock_phase>=0: _game_clock += fposmod(phase-_clock_phase,1.0)*600.0
	_clock_phase = phase
	return _game_clock

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or not is_instance_valid(session.world.player): return
	scan_clock -= delta
	if scan_clock <= 0:
		scan_clock = .25
		refresh_context()
		_work_shift_open = _shift_open()
		_tick_replacements()
		if active: _ensure_work_vehicles()
		elif session.state.region_id == "harbor" and session.state.place_id.is_empty() and _work_shift_open:
			# A visitor going straight to the company must still see its fleet.
			# Budget one spawn per scan, on prepared native port ground.
			for i in work_trucks.size():
				var state: Dictionary = work_trucks[i]
				if is_instance_valid(state.truck) or state.phase != "approach" or state.respawn_at>=0: continue
				var offset := fposmod(float(state.stop_offset)-TRUCK_START_GAP,truck_route.get_baked_length())
				var point := truck_route.sample_baked(offset,true)
				var region = session.controller.regions.get("harbor")
				if is_instance_valid(region) and region.prepare_collision_at(point): _spawn_work_truck(i)
				break
		_sync_work_vehicle_visibility()
		var harbor: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
		depot.set_region_active(harbor)
		outskirts.visible = harbor
		outskirts._trunks.collision_layer = 1 if harbor else 0
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return
	for index in work_trucks.size():
		var state: Dictionary = work_trucks[index]
		var vehicle = state.truck
		if is_instance_valid(vehicle) and vehicle.health <= 0 and state.respawn_at < 0: _work_truck_destroyed(index)
		if state.phase in ["destroyed","freight","freight_pending","interrupted"]: continue
		if not _work_shift_open and state.phase not in ["departed","delivering","returning","return_wait"]:
			# Parked off-screen trucks relinquish streamed support overnight.
			# Preparing their chunks here would rebuild what streaming just freed.
			state.ground_ready = false
			continue
		if is_instance_valid(vehicle):
			state.ground_ready = _ground_ready(vehicle)
			if not state.ground_ready:
				vehicle.set_physics_process(false)
				continue
		if _work_shift_open or state.phase in ["departed","delivering","returning","return_wait"]:
			_tick_truck(index,delta)
		if _work_shift_open and not state.loaded: _tick_crane(index,delta)

func _sync_work_vehicle_visibility() -> void:
	for forklift in forklifts:
		if not is_instance_valid(forklift) or forklift.controlled: continue
		forklift.visible = active
		forklift.set_physics_process(active)
	for state in work_trucks:
		var vehicle = state.truck
		if not is_instance_valid(vehicle) or state.phase in ["freight","freight_pending","interrupted"] or vehicle.controlled: continue
		var resident: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
		vehicle.visible = resident
		if state.phase == "destroyed":
			vehicle.set_physics_process(resident and not vehicle.has_meta("awaiting_ground"))
			continue
		var running: bool = resident and (_work_shift_open or state.phase in ["departed","delivering","returning","return_wait"])
		vehicle.set_physics_process(running and state.get("ground_ready",true) and not vehicle.has_meta("awaiting_ground"))
		vehicle.traffic = running and state.phase in ["approach","departed","returning"]
		vehicle.brake_input = not vehicle.traffic

func _ground_ready(truck: CharacterBody3D) -> bool:
	var region = session.controller.regions.get("harbor")
	if not is_instance_valid(region): return false
	# Prepare real streamed collision under both ends before moving beyond a
	# chunk boundary. A carrier cannot outrun residency or fall onto no floor.
	var ahead: Vector3 = truck.global_position-truck.global_basis.z*(truck.half_length+3)
	if not region.prepare_collision_at(truck.global_position) or not region.prepare_collision_at(ahead): return false
	var query := PhysicsRayQueryParameters3D.create(truck.global_position+Vector3.UP*.2,truck.global_position-Vector3.UP*.5,1)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _spawn_work_truck(index: int) -> void:
	if float(work_trucks[index].get("respawn_at",-1)) >= 0: return
	# Generic fleet restoration can already own a stolen/borrowed work truck.
	for existing in session.controller.vehicles:
		if is_instance_valid(existing) and existing.vehicle_id == "south_port_cargo_truck_%02d"%index:
			work_trucks[index].truck = existing
			work_trucks[index].phase = "interrupted"
			_watch_work_truck(index,existing)
			return
	super._spawn_work_truck(index)
	var truck = work_trucks[index].truck
	if is_instance_valid(truck):
		truck.add_to_group("port_logistics_truck")
		cranes[index].visual.visible = active

func _finish_truck_load(index: int) -> void:
	super._finish_truck_load(index)
	cranes[index].visual.show()
	var truck = work_trucks[index].truck
	if not is_instance_valid(truck): return
	# The load reaches above the empty cab's hull. Raise its physical envelope
	# and rotation probe while loaded; do not let it pass through low beams.
	if not truck.has_meta("empty_cargo_hull"):
		truck.set_meta("empty_cargo_hull",truck.shape.shape.size)
	var size: Vector3 = truck.get_meta("empty_cargo_hull")
	size.y = maxf(size.y,3.6)
	truck.shape.shape.size = size
	truck.shape.position.y = size.y*.5
	truck.rotation_shape.size = size-Vector3(0,.15,0)
	truck.body_height = size.y

func _reset_truck_load(index: int) -> void:
	super._reset_truck_load(index)
	var truck = work_trucks[index].truck
	if is_instance_valid(truck) and truck.has_meta("empty_cargo_hull"):
		var size: Vector3 = truck.get_meta("empty_cargo_hull")
		truck.shape.shape.size = size
		truck.shape.position.y = size.y*.5
		truck.rotation_shape.size = size-Vector3(0,.15,0)
		truck.body_height = size.y

func _sync_crane(index: int) -> void:
	super._sync_crane(index)
	# A suspended load uses the landing-clearance query. Enabling its old
	# ground-only static box during the last lowering frame overlaps the truck
	# hull and collision recovery can push the carrier through the quay floor.
	if work_trucks[index].phase == "loading" or work_trucks[index].loaded:
		cranes[index].collision.set_deferred("disabled",true)

func start_journey(index: int, returning: bool) -> bool:
	var state: Dictionary = work_trucks[index]
	var truck = state.truck
	var route: Curve3D = HAUL.journey(session.controller.traffic_routes,truck.global_position,index,returning)
	if route == null: return false
	truck._release_junction()
	truck.route = route
	truck.route_distance = 0
	truck.traffic = true
	truck.brake_input = false
	state.phase = "returning" if returning else "departed"
	return true

func _tick_truck(index: int, delta: float) -> void:
	var state: Dictionary = work_trucks[index]
	var truck = state.truck
	if not is_instance_valid(truck) or state.phase in ["freight","freight_pending","destroyed"]: return
	if truck.controlled or (session.world.driving.occupied and session.world.driving.car == truck):
		state.phase = "interrupted"
		return
	if state.phase in ["departed","returning"]: _yield_crossing_vehicle(state,truck,delta)
	match str(state.phase):
		"securing":
			state.remaining = maxf(0,state.remaining-delta)
			if state.remaining <= 0 and not start_journey(index,false): state.remaining = 3.0
		"departed", "returning":
			if truck.route == null: return
			var end: Vector3 = truck.route.get_point_position(truck.route.point_count-1)
			var distance := Vector2(end.x-truck.global_position.x,end.z-truck.global_position.z).length()
			if distance > 1.5 or absf(truck.speed) > .3: return
			truck.traffic = false
			truck.brake_input = true
			if state.phase == "returning":
				state.phase = "waiting"
				cranes[index].clock = 0.0
			else:
				state.phase = "delivering"
				state.remaining = 12.0
				state.unload_origin = cranes[index].visual.global_position
				cranes[index].visual.reparent(self,true)
		"delivering":
			if not depot.business_open(): return
			if absf(truck.speed) > .25: return
			var fraction := 1-float(state.remaining)/12.0
			# Keep the complete drop zone free; never lower a container onto an actor.
			if fraction > .7 and _cargo_bay_occupied(HAUL.dock(index)+Vector3(0,.18,-5.5),[truck.get_rid()]): return
			state.remaining = maxf(0,state.remaining-delta)
			depot.unload_pose(index,cranes[index].visual,state.unload_origin,1-state.remaining/12.0)
			if state.remaining <= 0:
				_reset_truck_load(index)
				state.deliveries += 1
				state.phase = "return_wait"
		"return_wait":
			state.remaining -= delta
			if state.remaining <= 0 and not start_journey(index,true): state.remaining = 3.0
		_:
			super._tick_truck(index,delta)

func _yield_crossing_vehicle(state: Dictionary,truck,delta: float) -> void:
	# An eight-metre carrier can meet a turning van nose-to-side. The generic
	# traffic recovery handles head-on pairs; give this longer vehicle room to
	# yield physically as well, only when its complete rear corridor is clear.
	state.yield_wait = maxf(0,float(state.get("yield_wait",0))-delta)
	var other = truck.blocker
	if state.yield_wait>0 or truck.junction_wait or truck.stall_time<12 or absf(truck.speed)>.2: return
	if not is_instance_valid(other) or not other is CharacterBody3D or other.get("traffic")!=true: return
	if (-truck.global_basis.z).dot(-other.global_basis.z)>.7: return
	var query := PhysicsShapeQueryParameters3D.new()
	var volume := BoxShape3D.new()
	volume.size = truck.shape.shape.size-Vector3(.05,.12,.05)
	query.shape = volume
	query.collision_mask = 7
	query.exclude = [truck.get_rid()]
	for distance in [1.0,2.0,3.0]:
		query.transform = truck.global_transform*truck.shape.transform
		query.transform.origin += truck.global_basis.z*distance+Vector3.UP*.07
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			state.yield_wait = 3.0
			return
	truck.backoff_time = 1.7
	state.yield_wait = 12.0

func _work_truck_destroyed(index: int) -> void:
	var state: Dictionary = work_trucks[index]
	if float(state.get("respawn_at",-1)) >= 0: return
	# Preserve the shared crane cargo before the wreck's subtree can be removed.
	if is_instance_valid(cranes[index].visual):
		cranes[index].visual.hide()
		if cranes[index].visual.get_parent() != self:
			# tree_exiting can arrive after the cargo child has left the tree.
			# Hidden cargo needs no world transform until the next crane reset.
			cranes[index].visual.reparent(self,cranes[index].visual.is_inside_tree())
	state.loaded = false
	state.respawn_at = game_seconds()+600.0
	state.phase = "destroyed"
	if is_instance_valid(state.truck):
		state.truck.traffic = false
		state.truck.remove_meta("port_container_loaded")
	work_truck_removed.emit(index)
	if not _save_queued:
		_save_queued = true
		_persist_cooldown.call_deferred()

func _persist_cooldown() -> void:
	_save_queued = false
	if is_inside_tree() and session != null and session.ready_for_play and not session.world.is_queued_for_deletion(): session.save_game()

func _work_truck_exiting(index: int, reference: WeakRef) -> void:
	if reference.get_ref() != work_trucks[index].truck: return
	super._work_truck_exiting(index,reference)

func _tick_replacements() -> void:
	for i in work_trucks.size():
		var state: Dictionary = work_trucks[i]
		if state.respawn_at < 0 or game_seconds() < state.respawn_at: continue
		var wreck = state.truck
		if is_instance_valid(wreck):
			if wreck.controlled or (session.world.driving.occupied and session.world.driving.car == wreck): continue
			var callback := _work_truck_destroyed.bind(i)
			if wreck.destroyed.is_connected(callback): wreck.destroyed.disconnect(callback)
			wreck.vehicle_id += "_wreck_"+str(wreck.get_instance_id())
			wreck.remove_meta("port_work_vehicle")
		state.truck = null
		state.respawn_at = -1.0
		state.phase = "approach"
		state.remaining = 0.0
		cranes[i].clock = 0.0

func snapshot() -> Dictionary:
	var entries: Array = []
	for state in work_trucks: entries.append({"respawn_at":state.respawn_at,"deliveries":state.deliveries})
	return {"version":1,"trucks":entries,"clock":game_seconds(),"clock_phase":_clock_phase}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	if data.has("clock"):
		_game_clock = float(data.clock)
		_clock_phase = float(data.clock_phase)
	for i in 3:
		work_trucks[i].respawn_at = float(data.trucks[i].respawn_at)
		work_trucks[i].deliveries = int(data.trucks[i].deliveries)
		if work_trucks[i].respawn_at >= 0: work_trucks[i].phase = "destroyed"
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("trucks") is Array or data.trucks.size() != 3: return false
	if data.has("clock") or data.has("clock_phase"):
		for key in ["clock","clock_phase"]:
			if typeof(data.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])): return false
		if data.clock<0 or data.clock_phase<0 or data.clock_phase>=1: return false
	for entry in data.trucks:
		if not entry is Dictionary: return false
		for key in ["respawn_at","deliveries"]:
			if typeof(entry.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(entry[key])): return false
		if entry.respawn_at < -1 or entry.deliveries < 0 or entry.deliveries != floorf(entry.deliveries): return false
	return true
