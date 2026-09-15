extends SceneTree

const SUPPRESSION := preload("res://emergency/FireSuppression.gd")
var failures: Array[String] = []
var scene: Node2D

class Fire extends Node2D:
	var is_exploding := true
	var completed := 0
	func extinguish_fire() -> void:
		completed += 1
		is_exploding = false

class Truck extends CharacterBody2D:
	var _response_crew: Array = []
	var is_returning_to_base := false
	var is_heading_to_cemetery := false
	var is_broken := false
	var targets: Array = []
	func add_service_target(target: Node2D) -> void:
		if not targets.has(target): targets.append(target)

class Director extends Node:
	var calls := 0
	var truck: Node2D
	func _dispatch_unbatched(_service: String, _target: Node2D, _force: bool) -> Node2D:
		calls += 1
		return truck

class Wreck extends Node2D:
	var is_exploded := true
	var is_exploding := false
	var is_broken := true
	var health := 0
	var flame_particles := CPUParticles2D.new()
	var smoke_emitter := CPUParticles2D.new()
	func _ready() -> void:
		add_child(flame_particles)
		add_child(smoke_emitter)
	func _dispatch_fire_truck() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures.append(label)

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("FIRE_COOPERATION TIMEOUT"); quit(2))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	# The shared incident must not be closed by the first short burst of water.
	var fire := Fire.new()
	scene.add_child(fire)
	check(not SUPPRESSION.apply_water(fire, 1.2), "Short burst cools fire without completing it")
	check(is_equal_approx(float(fire.get_meta(SUPPRESSION.PROGRESS_META)), 0.25), "Cooling persists on incident during interruption")
	check(not SUPPRESSION.apply_water(fire, 1.2), "Second hose adds to first hose work")
	check(SUPPRESSION.apply_water(fire, 2.5), "Combined water completes fire")
	SUPPRESSION.apply_water(fire, 2.0)
	check(fire.completed == 1 and fire.get_meta("service_complete", false), "Completion is idempotent and closes incident")
	fire.queue_free()
	# Real physics rays stop water when a wall appears between firefighter and fire.
	fire = Fire.new()
	fire.position = Vector2(50, 0)
	scene.add_child(fire)
	var firefighter = load("res://emergency/Firefighter.tscn").instantiate()
	scene.add_child(firefighter)
	firefighter.set_physics_process(false)
	firefighter.target = fire
	firefighter.state = firefighter.State.EXTINGUISH
	await physics_frame
	firefighter._physics_process(0.5)
	var progress := float(fire.get_meta(SUPPRESSION.PROGRESS_META, 0.0))
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 160)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(25, 0)
	scene.add_child(wall)
	await physics_frame
	firefighter._physics_process(0.5)
	check(firefighter.state == firefighter.State.APPROACH and not firefighter.water_hose.emitting, "Wall interrupts hose and triggers repositioning")
	check(is_equal_approx(float(fire.get_meta(SUPPRESSION.PROGRESS_META, 0.0)), progress), "No water crosses the wall; previous cooling survives")
	firefighter._approach_elapsed = firefighter.APPROACH_TIMEOUT
	firefighter._physics_process(0.1)
	check(firefighter.state == firefighter.State.RETURN and SUPPRESSION.is_active(fire), "Inaccessible fire releases crew without pretending completion")
	check(int(fire.get_meta("fire_retry_after_ms", 0)) > Time.get_ticks_msec(), "Blocked fire delays replacement truck")
	wall.queue_free()
	firefighter.queue_free()
	fire.queue_free()
	await physics_frame
	# Distinct approach stations and simultaneous work with the actual NPC loop.
	fire = Fire.new()
	fire.position = Vector2(500, 0)
	scene.add_child(fire)
	var truck := Truck.new()
	truck.position = Vector2(380, 0)
	scene.add_child(truck)
	for side in [-1.0, 1.0]:
		var member = load("res://emergency/Firefighter.tscn").instantiate()
		member.target = fire
		member.crew_side = side
		member.position = Vector2(440, side * 25)
		scene.add_child(member)
		member.set_physics_process(false)
		# The lightweight truck supplies the real crew list used for reservations.
		member.fire_truck = truck
		truck._response_crew.append(member)
	await physics_frame
	var first: Node = truck._response_crew[0]
	var second: Node = truck._response_crew[1]
	var first_post: Vector2 = first._fire_service_position(0.1)
	var second_post: Vector2 = second._fire_service_position(0.1)
	check(first_post.distance_to(second_post) >= 22.0, "Two firefighters reserve separate working positions")
	for frame in 230:
		for member in truck._response_crew:
			if member.state in [member.State.APPROACH, member.State.EXTINGUISH]: member._physics_process(1.0 / 60.0)
		await physics_frame
		if fire.completed > 0: break
	check(fire.completed == 1, "Two real responders reach stations and jointly extinguish")
	# Queue handles null, groups nearby fires, and releases completed jobs.
	var director := Director.new()
	director.truck = truck
	scene.add_child(director)
	var queue := preload("res://emergency/ServiceIncidents.gd").new()
	queue.director = director
	scene.add_child(queue)
	queue.set_process(false)
	check(queue.request("fire", null) == null, "Invalid request is ignored safely")
	var fire_a := Fire.new()
	var fire_b := Fire.new()
	scene.add_child(fire_a)
	scene.add_child(fire_b)
	fire_b.position = Vector2(100, 0)
	queue.request("fire", fire_a)
	queue.request("fire", fire_b)
	queue.request("fire", fire_a)
	check(director.calls == 1 and queue.incidents.size() == 1 and truck.targets.size() == 2, "Nearby and repeated calls share one truck")
	SUPPRESSION.apply_water(fire_a, 5.0)
	SUPPRESSION.apply_water(fire_b, 5.0)
	queue._process(1.1)
	check(queue.incidents.is_empty(), "Completed incident is removed instead of redispatched")
	var world_fire := preload("res://world/harbor/events/WorldFire.gd").new()
	world_fire.position = Vector2(1000, 500)
	scene.add_child(world_fire)
	await physics_frame
	var ray := PhysicsRayQueryParameters2D.create(Vector2(940, 500), world_fire.position, 1 | 2 | 4)
	var hit := world_fire.get_world_2d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider") == world_fire, "Burning bin has a physical footprint targetable by water cannon")
	SUPPRESSION.apply_water(world_fire, 5.0)
	check(world_fire.get_meta("service_complete", false) and not world_fire.flames.emitting, "World fire closes incident and disables flames")
	var wreck := Wreck.new()
	scene.add_child(wreck)
	var residual_script := preload("res://emergency/VehicleResidualFire.gd")
	residual_script.start(wreck)
	check(SUPPRESSION.is_active(wreck) and wreck.flame_particles.emitting, "Explosion wreck stays available for firefighter response")
	var cannon := preload("res://emergency/VehicleWaterCannon.gd").new()
	for pulse in 6: cannon._apply_hit(wreck)
	check(is_equal_approx(float(wreck.get_meta(SUPPRESSION.PROGRESS_META, 0.0)), 0.25), "Player water cannon cools the same shared incident")
	SUPPRESSION.apply_water(wreck, 3.7)
	check(not wreck.flame_particles.emitting and not SUPPRESSION.is_active(wreck), "Water extinguishes residual fire")
	check(wreck.is_exploded and wreck.is_broken and wreck.health == 0, "Fire service never repairs a wreck or restarts detonation")
	cannon.free()
	wreck.queue_free()
	wreck = Wreck.new()
	scene.add_child(wreck)
	residual_script.start(wreck)
	var cooling := wreck.get_node("ResidualFire")
	cooling._process(60.1)
	check(not SUPPRESSION.is_active(wreck) and wreck.get_meta("service_complete", false), "Residual fire has finite lifetime and closes naturally")
	wreck.queue_free()
	wreck = Wreck.new()
	scene.add_child(wreck)
	residual_script.start(wreck)
	wreck.is_exploded = false
	wreck.get_node("ResidualFire")._process(0.3)
	check(not wreck.flame_particles.emitting, "Repair cancels old residual fire")
	scene.queue_free()
	await process_frame
	print("FIRE_COOPERATION: ", failures)
	quit(0 if failures.is_empty() else 1)
