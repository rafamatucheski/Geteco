extends SceneTree
const NAV := preload("res://ResponderNavigation.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var wall := StaticBody2D.new()
	wall.position = Vector2(75, 0)
	var wall_shape := CollisionShape2D.new()
	wall_shape.shape = RectangleShape2D.new()
	wall_shape.shape.size = Vector2(28, 240)
	wall.add_child(wall_shape)
	world.add_child(wall)
	var actors: Array[CharacterBody2D] = []
	var searches: Array = []
	var completed := {}
	for i in 24:
		var actor := CharacterBody2D.new()
		actor.collision_layer = 0
		actor.collision_mask = 1
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 11.0
		actor.add_child(shape)
		world.add_child(actor)
		actors.append(actor)
		searches.append(NAV.new())
	await physics_frame
	await physics_frame
	var max_work_usec := 0
	var frames := 0
	var safe := true
	for frame in 300:
		await process_frame
		frames += 1
		for i in searches.size():
			if completed.has(i): continue
			var route: Array[Vector2] = searches[i]._plan(actors[i], Vector2(180, 0))
			if route.is_empty(): continue
			var previous := actors[i].global_position
			for point in route:
				safe = safe and searches[i].clear_segment(actors[i], previous, point)
				previous = point
			completed[i] = true
		max_work_usec = maxi(max_work_usec, NAV._work_usec)
		if completed.size() == searches.size(): break
	print("NAVIGATION_WORK_BUDGET completed=", completed.size(), "/24 safe=", safe, " frames=", frames, " peak_search_us=", max_work_usec)
	# A queued requester that disappears must not prevent later work.
	searches.clear()
	NAV._work_usec = NAV.SEARCH_FRAME_USEC
	var abandoned := NAV.new()
	abandoned._plan(actors[0], Vector2(180, 0))
	var freed := NAV.new()
	freed._plan(actors[1], Vector2(180, 0))
	freed = null
	var replacement := NAV.new()
	var resumed := false
	for frame in 100:
		await process_frame
		if not replacement._plan(actors[0], Vector2(180, 0)).is_empty():
			resumed = true
			break
	print("NAVIGATION_WORK_BUDGET replacement_progress=", resumed)
	world.free()
	quit(0 if completed.size() == 24 and safe and resumed else 1)
