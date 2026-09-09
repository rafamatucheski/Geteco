extends SceneTree

## Independent full-scene audit: authored setbacks plus actual physics geometry
## and a real PlayerCar departure, not only the provider's dictionary contract.
const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"

var _failures: Array[String] = []
var _dynamic_exclusions: Array[RID] = []
var _road_samples := 0
var _access_samples := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PREVIEW_PATH) as PackedScene
	if packed == null:
		push_error("HARBOR_DISTRICT: full preview scene failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var district := scene.get_node_or_null("District") as Node2D
	var layout := scene.get_node_or_null("RoadLayout") as Node2D
	var network := scene.get_node_or_null("RoadNetwork") as Node2D
	var car := scene.get_node_or_null("PlayerCar") as CharacterBody2D
	var player := scene.get_node_or_null("Player") as CharacterBody2D
	_check(district != null and layout != null and network != null, "Full preview is missing district/road nodes")
	_check(car != null and player != null, "Full preview needs its actual player and driveable car")
	if district == null or layout == null or network == null or car == null or player == null:
		_finish(scene)
		return
	var spatial_errors: Array = district.call("get_spatial_audit")
	_check(spatial_errors.is_empty(), "Authored spatial audit: %s" % [spatial_errors])
	var road_errors: Array = network.call("get_validation_errors")
	_check(road_errors.is_empty(), "Road graph validation: %s" % [road_errors])
	var safety := scene.get_node_or_null("RoadSafety")
	_check(safety != null, "Full district must include road/rail safety")
	if safety != null:
		var safety_data: Dictionary = safety.get_safety_data()
		_check(safety_data.validation_errors.is_empty(), "Road/rail safety validation: %s" % [safety_data.validation_errors])
	_collect_dynamic_exclusions(scene)
	var space := scene.get_world_2d().direct_space_state
	var sites: Array = []
	var accesses: Array = []
	for district_name in ["District", "EastDistrict", "NorthDistrict"]:
		var provider := scene.get_node_or_null(district_name) as Node2D
		_check(provider != null, "Expanded preview needs %s" % district_name)
		if provider == null:
			continue
		if provider.has_method("get_spatial_audit"):
			var provider_errors: Array = provider.call("get_spatial_audit")
			_check(provider_errors.is_empty(), "%s spatial audit: %s" % [district_name, provider_errors])
		var provider_sites: Array = provider.get("sites")
		var provider_accesses: Array = provider.get("accesses")
		_check(not provider_sites.is_empty(), "%s needs authored building sites" % district_name)
		for site in provider_sites:
			var world_site: Dictionary = site.duplicate()
			world_site.bounds = provider.global_transform * (site.bounds as Rect2)
			sites.append(world_site)
		for access in provider_accesses:
			var world_access: Dictionary = access.duplicate()
			world_access.bounds = provider.global_transform * (access.bounds as Rect2)
			world_access.destination = provider.to_global(access.destination)
			accesses.append(world_access)
	var definitions: Array = layout.call("get_road_graph_definitions")
	_audit_building_setbacks(sites, definitions, accesses)
	_audit_road_physics(space, definitions)
	_audit_access_physics(space, accesses)
	_audit_building_solids(space, sites)
	await _drive_out_of_garage(scene, car, player)
	print("HARBOR_DISTRICT: buildings=%d accesses=%d road_physics_samples=%d access_physics_samples=%d failures=%d" % [
		sites.size(), accesses.size(), _road_samples, _access_samples, _failures.size()])
	_finish(scene)


func _collect_dynamic_exclusions(node: Node) -> void:
	if node is PhysicsBody2D and not node is StaticBody2D:
		_dynamic_exclusions.append((node as PhysicsBody2D).get_rid())
	for child in node.get_children():
		_collect_dynamic_exclusions(child)


func _audit_building_setbacks(sites: Array, definitions: Array, accesses: Array) -> void:
	for site in sites:
		var footprint: Rect2 = site.bounds
		var visible_bounds := footprint.grow(18.0)
		for road in definitions:
			var points: PackedVector2Array = road.points
			for index in range(points.size() - 1):
				var sidewalk := Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(float(road.width) * 0.5 + 42.0)
				_check(not visible_bounds.intersects(sidewalk), "%s facade/shadow intrudes on %s sidewalk" % [site.id, road.id])
		for access in accesses:
			_check(not footprint.grow(-1.0).intersects(access.bounds), "%s footprint blocks %s" % [site.id, access.id])


func _audit_road_physics(space: PhysicsDirectSpaceState2D, definitions: Array) -> void:
	var probe := CircleShape2D.new()
	probe.radius = 4.0
	for road in definitions:
		var points: PackedVector2Array = road.points
		for index in range(points.size() - 1):
			var start := points[index]
			var finish := points[index + 1]
			var normal := (finish - start).normalized().orthogonal()
			var steps := ceili(start.distance_to(finish) / 60.0)
			for step in range(steps + 1):
				for fraction in [-0.4, 0.0, 0.4]:
					var position: Vector2 = start.lerp(finish, float(step) / steps) + normal * float(road.width) * float(fraction)
					var hits := _query(space, probe, position)
					_road_samples += 1
					_check(hits.is_empty(), "Static obstacle blocks %s asphalt at %s: %s" % [road.id, position, _describe_hits(hits)])


func _audit_access_physics(space: PhysicsDirectSpaceState2D, accesses: Array) -> void:
	for access in accesses:
		var bounds: Rect2 = (access.bounds as Rect2).grow(-3.0)
		var probe := RectangleShape2D.new()
		probe.size = bounds.size
		var hits := _query(space, probe, bounds.get_center())
		_access_samples += 1
		_check(hits.is_empty(), "%s access strip contains a solid: %s" % [access.id, _describe_hits(hits)])
		var destination_probe := CircleShape2D.new()
		destination_probe.radius = 12.0
		var destination_hits := _query(space, destination_probe, access.destination)
		_check(destination_hits.is_empty(), "%s destination is not reachable: %s" % [access.id, _describe_hits(destination_hits)])


func _audit_building_solids(space: PhysicsDirectSpaceState2D, sites: Array) -> void:
	var probe := CircleShape2D.new()
	probe.radius = 2.0
	for site in sites:
		var hits := _query(space, probe, (site.bounds as Rect2).get_center())
		_check(not hits.is_empty(), "%s building is missing a real physical solid" % site.id)


func _query(space: PhysicsDirectSpaceState2D, shape: Shape2D, position: Vector2) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = _dynamic_exclusions
	return space.intersect_shape(query, 16)


func _describe_hits(hits: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for hit in hits:
		var collider := hit.get("collider") as Node
		if collider != null:
			names.append(String(collider.get_path()))
	return ", ".join(names)


func _drive_out_of_garage(scene: Node2D, car: CharacterBody2D, player: CharacterBody2D) -> void:
	# Keep the actual scene geometry and vehicle controller. Temporarily remove
	# ambient traffic interactions so this is specifically an access regression.
	var life := scene.get_node_or_null("Life")
	if life != null:
		life.process_mode = Node.PROCESS_MODE_DISABLED
		for vehicle in life.get("vehicles"):
			if vehicle is CollisionObject2D:
				(vehicle as CollisionObject2D).collision_layer = 0
	var start := car.global_position
	_check(start.x >= 620.0 and start.x <= 900.0 and start.y > 1695.0 and start.y < 2130.0, "PlayerCar does not start in the garage access apron")
	car.rotation = PI * 0.5
	car.set("max_speed", 160.0)
	car.call("enter_vehicle", player)
	await physics_frame
	_check(bool(car.get("is_driven_by_player")), "Actual PlayerCar entry failed")
	var collided := false
	Input.action_press("ui_up")
	for _frame in 360:
		await physics_frame
		if car.get_slide_collision_count() > 0:
			collided = true
		if car.global_position.y >= 2190.0:
			break
	Input.action_release("ui_up")
	var traveled := car.global_position.distance_to(start)
	_check(not collided, "PlayerCar collided while leaving its authored garage access")
	_check(car.global_position.y >= 2170.0 and traveled > 100.0, "PlayerCar could not reach Dock Street from parking; final=%s traveled=%.1f" % [car.global_position, traveled])
	print("HARBOR_GARAGE_DRIVE: start=%s end=%s traveled=%.1f collided=%s" % [start, car.global_position, traveled, collided])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(scene: Node) -> void:
	Input.action_release("ui_up")
	for failure in _failures:
		push_error("HARBOR_DISTRICT: " + failure)
	scene.queue_free()
	quit(0 if _failures.is_empty() else 1)
