extends Node
## Three authored shipments share the existing quay trucks and crane cargo.
## Acceptance, handback and the economy receipt are separate explicit actions.
const FLEET := preload("res://runtime/FleetState.gd")
const PAYMENT := 300
const AVAILABLE := 0
const DELIVERED := 1
const LOST := 2
const PREFIX := "south_port_freight_accept_"

var session
var cargo
var security
var jobs: Array = [AVAILABLE, AVAILABLE, AVAILABLE]
var active_bay := -1
var pending_truck: Dictionary = {}
var previous_vehicle: Dictionary = {}
var _previous_ref: WeakRef
var _return_pending := false
var _clock := 0.0

func configure(owner_session, operations, checkpoint) -> void:
	session = owner_session
	cargo = operations
	security = checkpoint
	name = "SouthPortFreight"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	cargo.freight = self
	cargo.work_truck_removed.connect(_truck_removed)

func bay_available(index: int) -> bool:
	return index >= 0 and index < jobs.size() and jobs[index] == AVAILABLE and active_bay != index

func _available() -> bool:
	return session.ready_for_play and not session.modal and session.state.region_id == "harbor" \
		and session.state.place_id.is_empty() and session.world.gameplay.health > 0 \
		and session.world.gameplay.stars == 0 and not session.world.driving.is_body_transition_active()

func _reachable(vehicle: CharacterBody3D) -> bool:
	if not is_instance_valid(vehicle) or vehicle.health <= 0 or vehicle.is_queued_for_deletion(): return false
	if not vehicle.is_visible_in_tree() or vehicle.has_meta("awaiting_ground") or absf(vehicle.speed) > .25: return false
	if vehicle.global_position.distance_squared_to(session.world.player.global_position) > 36.0: return false
	# Use the same door and obstruction check as boarding, so an offer cannot
	# appear across a wall, on the other side of a truck or without floor.
	var option: Dictionary = session.world.driving._entry_option(true)
	return option.get("car") == vehicle and vehicle.is_on_floor()

func nearest_action() -> Dictionary:
	if not _available() or session.world.driving.occupied: return {}
	if active_bay >= 0:
		if not pending_truck.is_empty(): return {}
		var vehicle = cargo.work_trucks[active_bay].truck
		if _can_deliver(vehicle):
			return {"id":"urban_v1", "target":"south_port_freight_deliver", "label":"Entregar carga · R$ 300", "position":vehicle.global_position}
		return {}
	if not security.authorized_visit or not cargo._shift_open() or not session.state.campaign.active_id.is_empty(): return {}
	if session.state.intro.stage != "complete" or session.state.equipped_weapon not in ["", "fists"]: return {}
	for index in cargo.work_trucks.size():
		var entry: Dictionary = cargo.work_trucks[index]
		if not bay_available(index) or entry.phase != "securing" or not entry.loaded: continue
		var vehicle = entry.truck
		if not _reachable(vehicle) or vehicle.controlled: continue
		if vehicle.vehicle_id != _vehicle_id(index) or vehicle.has_meta("mission_vehicle") or vehicle.has_meta("dispatch_unit"): continue
		return {"id":"urban_v1", "target":PREFIX + str(index), "label":"Assumir frete · R$ 300", "position":vehicle.global_position}
	return {}

func perform(target: String) -> bool:
	var action := nearest_action()
	if action.is_empty() or action.target != target: return false
	if target == "south_port_freight_deliver": return _deliver()
	if not target.begins_with(PREFIX): return false
	if not session.save_game(true): return false
	session.controller.capture_player_vehicle()
	previous_vehicle = session.controller.starting_vehicle().duplicate(true)
	var previous = session.world.driving.car
	_previous_ref = weakref(previous) if is_instance_valid(previous) and previous.vehicle_id == previous_vehicle.get("vehicle_id", "") else null
	_watch_previous(previous)
	active_bay = target.trim_prefix(PREFIX).to_int()
	var entry: Dictionary = cargo.work_trucks[active_bay]
	var vehicle = entry.truck
	entry.phase = "freight"
	vehicle.traffic = false
	vehicle.brake_input = true
	vehicle.set_meta("port_freight_claim", active_bay)
	# This is an authorized handover of a stopped, intact work vehicle.
	vehicle.remove_meta("crash_was_traffic")
	session.save_game()
	session.show_message("Frete aceito. Leve a carga ao depósito e devolva o caminhão.")
	return true

func depot_position(index: int) -> Vector3:
	if cargo.has_method("start_journey"): return preload("res://gameplay/urban_v1/PortHaulRoutes.gd").dock(index)
	return cargo.truck_route.sample_baked(float(cargo.work_trucks[index].depot_offset), true)

func freight_status() -> Dictionary:
	if active_bay < 0: return {"active":false}
	var vehicle = cargo.work_trucks[active_bay].truck
	var depot := depot_position(active_bay)
	if not is_instance_valid(vehicle): return {"active":true, "objective":"Retome o frete no cais.", "target":depot}
	var driving: bool = session.world.driving.occupied and session.world.driving.car == vehicle
	var at_depot: bool = vehicle.global_position.distance_to(depot) <= 6.0
	var objective := "Leve a carga ao depósito · R$ 300" if driving else "Entre no caminhão do frete"
	if at_depot: objective = "Estacione e desembarque para entregar" if driving else "Entregue a carga junto ao caminhão · R$ 300"
	return {"active":true, "objective":objective, "target":depot if driving else vehicle.global_position}

func _can_deliver(vehicle) -> bool:
	if cargo.has_method("start_journey") and not cargo.depot.business_open(): return false
	# An accepted shipment remains authorized after leaving the port perimeter.
	# The new destination is outside that perimeter; its visit flag is revoked
	# normally by security when the player drives out of the checkpoint.
	if not _reachable(vehicle) or vehicle.controlled or active_bay < 0: return false
	if vehicle.vehicle_id != _vehicle_id(active_bay) or not cargo.work_trucks[active_bay].loaded: return false
	var visual = cargo.cranes[active_bay].visual
	if not is_instance_valid(visual) or visual.get_parent() != vehicle: return false
	return vehicle.global_position.distance_to(depot_position(active_bay)) <= 6.0

func _deliver() -> bool:
	var index := active_bay
	var entry: Dictionary = cargo.work_trucks[index]
	var vehicle = entry.truck
	var receipt: Dictionary = session.state.economy.grant_world_reward({"id":_receipt_id(index), "kind":"cash", "amount":PAYMENT})
	if not receipt.ok:
		session.show_message("Não foi possível receber o frete. Tente novamente.")
		return false
	jobs[index] = DELIVERED
	active_bay = -1
	vehicle.remove_meta("port_freight_claim")
	cargo._reset_truck_load(index)
	entry.phase = "approach"
	entry.deliveries = int(entry.deliveries) + 1
	vehicle.route = cargo.truck_route
	vehicle.route_distance = cargo.truck_route.get_closest_offset(vehicle.global_position)
	vehicle.traffic = cargo.active and cargo._shift_open()
	vehicle.brake_input = not vehicle.traffic
	if cargo.has_method("start_journey"):
		entry.phase = "return_wait"
		entry.remaining = 0.0
		vehicle.traffic = false
		vehicle.brake_input = true
		cargo.start_journey(index,true)
	# Handback also releases the player's saved selection. Otherwise the generic
	# fleet restore and the port NPC spawner would create the same truck twice.
	if session.world.driving.car == vehicle: session.world.driving.car = null
	var saved: Array = session.state.world_state.get("vehicles", [])
	session.state.world_state.vehicles = saved.filter(func(record): return record.get("vehicle_id", "") != _vehicle_id(index))
	_restore_previous_selection()
	session.save_game()
	session.show_message("Carga entregue · +R$ 300" if receipt.changed else "Carga já entregue.")
	return true

func _process(delta: float) -> void:
	if _return_pending and session.ready_for_play:
		for index in jobs.size():
			if jobs[index] != AVAILABLE: _release_retired_selection(index)
		_restore_previous_selection()
	if active_bay < 0: return
	_clock -= delta
	if _clock > 0.0: return
	_clock = .25
	if not session.ready_for_play: return
	if not pending_truck.is_empty():
		_restore_truck()
		return
	var vehicle = cargo.work_trucks[active_bay].truck
	if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion() or vehicle.health <= 0:
		_truck_removed(active_bay)

func _truck_removed(index: int) -> void:
	if index != active_bay: return
	jobs[index] = LOST
	active_bay = -1
	pending_truck.clear()
	_return_pending = false
	if not is_inside_tree() or session.world.is_queued_for_deletion() or not session.ready_for_play: return
	# Driving retires its selected FleetState during the same tree_exiting
	# signal. Save after those listeners, never an alive copy of a queued body.
	_save_after_removal.call_deferred(index)
	session.show_message("Frete perdido. Caminhão destruído ou removido.")

func _save_after_removal(index: int) -> void:
	if is_inside_tree() and not session.world.is_queued_for_deletion():
		_release_retired_selection(index)
		_restore_previous_selection()
		session.save_game()

func _release_retired_selection(index: int) -> void:
	var selected = session.world.driving.car
	if is_instance_valid(selected) and selected.vehicle_id == _vehicle_id(index) and not session.world.driving.occupied:
		session.world.driving.car = null
	var saved: Array = session.state.world_state.get("vehicles", [])
	session.state.world_state.vehicles = saved.filter(func(record): return record.get("vehicle_id", "") != _vehicle_id(index))

func _refresh_previous() -> void:
	if _previous_ref == null: return # A previous parked car need not be materialized after loading.
	var vehicle = _previous_ref.get_ref()
	if is_instance_valid(vehicle) and vehicle.is_queued_for_deletion() and vehicle.get_meta("distance_despawn", false):
		_previous_exiting(vehicle)
		return
	if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		previous_vehicle.clear()
		_previous_ref = null
		return
	_capture_supported_previous(vehicle)

func _capture_supported_previous(vehicle: CharacterBody3D) -> void:
	var current := FLEET.capture(vehicle, str(previous_vehicle.get("region", "harbor")))
	var point := vehicle.global_position
	var ground := PhysicsRayQueryParameters3D.create(point + Vector3.UP*.12, point - Vector3.UP*.3, 1)
	var support: Dictionary = vehicle.get_world_3d().direct_space_state.intersect_ray(ground) if vehicle.is_inside_tree() else {}
	# Residency can drop the old floor a few frames before distance cleanup.
	# Keep the last supported transform, while preserving current damage/equipment.
	if not previous_vehicle.is_empty() and (support.is_empty() or absf(float(support.position.y) - point.y) > .15):
		current.position = previous_vehicle.position.duplicate()
		current.yaw = previous_vehicle.yaw
	current.was_driven = false
	previous_vehicle = current

func _watch_previous(vehicle) -> void:
	if _previous_ref == null or not is_instance_valid(vehicle): return
	var callback := _previous_exiting.bind(vehicle)
	if not vehicle.tree_exiting.is_connected(callback): vehicle.tree_exiting.connect(callback)

func _previous_exiting(vehicle: CharacterBody3D) -> void:
	if _previous_ref == null or _previous_ref.get_ref() != vehicle: return
	if vehicle.get_meta("distance_despawn", false):
		# Streaming a parked car is not destroying it. Retain its last state,
		# without leaving physics running on a distant, unloaded floor.
		_capture_supported_previous(vehicle)
		_previous_ref = null
	elif vehicle.is_queued_for_deletion() and not session.world.is_queued_for_deletion():
		previous_vehicle.clear()
		_previous_ref = null

func _restore_previous_selection() -> void:
	_return_pending = false
	_refresh_previous()
	if previous_vehicle.is_empty(): return
	var selected = session.world.driving.car
	var saved: Array = session.state.world_state.get("vehicles", [])
	# A different car chosen during the delivery belongs to the player too.
	# Returning a loan must never roll that new selection back.
	var different_selection: bool = is_instance_valid(selected) and selected.vehicle_id != previous_vehicle.get("vehicle_id", "")
	var different_save: bool = saved.any(func(record): return record.get("vehicle_id", "") != previous_vehicle.get("vehicle_id", ""))
	if not different_selection and not different_save:
		session.state.world_state.vehicles = [previous_vehicle.duplicate(true)]
		var previous = _previous_ref.get_ref() if _previous_ref != null else null
		if is_instance_valid(previous):
			session.world.driving.car = previous
			session.world.driving._watch_car(previous)
	previous_vehicle.clear()
	_previous_ref = null

func snapshot() -> Dictionary:
	_refresh_previous()
	var truck := pending_truck.duplicate(true)
	if active_bay >= 0 and truck.is_empty():
		var vehicle = cargo.work_trucks[active_bay].truck
		if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and vehicle.health > 0:
			truck = FLEET.capture(vehicle, "harbor")
		else:
			_truck_removed(active_bay)
	return {"version":1, "jobs":jobs.duplicate(), "active_bay":active_bay, "truck":truck, "previous_vehicle":previous_vehicle.duplicate(true)}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	jobs = data.jobs.duplicate()
	active_bay = int(data.active_bay)
	pending_truck = data.truck.duplicate(true)
	previous_vehicle = data.get("previous_vehicle", {}).duplicate(true)
	if _previous_ref != null:
		var previous = _previous_ref.get_ref()
		if not is_instance_valid(previous) or previous.vehicle_id != previous_vehicle.get("vehicle_id", ""): _previous_ref = null
	for index in jobs.size():
		if _paid(index): jobs[index] = DELIVERED
	if active_bay >= 0:
		# A receipt is authoritative if an old world marker is replayed after
		# payment. Reconciliation must never pay again or respawn that cargo.
		if _paid(active_bay):
			jobs[active_bay] = DELIVERED
			active_bay = -1
			pending_truck.clear()
		else:
			cargo.work_trucks[active_bay].phase = "freight_pending"
	_return_pending = active_bay < 0 and not previous_vehicle.is_empty()
	return true

func _restore_truck() -> void:
	var vehicle: CharacterBody3D
	var candidates: Array = session.controller.vehicles.duplicate()
	if is_instance_valid(session.world.driving.car): candidates.append(session.world.driving.car)
	for candidate in candidates:
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.vehicle_id == _vehicle_id(active_bay):
			vehicle = candidate
			break
	var restored_new := false
	if not is_instance_valid(vehicle):
		var p: Array = pending_truck.position
		vehicle = session.controller.spawn_vehicle("cargo_flatbed_truck", Vector3(p[0],p[1],p[2]), float(pending_truck.yaw))
		if not is_instance_valid(vehicle): return # Streamed floor/clearance is retried; never teleport through solids.
		restored_new = true
	if vehicle.archetype != "cargo_flatbed_truck" or vehicle.health <= 0:
		_truck_removed(active_bay)
		return
	vehicle.vehicle_id = _vehicle_id(active_bay)
	vehicle.set_meta("port_work_vehicle", true)
	vehicle.set_meta("port_freight_claim", active_bay)
	vehicle.set_meta("region_id", "harbor")
	vehicle.traffic = false
	if restored_new:
		vehicle.paint_color = Color(str(pending_truck.get("paint", "31577a")))
		vehicle.health = float(pending_truck.health)
		vehicle.equipment_state = pending_truck.get("equipment", {}).duplicate(true)
		if not pending_truck.get("equipment", {}).is_empty() and is_instance_valid(vehicle.equipment): vehicle.equipment.restore_state(pending_truck.equipment)
	var entry: Dictionary = cargo.work_trucks[active_bay]
	entry.truck = vehicle
	cargo._watch_work_truck(active_bay, vehicle)
	cargo._finish_truck_load(active_bay)
	entry.phase = "freight"
	pending_truck.clear()

func _paid(index: int) -> bool:
	var record: Dictionary = session.state.economy.snapshot().transactions.get("reward:" + _receipt_id(index), {})
	return record.get("kind") == "reward" and record.get("item") == _receipt_id(index) and record.get("amount") == PAYMENT

static func _vehicle_id(index: int) -> String:
	return "south_port_cargo_truck_%02d" % index

static func _receipt_id(index: int) -> String:
	return "south_port_freight_delivery_%d" % index

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("jobs") is Array or data.jobs.size() != 3: return false
	for value in data.jobs:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)): return false
		if int(value) not in [AVAILABLE, DELIVERED, LOST]: return false
	var bay: Variant = data.get("active_bay")
	if typeof(bay) not in [TYPE_INT, TYPE_FLOAT] or float(bay) != floor(float(bay)) or bay < -1 or bay > 2: return false
	if not data.get("truck") is Dictionary: return false
	var previous: Variant = data.get("previous_vehicle", {})
	if not previous is Dictionary or (not previous.is_empty() and not FLEET.validate(previous)): return false
	if not previous.is_empty() and previous.get("vehicle_id", "").begins_with("south_port_cargo_truck_"): return false
	if bay == -1: return data.truck.is_empty()
	return data.jobs[int(bay)] == AVAILABLE and FLEET.validate(data.truck) and data.truck.health > 0 \
		and data.truck.archetype == "cargo_flatbed_truck" and data.truck.get("vehicle_id") == _vehicle_id(int(bay)) \
		and data.truck.region == "harbor"
