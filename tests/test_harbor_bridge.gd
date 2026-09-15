extends SceneTree

## Exercises the real driveable vehicle across both bridge lanes, with water
## collision still enabled. Graph reachability lives in the road contract test.
const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"

var _failures: Array[String] = []
var _exclusions: Array[RID] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PREVIEW_PATH) as PackedScene
	if packed == null:
		push_error("HARBOR_BRIDGE: full preview could not load")
		quit(1)
		return
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var car := scene.get_node_or_null("PlayerCar") as CharacterBody2D
	var player := scene.get_node_or_null("Player") as CharacterBody2D
	_check(car != null and player != null, "Full scene must contain the actual PlayerCar and Player")
	var bridge_exists := false
	for candidate in scene.find_children("*", "Node2D", true, false):
		var script := candidate.get_script() as Script
		if script != null and script.resource_path.ends_with("/HarborBridge.gd"):
			bridge_exists = true
	_check(bridge_exists, "Scene must instantiate the physical HarborBridge")
	if car == null or player == null or not bridge_exists:
		_finish(scene)
		return
	var life := scene.get_node_or_null("Life")
	if life != null:
		life.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_ambient_collisions(scene, car)
	var space := scene.get_world_2d().direct_space_state
	for x in [3250.0, 3500.0, 3800.0, 4100.0, 4330.0]:
		for y in [352.0, 400.0, 448.0]:
			var hits := _probe(space, Vector2(x, y))
			_check(hits.is_empty(), "Bridge asphalt blocked at %s: %s" % [Vector2(x, y), _colliders(hits)])
		for y in [200.0, 650.0]:
			var hits := _probe(space, Vector2(x, y))
			_check(not hits.is_empty(), "Water outside bridge is missing collision at %s" % Vector2(x, y))
	car.call("enter_vehicle", player)
	# Boarding now animates before throttle input is accepted.
	while is_instance_valid(car.get("_boarding")) and car.get("_boarding").active:
		await process_frame
	car.set("max_speed", 240.0)
	await physics_frame
	_check(bool(car.get("is_driven_by_player")), "Actual vehicle entry must succeed")
	await _drive_leg(car, Vector2(3100, 430), Vector2(4500, 430), 0.0, "eastbound")
	await _drive_leg(car, Vector2(4500, 370), Vector2(3100, 370), PI, "westbound")
	print("HARBOR_BRIDGE_RESULT failures=%d directions=2 water_boundary_samples=10 asphalt_samples=15" % _failures.size())
	_finish(scene)


func _disable_ambient_collisions(node: Node, car: CharacterBody2D) -> void:
	if node is PhysicsBody2D and not node is StaticBody2D:
		var body := node as PhysicsBody2D
		_exclusions.append(body.get_rid())
		if body != car:
			body.collision_layer = 0
			body.collision_mask = 0
	for child in node.get_children():
		_disable_ambient_collisions(child, car)


func _probe(space: PhysicsDirectSpaceState2D, point: Vector2) -> Array[Dictionary]:
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = _exclusions
	return space.intersect_shape(query, 8)


func _drive_leg(car: CharacterBody2D, start: Vector2, destination: Vector2, heading: float, label: String) -> void:
	Input.action_release("move_up")
	car.velocity = Vector2.ZERO
	car.global_position = start
	car.rotation = heading
	await physics_frame
	var collisions: Array[String] = []
	Input.action_press("move_up")
	for _frame in 720:
		await physics_frame
		for collision_index in car.get_slide_collision_count():
			var collision := car.get_slide_collision(collision_index)
			var collider := collision.get_collider() as Node
			var name := String(collider.get_path()) if collider != null else "unknown"
			if not collisions.has(name):
				collisions.append(name)
		if car.global_position.distance_to(destination) < 16.0:
			break
	Input.action_release("move_up")
	var final_position := car.global_position
	var distance := final_position.distance_to(start)
	_check(collisions.is_empty(), "%s bridge drive hit %s at %s" % [label, collisions, final_position])
	_check(final_position.distance_to(destination) < 20.0, "%s did not reach opposite shore: %s" % [label, final_position])
	_check(distance > 1380.0, "%s crossed insufficient real distance %.1f" % [label, distance])
	_check(absf(final_position.y - start.y) < 5.0, "%s was pushed outside its lane" % label)
	print("HARBOR_BRIDGE_DRIVE %s start=%s end=%s traveled=%.1f collisions=%s" % [label, start, final_position, distance, collisions])
	car.velocity = Vector2.ZERO


func _colliders(hits: Array[Dictionary]) -> String:
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
	Input.action_release("move_up")
	for failure in _failures:
		push_error("HARBOR_BRIDGE: " + failure)
	scene.queue_free()
	quit(0 if _failures.is_empty() else 1)
