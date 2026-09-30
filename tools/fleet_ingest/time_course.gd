extends SceneTree
func _initialize() -> void: run.call_deferred()
func brute(c, point: Vector3) -> Dictionary:
	var best := INF
	var distance := 0.0
	for i in range(c.points.size()-1):
		var a := Vector2(c.points[i].x,c.points[i].z)
		var b := Vector2(c.points[i+1].x,c.points[i+1].z)
		var p := Vector2(point.x,point.z)
		var t := clampf((p-a).dot(b-a)/maxf(.001,(b-a).length_squared()),0,1)
		var d := p.distance_squared_to(a.lerp(b,t))
		if d < best:
			best = d
			distance = (float(i)+t)/float(c.points.size()-1)*c.length
	return {"lateral": sqrt(best), "distance": distance}
func run() -> void:
	var c := preload("res://activities/motocross/MotocrossCourse.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var mismatched := 0
	for i in 600:
		var p := Vector3(rng.randf_range(-260, -80), 0, rng.randf_range(-170, -20))
		var a: Dictionary = c.nearest(p)
		var b: Dictionary = brute(c, p)
		worst = maxf(worst, absf(float(a.lateral) - float(b.lateral)))
		if absf(float(a.lateral) - float(b.lateral)) > 0.001: mismatched += 1
	print("NEAREST_EQUIV mismatched=", mismatched, " worst_lateral_diff=", worst)
	var t := Time.get_ticks_usec()
	root.add_child(c)
	c.finish_build()
	print("COURSE_MS total=", float(Time.get_ticks_usec()-t)/1000.0, " ", Engine.get_meta("motocross_build_ms", null))
	quit()
