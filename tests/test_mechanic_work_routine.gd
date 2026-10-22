extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("MECHANIC ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var place := preload("res://world/maciota/MaciotaPlace.gd").new()
	root.add_child(place)
	place.set_interior_active(true)
	var worker: CharacterBody3D = place.mechanic
	check(not worker.has_method("take_damage") and not worker.has_method("die"),"invulnerable resident has no damage/death path")
	# Simulate the full route, including two work pauses, using real physics.
	var visited := [false,false]
	var origin: Vector3 = worker.position
	var travelled := 0.0
	for frame in 1200:
		await physics_frame
		travelled += worker.position.distance_to(origin)
		origin = worker.position
		if worker.working: visited[worker.phase] = true
		if frame % 60 == 0:
			check(worker.position.x > -2.72 and worker.position.x < -2.58,"worker stays in free aisle")
			check(worker.position.y > -.04 and worker.position.y < .04,"worker stays on floor")
	check(visited[0] and visited[1] and travelled > 2.5,"walks between stations and works at both")
	check(place.interaction_points.mechanic.distance_to(worker.global_position) < 1.0,"conversation follows worker")
	# A player-sized solid in the aisle must stop him; no scripted teleport.
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	blocker.add_child(shape)
	place.room.add_child(blocker)
	blocker.position = Vector3(-2.65,0,-1.9)
	worker.position = Vector3(-2.65,0,-1.1)
	worker.phase = 1
	for frame in 180: await physics_frame
	check(worker.position.z > -1.6,"resident respects player-sized blocker")
	blocker.queue_free()
	place.set_interior_active(false)
	var stopped: Vector3 = worker.position
	for frame in 10: await physics_frame
	check(worker.position.is_equal_approx(stopped),"empty room stops work and movement")
	place.free()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
