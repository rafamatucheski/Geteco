extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var roads: Array = []
	for y in range(-8, 9):
		var points := PackedVector2Array()
		for x in range(-16, 17): points.append(Vector2(x*80,y*90))
		roads.append({"points":points})
	for x in range(-8, 9):
		roads.append({"points":PackedVector2Array([Vector2(x*90,-900),Vector2(x*90,900)])})
	roads.append({"points":PackedVector2Array([Vector2(-1024,-1024),Vector2(1024,1024)])})
	var reference := preload("res://tests/StreetRouteReference.gd").new()
	var started := Time.get_ticks_usec()
	reference.build(roads)
	var reference_us := Time.get_ticks_usec()-started
	var optimized := preload("res://ui/StreetRoute.gd").new()
	started = Time.get_ticks_usec()
	optimized.build(roads)
	var optimized_us := Time.get_ticks_usec()-started
	assert(reference.points == optimized.points)
	assert(reference.edges == optimized.edges)
	for i in 20:
		var from := Vector2(-1000 + i*15, -600+i*30)
		var to := Vector2(800-i*7,600-i*15)
		assert(reference.route(from,to) == optimized.route(from,to))
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	for i in 150:
		var point := Vector2(rng.randf_range(-2200,2200),rng.randf_range(-2200,2200))
		var expected: Dictionary = reference._nearest_edge(point)
		for limit in [350.0,450.0]:
			var actual: Dictionary = optimized._nearest_edge(point,limit)
			assert(actual == expected if expected.distance <= limit else actual.is_empty())
	var incremental := preload("res://ui/StreetRoute.gd").new()
	await incremental.build(roads, self)
	assert(incremental.edges == optimized.edges)
	print("SPATIAL_ROUTE_RESULT baseline_us=%d optimized_us=%d segment_pairs=%d optimized_pairs=%d" % [reference_us,optimized_us,optimized.segments.size()*(optimized.segments.size()-1)/2,optimized.intersection_tests])
	quit(0)
