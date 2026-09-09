extends SceneTree

## Full-scene spatial and physical regression: the actual player's capsule must
## traverse both alleys in both directions, including beneath the rail viaduct.
const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"
var _failures: Array[String] = []
var _exclusions: Array[RID] = []
var _samples := 0
var _sweeps := 0
var _underpasses := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PREVIEW_PATH) as PackedScene
	if packed == null:
		push_error("HARBOR_ALLEYS: preview scene failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var alleys := scene.get_node_or_null("Alleys")
	var player := scene.get_node_or_null("Player") as CharacterBody2D
	_check(alleys != null and alleys.has_method("get_alley_definitions"), "Preview must instantiate its pedestrian alley provider")
	_check(player != null, "Preview must contain the actual Player")
	if alleys == null or not alleys.has_method("get_alley_definitions") or player == null:
		_finish(scene)
		return
	var definitions: Array = alleys.get_alley_definitions()
	_check(definitions.size() == 2, "Expected the two authored residential passages")
	_check(alleys.find_children("*", "CollisionObject2D", true, false).is_empty(), "Alley paving must not create blocking collision objects")
	var player_collision := player.get_node_or_null("Collision") as CollisionShape2D
	_check(player_collision != null and player_collision.shape != null, "Actual player capsule must exist")
	if player_collision == null or player_collision.shape == null:
		_finish(scene)
		return
	var player_shape := player_collision.shape
	var roads: Array = scene.get_node("RoadLayout").get_road_graph_definitions()
	var sites: Array = scene.get_node("District").sites
	var land: Rect2 = scene.get_node("District").LAND_BOUNDS
	var rail := scene.get_node("FreightRail")
	var rail_points: PackedVector2Array = rail.get_rail_graph_data().get("global_points", PackedVector2Array())
	var space := scene.get_world_2d().direct_space_state
	_disable_dynamic_collisions(scene, player)
	# Keep the real body in its physics space while taking over motion for the test.
	# PROCESS_MODE_DISABLED would remove CollisionObject2D from that space.
	player.set_physics_process(false)
	player.set_process(false)
	player.collision_mask = 1
	player.velocity = Vector2.ZERO
	for alley in definitions:
		_check(alley.get("points") is PackedVector2Array, "Alley points must be a PackedVector2Array")
		_check(alley.get("width") is float and float(alley.width) >= 28.0, "Alley must expose its full usable width")
		_check(alley.get("pedestrian_only", false) == true, "Alley must not masquerade as a vehicle street")
		var points: PackedVector2Array = alley.points
		if points.size() < 3:
			_check(false, "Alley must have its authored corners, not a straight placeholder")
			continue
		var start_road := _sidewalk_road(points[0], roads)
		var end_road := _sidewalk_road(points[-1], roads)
		_check(start_road == "foundry_avenue", "%s north entrance must join Foundry's real sidewalk" % alley.id)
		_check(end_road == "market_street", "%s south entrance must join Market's real sidewalk" % alley.id)
		var width := float(alley.width)
		var turns := 0
		var underpass_verified := false
		for index in range(points.size() - 1):
			var start := points[index]
			var finish := points[index + 1]
			var passage := Rect2(start, Vector2.ZERO).expand(finish).grow(width * 0.5)
			_check(land.encloses(passage), "%s leaves authored land" % alley.id)
			for site in sites:
				_check(not passage.intersects(site.bounds), "%s paving clips building %s" % [alley.id, site.id])
			if rail.has_method("get_pillar_bounds"):
				for pillar: Rect2 in rail.get_pillar_bounds():
					_check(not passage.intersects(pillar), "%s includes a rail support" % alley.id)
			for rail_index in range(rail_points.size() - 1):
				var crossing = Geometry2D.segment_intersects_segment(start, finish, rail_points[rail_index], rail_points[rail_index + 1])
				if crossing != null:
					var vertical: Dictionary = rail.get_elevated_crossing_data(crossing)
					_check(vertical.get("classification", "") == "rail_elevated", "%s crosses a train at ground level" % alley.id)
					underpass_verified = true
			var corridor_shape := RectangleShape2D.new()
			corridor_shape.size = passage.size - Vector2.ONE * 0.5
			var full_hits := _query(space, corridor_shape, passage.get_center())
			_check(full_hits.is_empty(), "%s whole pavement blocked: %s" % [alley.id, _describe(full_hits)])
			var steps := maxi(1, ceili(start.distance_to(finish) / 12.0))
			for step in range(steps + 1):
				var point := start.lerp(finish, float(step) / steps)
				var hits := _query(space, player_shape, point + player_collision.position)
				_check(hits.is_empty(), "%s player's shape blocked at %s: %s" % [alley.id, point, _describe(hits)])
				_samples += 1
			if index > 0 and absf((start - points[index - 1]).normalized().cross((finish - start).normalized())) > 0.1:
				turns += 1
		_check(turns >= 2, "%s must retain both courtyard corners" % alley.id)
		_check(underpass_verified, "%s must exercise its real viaduct underpass" % alley.id)
		if underpass_verified:
			_underpasses += 1
		for reverse in [false, true]:
			var itinerary := points.duplicate()
			if reverse:
				itinerary.reverse()
			player.global_position = itinerary[0]
			await physics_frame
			for index in range(1, itinerary.size()):
				var hit := player.move_and_collide(itinerary[index] - player.global_position)
				_sweeps += 1
				_check(hit == null, "%s actual player sweep hit %s at %s" % [alley.id, str(hit.get_collider()) if hit != null else "none", player.global_position])
				_check(player.global_position.distance_to(itinerary[index]) < 0.1, "%s player did not reach passage corner" % alley.id)
	print("HARBOR_ALLEYS_RESULT alleys=%d player_shape_samples=%d real_player_sweeps=%d elevated_underpasses=%d failures=%d" % [definitions.size(), _samples, _sweeps, _underpasses, _failures.size()])
	_finish(scene)


func _sidewalk_road(point: Vector2, roads: Array) -> String:
	for road in roads:
		var points: PackedVector2Array = road.points
		for index in range(points.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
			var distance := point.distance_to(nearest)
			if distance >= float(road.width) * 0.5 + 5.0 and distance <= float(road.width) * 0.5 + 42.0 - 5.0:
				return String(road.id)
	return ""


func _disable_dynamic_collisions(node: Node, player: CharacterBody2D) -> void:
	if node is PhysicsBody2D and not node is StaticBody2D:
		_exclusions.append((node as PhysicsBody2D).get_rid())
		if node != player:
			node.collision_layer = 0
			node.collision_mask = 0
	for child in node.get_children():
		_disable_dynamic_collisions(child, player)


func _query(space: PhysicsDirectSpaceState2D, shape: Shape2D, point: Vector2) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.exclude = _exclusions
	return space.intersect_shape(query, 16)


func _describe(hits: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for hit in hits:
		var collider := hit.get("collider") as Node
		if collider != null:
			names.append(String(collider.get_path()))
	return ", ".join(names)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(scene: Node) -> void:
	for failure in _failures:
		push_error("HARBOR_ALLEYS: " + failure)
	scene.queue_free()
	quit(0 if _failures.is_empty() else 1)
