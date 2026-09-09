extends SceneTree

## Full-scene boarding proof. Only the existing review shortcut positions the
## player initially on land; every subsequent position is reached by input or
## CharacterBody2D.move_and_collide, including the return to the quay.
const PREVIEW := preload("res://district/harbor_preview/HarborPreview.tscn")
var failures: Array[String] = []
var excluded: Array[RID] = []
var samples := 0
var sweeps := 0
var native_distance := 0.0
var water_samples := 0
var bullet_blocked := false
var bullet_clear := false
var future_positions: Dictionary = {}
var visited_markers: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := PREVIEW.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var waterfront := scene.get_node("Waterfront") as Node2D
	var player := scene.get_node("Player") as CharacterBody2D
	_check(waterfront.has_method("get_ship_access_data"), "Waterfront must publish the real ship access contract")
	if not waterfront.has_method("get_ship_access_data"):
		_finish(scene)
		return
	var data: Dictionary = waterfront.get_ship_access_data()
	_check(data.get("gangway_bounds") is Rect2 and data.get("deck_polygon") is PackedVector2Array and data.get("walk_route") is PackedVector2Array and data.get("obstacles") is Array, "Ship access contract has missing or incorrect geometry types")
	if failures.size() > 0:
		_finish(scene)
		return
	var route: PackedVector2Array = data.walk_route
	var deck: PackedVector2Array = data.deck_polygon
	var gangway: Rect2 = data.gangway_bounds
	_check(route.size() >= 6 and deck.size() >= 3 and not data.obstacles.is_empty(), "Ship must offer a genuine deck circuit with solid cargo, not just a spawn point")
	if route.size() < 2:
		_finish(scene)
		return
	_check(route[0].x < 3200.0 and not Geometry2D.is_point_in_polygon(route[0], deck), "Review shortcut must begin on the land quay, not teleport aboard")
	_check(gangway.position.x < 3200.0 and gangway.end.x > 3350.0, "Gangway must physically overlap both quay and ship")
	_check(scene.has_method("_visit_ship"), "Scene must expose its land-side boarding review shortcut")
	if scene.has_method("_visit_ship"):
		scene.call("_visit_ship")
	_check(player.global_position.distance_to(waterfront.to_global(route[0])) < 0.1, "Boarding shortcut must place the actual Player at the land-side route start")
	_disable_dynamic(scene, player)
	var collision := player.get_node("Collision") as CollisionShape2D
	_check(collision != null and collision.shape != null, "Actual Player capsule must exist")
	if collision == null or collision.shape == null:
		_finish(scene)
		return
	player.collision_mask = 1
	var space := player.get_world_2d().direct_space_state
	_check(not bool(data.get("mission_integrated", true)) and not bool(data.get("ship_pilotable", true)), "Ship access must not pretend that missions or ship driving are implemented")
	for label in data.get("future_markers", {}):
		var local_position: Vector2 = data.future_markers[label]
		var marker := waterfront.get_node_or_null(NodePath("ShipWaypoints/" + String(label))) as Marker2D
		_check(marker != null and marker.position.distance_to(local_position) < 0.1, "Future ship waypoint must be an actual named Marker2D: %s" % label)
		var world := waterfront.to_global(local_position)
		future_positions[String(label)] = world
		_check(_query(space, collision.shape, world + collision.position).is_empty(), "Future mission marker must be physically reachable: %s" % label)
	_record_visited_markers(player.global_position, player.global_position)
	var quay: Rect2 = waterfront.get_waterfront_audit_data().quay_bounds
	for index in range(route.size() - 1):
		var steps := maxi(1, ceili(route[index].distance_to(route[index + 1]) / 8.0))
		for step in range(steps + 1):
			var local := route[index].lerp(route[index + 1], float(step) / steps)
			_check(quay.has_point(local) or gangway.has_point(local) or Geometry2D.is_point_in_polygon(local, deck), "Walk route leaves quay/gangway/deck at %s" % local)
			var hits := _query(space, collision.shape, waterfront.to_global(local) + collision.position)
			_check(hits.is_empty(), "Actual Player capsule blocked at %s: %s" % [local, _names(hits)])
			samples += 1
	_audit_solids(space, waterfront, data)
	# The review button must not conceal a barrier between the road sidewalk and
	# the quay: sweep back to the real Quay Boulevard sidewalk, then walk forward
	# again with input. No extra player positioning is used for this approach.
	var sidewalk := Vector2.ZERO
	for road in scene.get_node("RoadLayout").get_road_graph_definitions():
		if String(road.id) == "quay_boulevard":
			var road_points: PackedVector2Array = road.points
			var nearest := Geometry2D.get_closest_point_to_segment(route[0], road_points[0], road_points[-1])
			sidewalk = nearest + (route[0] - nearest).normalized() * (float(road.width) * 0.5 + 21.0)
	_check(not sidewalk.is_zero_approx(), "Boarding quay must have an approach from the existing Quay Boulevard sidewalk")
	if not sidewalk.is_zero_approx():
		player.set_physics_process(false)
		_sweep(player, waterfront.to_global(sidewalk))
		await _walk_input(player, waterfront.to_global(route[0]))
	# Prove ordinary keyboard movement boards the ship, not just body sweeps.
	var native_end := 0
	for index in range(1, route.size()):
		await _walk_input(player, waterfront.to_global(route[index]))
		native_end = index
		if Geometry2D.is_point_in_polygon(waterfront.to_local(player.global_position), deck):
			break
	_check(native_distance > 100.0 and Geometry2D.is_point_in_polygon(waterfront.to_local(player.global_position), deck), "Actual Player input must cross the gangway and reach the deck")
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	var visited_bow := waterfront.to_local(player.global_position).y < 930.0
	for index in range(native_end + 1, route.size()):
		_sweep(player, waterfront.to_global(route[index]))
		visited_bow = visited_bow or route[index].y < 930.0
		await _try_bullet_probes(scene, player, waterfront, data, route, index)
	_check(visited_bow, "Deck circuit must reach the bow, not merely touch the gangway landing")
	for index in range(route.size() - 2, -1, -1):
		_sweep(player, waterfront.to_global(route[index]))
	_check(player.global_position.distance_to(waterfront.to_global(route[0])) < 0.2, "Actual Player must return to the quay without intermediate teleportation")
	_check(bullet_clear, "A real player-fired projectile must travel through a clear deck corridor")
	_check(bullet_blocked, "A real player-fired projectile must be stopped by ship cargo")
	for label in future_positions:
		_check(visited_markers.has(label), "Actual Player circuit must visit future mission marker: %s" % label)
	print("HARBOR_SHIP_ACCESS_RESULT failures=%d player_capsule_samples=%d actual_sweeps=%d native_input_distance=%.1f water_samples=%d bow=%s bullet_clear=%s bullet_blocked=%s" % [failures.size(), samples, sweeps, native_distance, water_samples, visited_bow, bullet_clear, bullet_blocked])
	_finish(scene)


func _disable_dynamic(node: Node, player: CharacterBody2D) -> void:
	if node is PhysicsBody2D and not node is StaticBody2D:
		excluded.append((node as PhysicsBody2D).get_rid())
		if node != player:
			node.collision_layer = 0
			node.collision_mask = 0
			node.set_physics_process(false)
	for child in node.get_children():
		_disable_dynamic(child, player)


func _audit_solids(space: PhysicsDirectSpaceState2D, waterfront: Node2D, data: Dictionary) -> void:
	var probe := CircleShape2D.new()
	probe.radius = 2.0
	for bounds: Rect2 in data.obstacles:
		_check(not _query(space, probe, waterfront.to_global(bounds.get_center())).is_empty(), "Ship cargo/accommodation must have a real solid at %s" % bounds.get_center())
	for bounds: Rect2 in data.get("guard_rails", []):
		_check(not _query(space, probe, waterfront.to_global(bounds.get_center())).is_empty(), "Ship/gangway guard rail must be a real solid at %s" % bounds.get_center())
	for edge: PackedVector2Array in data.get("deck_edge_segments", []):
		_check(not _query(space, probe, waterfront.to_global((edge[0] + edge[1]) * 0.5)).is_empty(), "Deck perimeter guard rail must be a real solid")
	var gangway: Rect2 = data.gangway_bounds
	var water_points := PackedVector2Array([Vector2(4000, 1000), Vector2(3300, 750), Vector2(gangway.get_center().x, gangway.position.y - 30), Vector2(gangway.get_center().x, gangway.end.y + 30)])
	for point in water_points:
		_check(not _query(space, probe, waterfront.to_global(point)).is_empty(), "Water outside the exact boarding opening must remain blocked at %s" % point)
	# A dense negative grid catches accidental rectangular holes around the
	# tapered bow/stern that four hand-picked water points could miss.
	var cutout: PackedVector2Array = data.get("water_cutout_polygon", data.get("hull_polygon", data.deck_polygon))
	for x in range(3205, 4001, 25):
		for y in range(600, 2201, 25):
			var point := Vector2(x, y)
			if gangway.grow(3.0).has_point(point) or Geometry2D.is_point_in_polygon(point, cutout):
				continue
			var near_boundary := false
			for index in cutout.size():
				if Geometry2D.get_closest_point_to_segment(point, cutout[index], cutout[(index + 1) % cutout.size()]).distance_to(point) < 3.0:
					near_boundary = true
					break
			if near_boundary:
				continue
			water_samples += 1
			_check(not _query(space, probe, waterfront.to_global(point)).is_empty(), "Unexpected walkable hole in surrounding water at %s" % point)


func _walk_input(player: CharacterBody2D, destination: Vector2) -> void:
	player.set_physics_process(true)
	var start := player.global_position
	for _frame in 600:
		var delta := destination - player.global_position
		if delta.length() < 5.0:
			break
		_release_input()
		var direction := delta.normalized()
		if absf(direction.x) > 0.1:
			Input.action_press("ui_right" if direction.x > 0 else "ui_left", absf(direction.x))
		if absf(direction.y) > 0.1:
			Input.action_press("ui_down" if direction.y > 0 else "ui_up", absf(direction.y))
		await physics_frame
	_release_input()
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	native_distance += player.global_position.distance_to(start)
	_record_visited_markers(start, player.global_position)
	_check(player.global_position.distance_to(destination) < 8.0, "Native Player input could not reach %s, stopped at %s" % [destination, player.global_position])


func _sweep(player: CharacterBody2D, destination: Vector2) -> void:
	var start := player.global_position
	var hit := player.move_and_collide(destination - player.global_position)
	_record_visited_markers(start, player.global_position)
	sweeps += 1
	_check(hit == null, "Actual Player sweep hit %s en route to %s" % [str(hit.get_collider()) if hit != null else "none", destination])
	_check(player.global_position.distance_to(destination) < 0.2, "Actual Player did not reach deck waypoint %s" % destination)


func _record_visited_markers(start: Vector2, finish: Vector2) -> void:
	for label in future_positions:
		if Geometry2D.get_closest_point_to_segment(future_positions[label], start, finish).distance_to(future_positions[label]) < 8.0:
			visited_markers[label] = true


func _try_bullet_probes(scene: Node2D, player: CharacterBody2D, waterfront: Node2D, data: Dictionary, route: PackedVector2Array, route_index: int) -> void:
	if not bullet_clear and route_index + 1 < route.size():
		var target := waterfront.to_global(route[route_index + 1])
		if player.global_position.distance_to(target) > 180.0:
			var bullet := _fire_player_bullet(scene, player, target)
			if bullet != null:
				var first := bullet.global_position
				for _frame in 4:
					await physics_frame
					if not is_instance_valid(bullet):
						break
				if is_instance_valid(bullet):
					bullet_clear = bullet.global_position.distance_to(first) > 55.0 and not bool(bullet.get("_spent"))
					bullet.queue_free()
	if bullet_blocked:
		return
	var local := waterfront.to_local(player.global_position)
	for bounds: Rect2 in data.obstacles:
		# Choose a container, not an arbitrary water or superstructure collision.
		if bounds.size.x > 100.0 or bounds.size.y > 150.0:
			continue
		var distance := local.distance_to(bounds.get_center())
		if distance < 65.0 or distance > 280.0:
			continue
		var ray := PhysicsRayQueryParameters2D.create(player.global_position, waterfront.to_global(bounds.get_center()), 1, excluded)
		var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or not bounds.grow(2.0).has_point(waterfront.to_local(hit.position)):
			continue
		var bullet := _fire_player_bullet(scene, player, waterfront.to_global(bounds.get_center()))
		if bullet == null:
			continue
		var outcome := {"spent": false}
		bullet.tree_exiting.connect(func(): outcome.spent = bool(bullet.get("_spent")))
		for _frame in 45:
			await physics_frame
			if not is_instance_valid(bullet):
				break
		bullet_blocked = bool(outcome.spent)
		if is_instance_valid(bullet):
			bullet.queue_free()
		if bullet_blocked:
			return


func _fire_player_bullet(scene: Node2D, player: CharacterBody2D, target: Vector2) -> Node2D:
	player.set("active_weapon_id", "pistol")
	var ammo: Dictionary = player.get("weapon_ammo")
	ammo["pistol"] = {"clip": 10, "reserve": 20}
	player.set("weapon_ammo", ammo)
	var before := scene.get_children()
	player.call("_shoot_towards", target)
	for child in scene.get_children():
		if not before.has(child) and child is Node2D:
			var script := child.get_script() as Script
			if script != null and script.resource_path == "res://Bullet.gd":
				return child as Node2D
	_check(false, "Actual Player pistol firing must instantiate the production Bullet")
	return null


func _query(space: PhysicsDirectSpaceState2D, shape: Shape2D, point: Vector2) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = excluded
	return space.intersect_shape(query, 16)


func _names(hits: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for hit in hits:
		if hit.collider is Node:
			names.append(String(hit.collider.get_path()))
	return ", ".join(names)


func _release_input() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(scene: Node) -> void:
	_release_input()
	for failure in failures:
		push_error("HARBOR_SHIP_ACCESS: " + failure)
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)
