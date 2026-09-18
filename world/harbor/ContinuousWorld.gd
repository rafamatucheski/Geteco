extends Node
## One world, one Player, one camera. Regions are prepared ahead of travel;
## their simulation/rendering sleeps outside the active neighbourhood.
const MOUNTAIN_SCENE := "res://world/mountain_pass/MountainPass.tscn"
const MOUNTAIN_OFFSET := Vector2(4300, -4960)
const SEAM_X := 7300.0
var mountain: Node2D
var building := false
var ready_for_crossing := false
var current_region := "harbor"
var _elapsed := 0.0
var population_activity := preload("res://systems/PopulationActivity.gd").new()
var _mountain_layers: Array[CanvasLayer] = []
var _mountain_layer_visibility: Dictionary = {}
var _mountain_layers_selected := false
var handoff_max_displacement := 0.0

func _ready() -> void:
	add_to_group("continuous_world")

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
	if not ready_for_crossing and not building and (point.y < -1000 or pending.get("region", "") == "mountain"):
		ensure_mountain()
	_budget_traffic(point)
	if not ready_for_crossing: return
	_update_region()
	_transfer_bridge_traffic()

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

func _update_region() -> void:
	var point := exterior_position()
	var player: Node2D = mountain.player_instance
	var selected: bool = point.x >= SEAM_X and point.y < -2000 or bool(player.get_meta("mountain_interior", false))
	current_region = "mountain" if selected else "harbor"
	var nearby: bool = selected or point.distance_to(Vector2(SEAM_X, -4560)) < 3200
	var harbor_nearby: bool = not selected or point.distance_to(Vector2(SEAM_X, -4560)) < 3200
	_update_harbor_suspension(harbor_nearby)
	mountain.visible = nearby
	mountain.process_mode = Node.PROCESS_MODE_INHERIT if nearby else Node.PROCESS_MODE_DISABLED
	mountain.region_selected = selected
	mountain.cold_controller.set_process(selected)
	if not selected: mountain.storm_manager.set_sheltered(true)
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
	if _harbor_suspended: return
	var walkers := get_tree().get_nodes_in_group("pedestrian")
	for actor in get_tree().get_nodes_in_group("authored_sidewalk_pedestrian"):
		if not walkers.has(actor): walkers.append(actor)
	population_activity.update(get_parent(), point, get_tree().get_nodes_in_group("modern_traffic"), walkers)

func _transfer_bridge_traffic() -> void:
	if _harbor_suspended: return
	var traffic := mountain.get_node("MountainTraffic")
	for car in get_tree().get_nodes_in_group("modern_traffic"):
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
		"population": population_activity.stats, "sleeping_traffic": population_activity.stats.get("sleeping_traffic", 0), "memory_bytes": OS.get_static_memory_usage()}

func _exit_tree() -> void:
	population_activity.restore_all()
