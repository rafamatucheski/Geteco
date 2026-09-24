extends RefCounted
## Wheel-local raycasts are the sole authority for ground contact and orientation.

const SNOW_EDGE_Z := (-1350.0-4960.0)/16.0

static func sample(vehicle: CharacterBody3D, wheel_position: Vector3) -> Dictionary:
	if not vehicle.is_inside_tree(): return {}
	var query := PhysicsRayQueryParameters3D.create(wheel_position+Vector3.UP*.65,wheel_position-Vector3.UP*1.15,1,[vehicle.get_rid()])
	query.hit_from_inside = false
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var normal: Vector3 = hit.normal
	if normal.dot(Vector3.UP) < .45: return {}
	var point: Vector3 = hit.position
	var kind := _surface_kind(hit.collider,point)
	if _inside_water(vehicle,point): kind = "water"
	return {"point":point,"normal":normal.normalized(),"kind":kind,"wet":kind=="water" or _weather_wet(vehicle)}

static func _surface_kind(collider: Object, point: Vector3) -> String:
	var cursor := collider as Node
	var labels := ""
	for depth in 8:
		if cursor == null: break
		if cursor.has_meta("vehicle_surface"): return str(cursor.get_meta("vehicle_surface"))
		labels += " "+str(cursor.name).to_lower()
		cursor = cursor.get_parent()
	if "road" in labels or "sidewalk" in labels or "gangway" in labels or "deck" in labels or "port" in labels:
		return "hard"
	if "mountainterrain" in labels:
		return "snow" if point.z < SNOW_EDGE_Z else "dirt"
	if "snow" in labels: return "snow"
	if "earth" in labels or "sawmill" in labels or "land" in labels or "shore" in labels:
		return "dirt"
	return "hard"

static func _weather_wet(vehicle: Node) -> bool:
	var cursor: Node = vehicle
	var session: Variant = null
	while cursor != null:
		session = cursor.get("session")
		if is_instance_valid(session): break
		cursor = cursor.get_parent()
	if not is_instance_valid(session): return false
	var weather: Variant = session.get("weather")
	if not is_instance_valid(weather): return false
	var controller: Variant = weather.get("controller")
	if is_instance_valid(controller) and controller.get("state") != null and str(controller.state.region_id) == "mountain": return false
	return int(weather.get("weather_state")) in [1,2]

static func _inside_water(vehicle: Node, point: Vector3) -> bool:
	for candidate in vehicle.get_tree().get_nodes_in_group("native_water_surface"):
		if candidate is Node3D and candidate.is_visible_in_tree() and candidate.has_method("contains_water"):
			if absf(point.y-candidate.global_position.y)<.8 and candidate.contains_water(point): return true
	return false
