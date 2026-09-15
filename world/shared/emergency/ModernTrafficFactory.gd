class_name ModernTrafficFactory
extends RefCounted

## Single integration point for the current Antigravity vehicle scene.
## Authored road geometry remains owned by each district; this factory only
## turns those exact lane centre-lines into Path2D traffic and parked cars.

# Resolve the scene after scripts finish loading. Preloading it here while
# referring to DemoTrafficVehicle can attach an incomplete script in a worker.
const VEHICLE_SCENE_PATH := "res://world/shared/traffic/TrafficVehicle.tscn"

# Compatibility alias; vehicles read the catalog directly to avoid the cycle
# factory -> vehicle scene -> vehicle script -> factory during threaded loads.
const VEHICLE_CROPS: Array[Rect2] = VehicleCatalog.VEHICLE_CROPS

const MINIMUM_SPAWN_CLEARANCE := 96.0
# DistrictRailLine occupies this authored horizontal band. Routes may cross it
# at the viaduct/level crossing, but no ambient car is initially placed there.
const DISTRICT_ONE_RAIL_SPAWN_EXCLUSION := Rect2(-320.0, 1570.0, 3360.0, 370.0)


static func create_lane(
	parent: Node,
	lane_name: String,
	points: PackedVector2Array,
	intersection_id: StringName = &"",
	intersection_axis: String = "AUTO"
) -> Path2D:
	assert(points.size() >= 2, "%s needs at least two authored points" % lane_name)
	var path := Path2D.new()
	path.name = lane_name
	# All authored traffic paths share one discovery group. Canonical graph
	# consumers still scope lanes by graph_source before interpreting structural
	# metadata, while legacy CentralDistrict paths retain their signal metadata.
	path.add_to_group("unified_traffic_lane")
	path.set_meta("traffic_lane_id", lane_name)
	path.set_meta("traffic_intersection_id", intersection_id)
	path.set_meta("traffic_intersection_axis", intersection_axis)
	var curve := Curve2D.new()
	curve.bake_interval = 8.0
	for point in points:
		curve.add_point(point)
	path.curve = curve
	parent.add_child(path)
	return path


static func spawn_moving_vehicle(
	path: Path2D,
	vehicle_name: String,
	archetype_id: String,
	requested_ratio: float,
	speed: float,
	visual_index: int
) -> DemoTrafficVehicle:
	var follow := PathFollow2D.new()
	follow.name = "%s_Follow" % vehicle_name
	# Open graph lanes must never wrap end -> start. A loop is permitted only
	# when the canonical lane generator declares it explicitly (or when a legacy
	# lane is geometrically closed).
	follow.loop = bool(path.get_meta("traffic_lane_loop", _curve_is_closed(path.curve)))
	follow.rotates = true
	follow.cubic_interp = true
	path.add_child(follow)
	follow.progress_ratio = _find_clear_ratio(path, requested_ratio)

	var vehicle := (load(VEHICLE_SCENE_PATH) as PackedScene).instantiate() as DemoTrafficVehicle
	vehicle.defer_presentation = true
	vehicle.name = vehicle_name
	vehicle.vehicle_id = archetype_id
	var spec := VehicleCatalog.get_vehicle_spec(archetype_id)
	var crop_idx := int(spec.get("crop_index", visual_index if visual_index >= 0 else 0))
	vehicle.crop = VEHICLE_CROPS[posmod(crop_idx, VEHICLE_CROPS.size())]
	vehicle.target_length = float(spec.get("target_length", 76.0))
	vehicle.speed = speed
	follow.add_child(vehicle)
	vehicle.apply_archetype(archetype_id, VehicleCatalog.get_random_color(archetype_id))
	vehicle.add_to_group("modern_traffic")
	vehicle.set_meta("traffic_lane_id", String(path.get_meta("traffic_lane_id", path.name)))
	vehicle.set_meta("traffic_road_index", int(path.get_meta("traffic_road_index", -1)))
	vehicle.set_meta("traffic_road_id", String(path.get_meta("traffic_road_id", "")))
	vehicle.set_meta("traffic_direction", int(path.get_meta("traffic_direction", 1)))
	return vehicle


static func spawn_parked_vehicle(
	parent: Node,
	vehicle_name: String,
	world_position: Vector2,
	world_rotation: float,
	archetype_id: String,
	visual_index: int,
	custom_color: Color = Color.TRANSPARENT,
	replenish: bool = true
) -> DemoTrafficVehicle:
	var vehicle := (load(VEHICLE_SCENE_PATH) as PackedScene).instantiate() as DemoTrafficVehicle
	vehicle.defer_presentation = true
	vehicle.name = vehicle_name
	vehicle.position = world_position
	vehicle.rotation = world_rotation
	var spec := VehicleCatalog.get_vehicle_spec(archetype_id)
	var crop_idx := int(spec.get("crop_index", visual_index if visual_index >= 0 else 0))
	vehicle.crop = VEHICLE_CROPS[posmod(crop_idx, VEHICLE_CROPS.size())]
	vehicle.target_length = float(spec.get("target_length", 76.0))
	parent.add_child(vehicle)
	var chosen_color := custom_color
	if chosen_color == Color.TRANSPARENT:
		chosen_color = VehicleCatalog.get_random_color(archetype_id)
	vehicle.apply_archetype(archetype_id, chosen_color)
	vehicle.configure_as_parked()
	vehicle.add_to_group("modern_parked_vehicle")
	if replenish and parent is Node2D:
		var slot: Node = load("res://world/shared/traffic/ParkedVehicleSpawn.gd").new()
		slot.name = vehicle_name+"Spawn"
		parent.add_child(slot)
		slot.configure(parent,vehicle,world_position,world_rotation,archetype_id,visual_index,chosen_color)
	return vehicle


static func _find_clear_ratio(path: Path2D, requested_ratio: float) -> float:
	var lane_loops := bool(path.get_meta("traffic_lane_loop", _curve_is_closed(path.curve)))
	var ratio := fposmod(requested_ratio, 1.0) if lane_loops else clampf(requested_ratio, 0.03, 0.97)
	var curve_length := maxf(1.0, path.curve.get_baked_length())
	# Occupancy (another car momentarily nearby) is benign and self-resolves as
	# traffic moves; a junction-unsafe ratio (inside a dead end's exclusion
	# zone, unable to plan or take its only exit -- see has_lane_transition())
	# is what actually strands a vehicle forever. If the full search below
	# never finds a position clear on both counts, prefer the best
	# junction-safe ratio seen over blindly returning wherever the walk
	# happened to stop.
	var best_junction_safe_ratio := -1.0
	for attempt in 12:
		var candidate := path.to_global(path.curve.sample_baked(ratio * curve_length, true))
		var junction_safe := _junction_spawn_is_clear(path, ratio, curve_length)
		if junction_safe and best_junction_safe_ratio < 0.0:
			best_junction_safe_ratio = ratio
		if _position_is_clear(path.get_tree(), candidate) and junction_safe:
			return ratio
		var step := 0.071 + float(attempt % 3) * 0.013
		ratio = fposmod(ratio + step, 1.0) if lane_loops else clampf(ratio + step, 0.03, 0.97)
	# The forward search above only ever walks toward 1.0 (or wraps on a loop),
	# so on an open lane it can exhaust its budget pinned at the 0.97 clamp --
	# which, on a dead-end lane whose only exit is a turn connector shortly
	# before the physical end (e.g. westgate_drive/forward_01, junction at
	# curve_length with no room to spare), is itself inside the junction's own
	# exclusion zone and therefore never actually safe. Returning that ratio
	# anyway used to spawn a vehicle already stuck at the road's hard end, with
	# no way to plan or take the only turn off it (see
	# JunctionTrafficController._planned_connection, which requires
	# entry_curve_offset >= progress) -- a real reproduced bug, not a
	# hypothetical: HarborTraffic_27 in HarborPreview.tscn. Before giving up,
	# search backward from the original request for a position the forward
	# walk could never reach.
	if not lane_loops and not (_position_is_clear(path.get_tree(), path.to_global(path.curve.sample_baked(ratio * curve_length, true))) and _junction_spawn_is_clear(path, ratio, curve_length)):
		var back_ratio := clampf(requested_ratio, 0.03, 0.97)
		for attempt in 12:
			var candidate := path.to_global(path.curve.sample_baked(back_ratio * curve_length, true))
			var junction_safe := _junction_spawn_is_clear(path, back_ratio, curve_length)
			if junction_safe and best_junction_safe_ratio < 0.0:
				best_junction_safe_ratio = back_ratio
			if _position_is_clear(path.get_tree(), candidate) and junction_safe:
				return back_ratio
			var step := 0.071 + float(attempt % 3) * 0.013
			back_ratio = clampf(back_ratio - step, 0.03, 0.97)
	# Nothing was ever clear of both a neighbour and the junction's exclusion
	# zone (a genuinely saturated lane). A ratio that at least never straps a
	# vehicle to a dead end -- even if another car was standing there a
	# moment ago -- is strictly safer than the raw fallback: the next few
	# frames of normal spacing/yield logic resolve mere occupancy on their
	# own, but there is no recovery from an unreachable connector.
	if best_junction_safe_ratio >= 0.0:
		return best_junction_safe_ratio
	return ratio


static func _curve_is_closed(curve: Curve2D) -> bool:
	if curve == null or curve.point_count < 3:
		return false
	return curve.get_point_position(0).distance_to(curve.get_point_position(curve.point_count - 1)) <= 1.0


static func _junction_spawn_is_clear(path: Path2D, ratio: float, curve_length: float) -> bool:
	for controller in path.get_tree().get_nodes_in_group("junction_traffic_controller"):
		# Uma pista da serra não pertence ao grafo de cruzamentos do porto.
		# O controlador rejeita road_index=-1; aplicar isso a outra região fazia
		# todas as tentativas terminarem no mesmo ponto de fallback da pista.
		var source = controller.get("graph_source")
		if source is Node and not source.is_ancestor_of(path):
			continue
		if controller.has_method("is_lane_spawn_position_safe"):
			return bool(controller.call("is_lane_spawn_position_safe", path, ratio * curve_length, 96.0))
	return true


static func _position_is_clear(tree: SceneTree, candidate: Vector2) -> bool:
	if DISTRICT_ONE_RAIL_SPAWN_EXCLUSION.has_point(candidate):
		return false
	for exclusion in tree.get_nodes_in_group("traffic_spawn_exclusion"):
		var bounds: Rect2 = exclusion.get_meta("traffic_spawn_exclusion_rect", Rect2())
		if bounds.has_point(candidate):
			return false
	for node in tree.get_nodes_in_group("vehicle"):
		if node is Node2D and (node as Node2D).global_position.distance_to(candidate) < MINIMUM_SPAWN_CLEARANCE:
			return false
	for node in tree.get_nodes_in_group("modern_parked_vehicle"):
		if node is Node2D and (node as Node2D).global_position.distance_to(candidate) < MINIMUM_SPAWN_CLEARANCE:
			return false
	return true
