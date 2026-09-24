extends Node
## One world, one Player, one camera. Regions are prepared ahead of travel;
## their simulation/rendering sleeps outside the active neighbourhood.
const MOUNTAIN_SCENE := "res://world/mountain_pass/MountainPass.tscn"
const MOUNTAIN_OFFSET := Vector2(4300, -4960)
const SEAM_X := 7300.0
const MOUNTAIN_SEAM_POSITION := Vector2(SEAM_X, -4560.0)
# Region construction is expensive even though every producer remains staged.
# Start from physical approach, not from a broad north-Harbor Y coordinate.
const MOUNTAIN_DIRECT_PRELOAD_DISTANCE := 4200.0
const MOUNTAIN_LOOKAHEAD_SECONDS := 6.0
const MOUNTAIN_MAX_LOOKAHEAD_DISTANCE := 2600.0
const MOUNTAIN_MIN_APPROACH_SPEED := 35.0
const POPULATION_CATALOG_RECONCILE_TICKS := 300
const POPULATION_ZONE_SYNC_BATCH := 128
const POPULATION_CAR_GROUP := &"modern_traffic"
const POPULATION_WALKER_GROUP := &"pedestrian"
const POPULATION_AUTHORED_WALKER_GROUP := &"authored_sidewalk_pedestrian"
const POPULATION_REGION_GROUP := &"population_region"
var mountain: Node2D
var building := false
var ready_for_crossing := false
var current_region := "harbor"
var _elapsed := 0.0
var _population_catalog_ticks := 0
var _population_cars: Array[Node] = []
var _population_car_ids: Array[int] = []
var _population_car_indices: Dictionary = {}
var _population_walkers: Array[Node] = []
var _population_walker_ids: Array[int] = []
var _population_walker_indices: Dictionary = {}
var _population_regions: Array[Node] = []
var _population_region_ids: Array[int] = []
var _population_region_indices: Dictionary = {}
var _pending_population_nodes: Dictionary = {}
var _pending_population_departures: Dictionary = {}
var _population_events_scheduled := false
var _population_catalog_started := false
var _population_zone_sync_cursor := 0
var _mountain_load_trigger: Dictionary = {}
var _mountain_load_gate: Dictionary = {}
var _population_catalog_stats := {
	"full_reconciliations": 0,
	"group_queries": 0,
	"incremental_additions": 0,
	"incremental_removals": 0,
	"last_reconcile_usec": 0,
	"max_reconcile_usec": 0,
}
var population_activity := preload("res://systems/PopulationActivity.gd").new()
var population_zones := preload("res://systems/PopulationZoneManager.gd").new()
var _mountain_layers: Array[CanvasLayer] = []
var _mountain_layer_visibility: Dictionary = {}
var _mountain_layers_selected := false
var handoff_max_displacement := 0.0
var vehicle_prewarm_coordinator

func _ready() -> void:
	add_to_group("continuous_world")
	vehicle_prewarm_coordinator = preload("res://cars/VehicleRegionalPrewarmCoordinator.gd").new()
	vehicle_prewarm_coordinator.name = "VehicleRegionalPrewarm"
	vehicle_prewarm_coordinator.seam_position = MOUNTAIN_SEAM_POSITION
	add_child(vehicle_prewarm_coordinator)
	_start_population_catalog()

func ensure_mountain() -> void:
	if building or ready_for_crossing: return
	building = true
	ResourceLoader.load_threaded_request(MOUNTAIN_SCENE)
	while ResourceLoader.load_threaded_get_status(MOUNTAIN_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var resource := ResourceLoader.load_threaded_get(MOUNTAIN_SCENE) as PackedScene
	if resource == null:
		building = false
		push_error("Could not prepare Mountain Pass")
		return
	mountain = resource.instantiate()
	mountain.name = "MountainRegion"
	mountain.position = MOUNTAIN_OFFSET
	mountain.streamed_region = true
	mountain.region_selected = false
	mountain.connect_to_harbor = false
	mountain.spawn_player_on_ready = false
	mountain.spawn_suv_on_ready = false
	mountain.player_instance = get_tree().get_first_node_in_group("player")
	# Region construction owns independent SubViewports and render resources.
	# Keep its CanvasItems out of the live Harbor render pass until the staged
	# build has completed and proximity selection explicitly enables it.
	mountain.visible = false
	get_parent().add_child(mountain)
	while not mountain.region_ready:
		await get_tree().process_frame
	for node in mountain.find_children("*", "CanvasLayer", true, false):
		_mountain_layers.append(node)
		_mountain_layer_visibility[node] = node.visible
		node.hide()
	ready_for_crossing = true
	for lane in get_tree().get_nodes_in_group("unified_traffic_lane"):
		var road_id := String(lane.get_meta("traffic_road_id", ""))
		if road_id.ends_with("mountain_bridge_outbound"): lane.set_meta("continuous_border_end", true)
		if road_id.ends_with("mountain_bridge_inbound"): lane.set_meta("continuous_border_start", true)
	building = false
	_update_region()
	get_node("/root/RegionTravel").finish_arrival(get_parent())

func exterior_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return Vector2.ZERO
	var car: Node2D = get_node("/root/RegionTravel").controlled_car()
	if car != null and not player.has_meta("police_exterior_position"): return car.global_position
	return player.get_meta("police_exterior_position", player.global_position)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	var point := exterior_position()
	var pending: Dictionary = get_node("/root/RegionTravel").pending_world
	_mountain_load_gate = mountain_load_decision(
		point,
		exterior_velocity(),
		String(pending.get("region", ""))
	)
	if not ready_for_crossing and not building and bool(_mountain_load_gate.get("should_load", false)):
		_mountain_load_trigger = _mountain_load_gate.duplicate(true)
		_mountain_load_trigger["process_frame"] = Engine.get_process_frames()
		_mountain_load_trigger["time_msec"] = Time.get_ticks_msec()
		ensure_mountain()
	_budget_traffic(point)
	if not ready_for_crossing: return
	_update_region()
	_transfer_bridge_traffic()


func exterior_velocity() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return Vector2.ZERO
	var actor: Node2D = player
	var car: Node2D = get_node("/root/RegionTravel").controlled_car()
	if car != null and not player.has_meta("police_exterior_position"):
		actor = car
	if actor is CharacterBody2D:
		return (actor as CharacterBody2D).velocity
	if actor is RigidBody2D:
		return (actor as RigidBody2D).linear_velocity
	return Vector2.ZERO


func mountain_load_decision(point: Vector2, velocity: Vector2, pending_region := "") -> Dictionary:
	var requested := pending_region == "mountain"
	if not point.is_finite():
		return {
			"should_load": requested,
			"reason": "pending_region" if requested else "invalid_position",
			"point": point,
			"pending_region": pending_region,
		}
	if not velocity.is_finite():
		velocity = Vector2.ZERO
	var toward := MOUNTAIN_SEAM_POSITION - point
	var distance := toward.length()
	var approach_speed := velocity.dot(toward / distance) if distance > 0.001 else velocity.length()
	var lookahead_distance := 0.0
	if approach_speed >= MOUNTAIN_MIN_APPROACH_SPEED:
		lookahead_distance = minf(
			approach_speed * MOUNTAIN_LOOKAHEAD_SECONDS,
			MOUNTAIN_MAX_LOOKAHEAD_DISTANCE
		)
	var trigger_distance := MOUNTAIN_DIRECT_PRELOAD_DISTANCE + lookahead_distance
	var proximity_trigger := distance <= trigger_distance
	var reason := "pending_region" if requested else ("physical_approach" if proximity_trigger else "outside_approach_gate")
	return {
		"should_load": requested or proximity_trigger,
		"reason": reason,
		"point": point,
		"velocity": velocity,
		"pending_region": pending_region,
		"seam_position": MOUNTAIN_SEAM_POSITION,
		"distance": distance,
		"approach_speed": approach_speed,
		"lookahead_distance": lookahead_distance,
		"trigger_distance": trigger_distance,
		"estimated_lead_seconds": distance / approach_speed if approach_speed > 0.001 else INF,
	}

const HARBOR_EXTERIOR_TARGETS: Array[String] = [
	"District", "EastDistrict", "NorthDistrict", "SouthPort",
	"Gateway", "Waterfront", "Alleys", "CobraNeighborhood",
	"CobraTerritory", "CobraVehicles", "Cemetery", "RoadNetwork",
	"FreightRail", "RoadSafety", "Life", "Interiors", "ArrivalStop",
	"RoadLighting", "UrbanTransit", "ChopShopZone", "RestaurantLife",
	"PatrolParking", "ResidencePrototype", "Residence_westgate_garden",
	"Residence_quayside_house", "Residence_canal_north", "PayNSpray",
	"ThematicFleet", "NecoTowTruck", "Bridge"
]
var _harbor_suspended := false

func _update_harbor_suspension(harbor_nearby: bool) -> void:
	var should_suspend := not harbor_nearby
	if _harbor_suspended == should_suspend: return
	_harbor_suspended = should_suspend
	var harbor = get_parent()
	if harbor == null: return
	for node_name in HARBOR_EXTERIOR_TARGETS:
		var node = harbor.get_node_or_null(node_name)
		if node != null:
			if should_suspend:
				node.set_meta("cw_prev_vis", node.visible if node is CanvasItem else true)
				node.set_meta("cw_prev_proc", node.process_mode)
				if node is CanvasItem: node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				if node is CanvasItem:
					node.visible = bool(node.get_meta("cw_prev_vis", true))
				node.process_mode = int(node.get_meta("cw_prev_proc", Node.PROCESS_MODE_INHERIT))

	var harbor_life := harbor.get_node_or_null("Life")
	if harbor_life != null:
		var traffic_controller = harbor_life.get("traffic_controller")
		if traffic_controller != null and traffic_controller.has_method("set_simulation_suspended"):
			traffic_controller.set_simulation_suspended(should_suspend)

func _update_region() -> void:
	var point := exterior_position()
	var player: Node2D = mountain.player_instance
	var selected: bool = point.x >= SEAM_X and point.y < -2000 or bool(player.get_meta("mountain_interior", false))
	current_region = "mountain" if selected else "harbor"
	var nearby: bool = selected or point.distance_to(Vector2(SEAM_X, -4560)) < 3200
	var harbor_nearby: bool = not selected or point.distance_to(Vector2(SEAM_X, -4560)) < 3200
	_update_harbor_suspension(harbor_nearby)
	if nearby and not mountain.visible:
		# Construction happens while hidden over many frames. Drop every stale
		# transform sample before the completed region enters the render pass.
		mountain.reset_physics_interpolation()
	mountain.visible = nearby
	mountain.process_mode = Node.PROCESS_MODE_INHERIT if nearby else Node.PROCESS_MODE_DISABLED
	mountain.region_selected = selected
	mountain.cold_controller.set_process(selected)
	# The storm node is a child of the mountain region, but its particles follow
	# the shared camera in global coordinates. Keep it explicitly disabled outside
	# the selected biome and restore it when the player returns.
	mountain.storm_manager.set_region_active(selected)
	mountain.parallax.visible = selected
	# Region transitions suspend layers; each menu still owns its open/closed state.
	# Forcing every layer visible on every tick used to open both stores on arrival.
	if selected != _mountain_layers_selected:
		for layer in _mountain_layers:
			if selected:
				layer.visible = bool(_mountain_layer_visibility.get(layer, false))
			else:
				_mountain_layer_visibility[layer] = layer.visible
				layer.hide()
		_mountain_layers_selected = selected
	mountain.cold_hud.visible = selected
	var expedition := mountain.get_node("MountainExpedition")
	expedition.set_process(selected)
	expedition.set_process_unhandled_key_input(selected)
	get_parent().weather.set_interior_mode(bool(player.get_meta("mountain_interior", false)) or bool(player.get_meta("harbor_interior", false)))
	if not selected:
		var camera := get_viewport().get_camera_2d()
		if camera and camera.has_meta("mountain_zoom"): camera.remove_meta("mountain_zoom")

func _budget_traffic(point: Vector2) -> void:
	# Population budgeting is world-wide: when Harbor is sleeping, the active
	# Mountain region still needs proximity sleep/wake decisions. Only bridge
	# transfer is restricted to the seam neighborhood.
	_maintain_population_catalog()
	for region in _population_regions:
		if is_instance_valid(region) and region.has_method("reconcile_virtual_population"):
			region.reconcile_virtual_population(point, population_zones)
	_update_population_activity(point)


func _update_population_activity(point: Vector2) -> void:
	population_activity.update(get_parent(), point, _population_cars, _population_walkers)


func _start_population_catalog() -> void:
	if _population_catalog_started: return
	_population_catalog_started = true
	var tree := get_tree()
	if tree == null: return
	if not tree.node_added.is_connected(_on_population_node_added):
		tree.node_added.connect(_on_population_node_added)
	if not tree.node_removed.is_connected(_on_population_node_removed):
		tree.node_removed.connect(_on_population_node_removed)
	# One authoritative bootstrap is required because actors may have entered the
	# tree before this sibling. Afterwards node events own the hot path.
	_refresh_population_catalog()


func _maintain_population_catalog() -> void:
	_start_population_catalog()
	_population_catalog_ticks += 1
	_sync_population_zone_batch()
	if _population_catalog_ticks >= POPULATION_CATALOG_RECONCILE_TICKS:
		_refresh_population_catalog()


func _on_population_node_added(node: Node) -> void:
	if not is_instance_valid(node): return
	var actor_id := node.get_instance_id()
	# Reparenting within the same SceneTree can emit a remove/add pair. Cancelling
	# the deferred departure preserves the actor's stable population identity.
	_pending_population_departures.erase(actor_id)
	if _is_population_candidate(node):
		if node.is_node_ready():
			_classify_population_node(node)
		else:
			_queue_population_classification(node)
	elif node.get_script() != null and not node.is_node_ready():
		# Scripted actors commonly join their population group in _ready(). Listen
		# only to those candidates instead of deferring every piece of scenery.
		var callback := _queue_population_classification.bind(node)
		if not node.ready.is_connected(callback):
			node.ready.connect(callback, CONNECT_ONE_SHOT)


func _on_population_node_removed(node: Node) -> void:
	if not is_instance_valid(node): return
	var actor_id := node.get_instance_id()
	_pending_population_nodes.erase(actor_id)
	var removed := false
	removed = _catalog_remove(actor_id, _population_cars, _population_car_ids, _population_car_indices) or removed
	removed = _catalog_remove(actor_id, _population_walkers, _population_walker_ids, _population_walker_indices) or removed
	removed = _catalog_remove(actor_id, _population_regions, _population_region_ids, _population_region_indices) or removed
	if removed:
		_population_catalog_stats["incremental_removals"] = int(_population_catalog_stats["incremental_removals"]) + 1
	var population_key := String(population_zones.actor_keys.get(actor_id, ""))
	if population_key.is_empty(): return
	_pending_population_departures[actor_id] = {"node": node, "population_key": population_key}
	_schedule_population_event_flush()


func _queue_population_classification(node: Node) -> void:
	if not is_instance_valid(node): return
	_pending_population_nodes[node.get_instance_id()] = node
	_schedule_population_event_flush()


func _schedule_population_event_flush() -> void:
	if _population_events_scheduled: return
	_population_events_scheduled = true
	call_deferred("_flush_population_events")


func _flush_population_events() -> void:
	_population_events_scheduled = false
	var pending_nodes := _pending_population_nodes.values()
	_pending_population_nodes.clear()
	for node_value in pending_nodes:
		if is_instance_valid(node_value) and node_value is Node and node_value.is_inside_tree():
			_classify_population_node(node_value)
	var departures := _pending_population_departures.duplicate()
	_pending_population_departures.clear()
	for actor_id_value in departures:
		var actor_id := int(actor_id_value)
		var departure: Dictionary = departures[actor_id]
		var node_value: Variant = departure.get("node")
		if is_instance_valid(node_value) and node_value is Node and node_value.is_inside_tree():
			_classify_population_node(node_value)
			continue
		# capture_actor() removes actor_keys before queue_free(), so a virtualized
		# identity is deliberately retained. Uncaptured despawns are forgotten.
		var population_key := String(departure.get("population_key", ""))
		if not population_key.is_empty() and String(population_zones.actor_keys.get(actor_id, "")) == population_key:
			population_zones.forget(population_key)


func _is_population_candidate(node: Node) -> bool:
	return node.is_in_group(POPULATION_CAR_GROUP) \
		or node.is_in_group(POPULATION_WALKER_GROUP) \
		or node.is_in_group(POPULATION_AUTHORED_WALKER_GROUP) \
		or node.is_in_group(POPULATION_REGION_GROUP)


func _classify_population_node(node: Node, register_zone := true) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var actor_id := node.get_instance_id()
	var is_car := node is Node2D and node.is_in_group(POPULATION_CAR_GROUP)
	var is_walker := node is Node2D and (node.is_in_group(POPULATION_WALKER_GROUP) or node.is_in_group(POPULATION_AUTHORED_WALKER_GROUP))
	var is_region := node.is_in_group(POPULATION_REGION_GROUP)
	var changed := false
	if is_car:
		changed = _catalog_add(node, _population_cars, _population_car_ids, _population_car_indices) or changed
	else:
		changed = _catalog_remove(actor_id, _population_cars, _population_car_ids, _population_car_indices) or changed
	if is_walker:
		changed = _catalog_add(node, _population_walkers, _population_walker_ids, _population_walker_indices) or changed
	else:
		changed = _catalog_remove(actor_id, _population_walkers, _population_walker_ids, _population_walker_indices) or changed
	if is_region:
		changed = _catalog_add(node, _population_regions, _population_region_ids, _population_region_indices) or changed
	else:
		changed = _catalog_remove(actor_id, _population_regions, _population_region_ids, _population_region_indices) or changed
	if changed:
		_population_catalog_stats["incremental_additions"] = int(_population_catalog_stats["incremental_additions"]) + 1
	if register_zone and (is_car or is_walker):
		_register_population_actor(node as Node2D, "traffic" if is_car else "pedestrian")
	elif register_zone and population_zones.actor_keys.has(actor_id):
		population_zones.forget(String(population_zones.actor_keys[actor_id]))


func _register_population_actor(actor: Node2D, kind: String) -> String:
	var key := population_zones.register_actor(actor)
	if key.is_empty(): return key
	var data: Dictionary = population_zones.records.get(key, {})
	data["kind"] = kind
	population_zones.records[key] = data
	return key


func _catalog_add(node: Node, actors: Array[Node], actor_ids: Array[int], indices: Dictionary) -> bool:
	var actor_id := node.get_instance_id()
	if indices.has(actor_id): return false
	indices[actor_id] = actors.size()
	actors.append(node)
	actor_ids.append(actor_id)
	return true


func _catalog_remove(actor_id: int, actors: Array[Node], actor_ids: Array[int], indices: Dictionary) -> bool:
	if not indices.has(actor_id): return false
	var index := int(indices[actor_id])
	var last_index := actors.size() - 1
	if index != last_index:
		actors[index] = actors[last_index]
		actor_ids[index] = actor_ids[last_index]
		indices[actor_ids[index]] = index
	actors.pop_back()
	actor_ids.pop_back()
	indices.erase(actor_id)
	return true


func _sync_population_zone_batch() -> void:
	var total := _population_cars.size() + _population_walkers.size()
	if total <= 0:
		_population_zone_sync_cursor = 0
		return
	_population_zone_sync_cursor = posmod(_population_zone_sync_cursor, total)
	var count := mini(POPULATION_ZONE_SYNC_BATCH, total)
	for offset in count:
		var combined_index := (_population_zone_sync_cursor + offset) % total
		var actor_value: Variant = _population_cars[combined_index] if combined_index < _population_cars.size() else _population_walkers[combined_index - _population_cars.size()]
		if is_instance_valid(actor_value) and actor_value is Node2D:
			population_zones.update_actor(actor_value)
	_population_zone_sync_cursor = (_population_zone_sync_cursor + count) % total


func _refresh_population_catalog() -> void:
	var started_usec := Time.get_ticks_usec()
	_population_catalog_ticks = 0
	var expected_cars: Dictionary = {}
	var expected_walkers: Dictionary = {}
	var expected_regions: Dictionary = {}
	for actor in _population_group_nodes(POPULATION_CAR_GROUP):
		if not is_instance_valid(actor) or not actor is Node2D: continue
		expected_cars[actor.get_instance_id()] = true
		_classify_population_node(actor, false)
	for group_name in [POPULATION_WALKER_GROUP, POPULATION_AUTHORED_WALKER_GROUP]:
		for actor in _population_group_nodes(group_name):
			if not is_instance_valid(actor) or not actor is Node2D: continue
			expected_walkers[actor.get_instance_id()] = true
			_classify_population_node(actor, false)
	for region in _population_group_nodes(POPULATION_REGION_GROUP):
		if not is_instance_valid(region): continue
		expected_regions[region.get_instance_id()] = true
		_classify_population_node(region, false)
	_remove_catalog_entries_missing_from(expected_cars, _population_cars, _population_car_ids, _population_car_indices)
	_remove_catalog_entries_missing_from(expected_walkers, _population_walkers, _population_walker_ids, _population_walker_indices)
	_remove_catalog_entries_missing_from(expected_regions, _population_regions, _population_region_ids, _population_region_indices)
	var present_population_keys: Dictionary = {}
	for actor in _population_cars:
		if is_instance_valid(actor) and actor is Node2D:
			present_population_keys[_register_population_actor(actor, "traffic")] = true
	for actor in _population_walkers:
		if is_instance_valid(actor) and actor is Node2D:
			var key := String(actor.get_meta("population_key", ""))
			if key.is_empty() or not present_population_keys.has(key):
				key = _register_population_actor(actor, "pedestrian")
			present_population_keys[key] = true
	present_population_keys.erase("")
	population_zones.prune_missing_materialized(present_population_keys)
	for actor_id_value in population_zones.actor_keys.keys():
		var actor_id := int(actor_id_value)
		if not _population_car_indices.has(actor_id) and not _population_walker_indices.has(actor_id):
			population_zones.actor_keys.erase(actor_id)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	_population_catalog_stats["full_reconciliations"] = int(_population_catalog_stats["full_reconciliations"]) + 1
	_population_catalog_stats["last_reconcile_usec"] = elapsed_usec
	_population_catalog_stats["max_reconcile_usec"] = maxi(int(_population_catalog_stats["max_reconcile_usec"]), elapsed_usec)


func _population_group_nodes(group_name: StringName) -> Array[Node]:
	_population_catalog_stats["group_queries"] = int(_population_catalog_stats["group_queries"]) + 1
	return get_tree().get_nodes_in_group(group_name)


func _remove_catalog_entries_missing_from(expected: Dictionary, actors: Array[Node], actor_ids: Array[int], indices: Dictionary) -> void:
	for index in range(actor_ids.size() - 1, -1, -1):
		var actor_id := actor_ids[index]
		if not expected.has(actor_id):
			_catalog_remove(actor_id, actors, actor_ids, indices)


func get_population_catalog_stats() -> Dictionary:
	var result := _population_catalog_stats.duplicate(true)
	result["cars"] = _population_cars.size()
	result["walkers"] = _population_walkers.size()
	result["regions"] = _population_regions.size()
	result["pending_nodes"] = _pending_population_nodes.size()
	result["pending_departures"] = _pending_population_departures.size()
	result["reconcile_interval_ticks"] = POPULATION_CATALOG_RECONCILE_TICKS
	result["zone_sync_batch"] = POPULATION_ZONE_SYNC_BATCH
	return result

func _transfer_bridge_traffic() -> void:
	if _harbor_suspended: return
	var traffic := mountain.get_node("MountainTraffic")
	for car in _population_cars:
		if not is_instance_valid(car): continue
		if car.is_in_group("regional_coach"): continue
		if car.get("is_driven_by_player") == true or car.get("is_broken") == true: continue
		var follower := car.get_parent() as PathFollow2D
		if follower == null: continue
		var lane := follower.get_parent() as Path2D
		if lane == null: continue
		var road_id := String(lane.get_meta("traffic_road_id", ""))
		if road_id.ends_with("mountain_bridge_outbound") and follower.progress > lane.curve.get_baked_length() - 8:
			_handoff(follower, traffic.lane)
		elif lane == traffic.lane and car.global_position.x < SEAM_X + 10 and car.global_position.y < -4560:
			for target in get_tree().get_nodes_in_group("unified_traffic_lane"):
				if String(target.get_meta("traffic_road_id", "")).ends_with("mountain_bridge_inbound"):
					_handoff(follower, target)
					break

func _handoff(follower: PathFollow2D, target: Path2D) -> bool:
	var point := follower.global_position
	var offset := target.curve.get_closest_offset(target.to_local(point))
	var destination := target.to_global(target.curve.sample_baked(offset, true))
	# O veículo permanece na origem até caber na fila de destino. A checagem
	# usa posições vivas, inclusive outra transferência feita neste mesmo frame.
	for other in get_tree().get_nodes_in_group("vehicle"):
		if other.get_parent() == follower or not other is Node2D: continue
		if other.global_position.distance_to(destination) < 110.0:
			var along := target.global_transform.x.normalized()
			var pose := target.curve.sample_baked_with_rotation(offset, true)
			along = target.global_transform.basis_xform(pose.x).normalized()
			if absf((other.global_position-destination).cross(along)) < 45.0:
				return false
	follower.reparent(target, false)
	follower.loop = bool(target.get_meta("traffic_lane_loop", false))
	follower.progress = offset
	follower.reset_physics_interpolation()
	handoff_max_displacement = maxf(handoff_max_displacement,point.distance_to(follower.global_position))
	for car in follower.get_children():
		if car is Node2D:
			car.position = Vector2.ZERO
			car.rotation = 0.0
			car.set_meta("traffic_lane_id", target.get_meta("traffic_lane_id", target.name))
			car.set_meta("traffic_road_id", target.get_meta("traffic_road_id", ""))
	return true

func get_streaming_stats() -> Dictionary:
	return {"ready": ready_for_crossing, "region": current_region, "resident_regions": 2 if ready_for_crossing else 1,
		"population": population_activity.stats, "population_zones": population_zones.snapshot(), "population_catalog": get_population_catalog_stats(),
		"mountain_load_gate": _mountain_load_gate.duplicate(true),
		"mountain_load_trigger": _mountain_load_trigger.duplicate(true),
		"vehicle_regional_prewarm": vehicle_prewarm_coordinator.telemetry_snapshot() if is_instance_valid(vehicle_prewarm_coordinator) else {},
		"sleeping_traffic": population_activity.stats.get("sleeping_traffic", 0), "memory_bytes": OS.get_static_memory_usage()}

func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null:
		if tree.node_added.is_connected(_on_population_node_added):
			tree.node_added.disconnect(_on_population_node_added)
		if tree.node_removed.is_connected(_on_population_node_removed):
			tree.node_removed.disconnect(_on_population_node_removed)
	population_activity.restore_all()
