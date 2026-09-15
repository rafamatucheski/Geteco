extends SceneTree
const Flow := preload("res://world/shared/traffic/TrafficFlowModel.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(3000,0))
	world.add_child(path)
	var actors: Array[Node] = []
	for i in 301:
		var actor := Node2D.new()
		actor.position = Vector2(10000+i*50,10000) if i > 0 else Vector2(400,0)
		var hull := CollisionShape2D.new()
		hull.name = "Collision"
		hull.shape = RectangleShape2D.new()
		hull.shape.size = Vector2(74,28)
		actor.add_child(hull)
		world.add_child(actor)
		actors.append(actor)
	var entrant := Node2D.new()
	world.add_child(entrant)
	var success := true
	var start := Time.get_ticks_usec()
	for i in 1000:
		success = success and Flow.exit_blocker(entrant,path,350,450,actors) == actors[0]
	var cost := (Time.get_ticks_usec()-start)/1000.0
	# Reverse the iteration order too: distant actors must not change the result.
	actors.reverse()
	start = Time.get_ticks_usec()
	for i in 1000:
		success = success and Flow.exit_blocker(entrant,path,350,450,actors) == actors.back()
	var cost_last := (Time.get_ticks_usec()-start)/1000.0
	print("CITY_TRAFFIC_QUERY_COST actors=301 queries=2000 first_blocker_mean_us=",cost," last_blocker_mean_us=",cost_last," correct=",success)
	world.queue_free()
	await process_frame
	quit(0 if success else 1)
