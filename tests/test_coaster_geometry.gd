extends SceneTree
const SITE = preload("res://world/places/amusement_park/ParkLume.gd")
const ACTOR = preload("res://scripts/Actor.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("COASTER_GEOMETRY ","PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func run() -> void:
	var site := SITE.new()
	root.add_child(site)
	var length := site.coaster_length()
	var count := ceili(length/.25)
	var paths: Array[PackedVector2Array] = []
	var inside := true
	var smooth := true
	var minimum_dot := 1.0
	var sharp_at := 0.0
	var high := 0.0
	var low := INF
	for lateral in [-.64,0,.64]:
		var points := PackedVector2Array()
		for i in count:
			var pose := site.sample_coaster(length*i/count)
			var point := site.to_local(pose.origin+pose.basis.x*lateral)
			points.append(Vector2(point.x,point.z))
			high = maxf(high,point.y)
			low = minf(low,point.y)
			inside = inside and Rect2(-36,-29,30,51).has_point(Vector2(point.x,point.z))
			var dot := pose.basis.z.dot(site.sample_coaster(length*(i+1)/count).basis.z)
			if dot < minimum_dot:
				minimum_dot = dot
				sharp_at = length*i/count
			smooth = smooth and dot>.97
		paths.append(points)
	var crossings := 0
	for path in paths:
		for i in count:
			for j in range(i+2,count):
				if i==0 and j==count-1: continue
				if Geometry2D.segment_intersects_segment(path[i],path[(i+1)%count],path[j],path[(j+1)%count]) != null: crossings += 1
	# Left/right rails must not cut each other, including in tight turns.
	for i in count:
		for j in count:
			if Geometry2D.segment_intersects_segment(paths[0][i],paths[0][(i+1)%count],paths[2][j],paths[2][(j+1)%count]) != null: crossings += 1
	check(crossings==0,"centerline and both rails have zero XZ crossings (%d)"%crossings)
	check(inside,"complete rail width stays clear of perimeter fence")
	check(smooth,"dense sampling has no tangent flips or abrupt corners (dot %.4f at %.2fm)"%[minimum_dot,sharp_at])
	check(length>120 and high>12 and low>.15,"full circuit preserves climb/descent above ground: %.2fm, %.2f..%.2fm"%[length,low,high])
	var before := site.sample_coaster(length-.02)
	var after := site.sample_coaster(.02)
	check(before.origin.distance_to(after.origin)<.05 and before.basis.z.dot(after.basis.z)>.999,"station seam has continuous position and tangent on either side")
	var actor := ACTOR.new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.collision_mask = 1
	for i in 3: await physics_frame
	var dock := site.sample_coaster(0)
	var at := Transform3D(Basis.IDENTITY,Vector3(dock.origin.x+1.8,.50,dock.origin.z+.35))
	site.set_boarding_open(0)
	await physics_frame
	check(actor.test_move(at,Vector3.LEFT*1.8),"closed gate blocks body above the boarding step")
	site.set_boarding_open(1)
	await physics_frame
	check(not actor.test_move(at,Vector3.LEFT*1.8),"opened gate admits a full capsule across the explicit boarding step")
	site.set_boarding_open(0)
	await physics_frame
	check(actor.test_move(at,Vector3.LEFT*1.8),"gate restores collision after disembark")
	var visitor := ACTOR.new()
	visitor.is_player = false
	root.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.collision_mask = 1
	await physics_frame
	check(visitor.test_move(at,Vector3.LEFT*1.8),"closed gate also blocks an NPC capsule")
	site.set_boarding_open(1)
	await physics_frame
	check(not visitor.test_move(at,Vector3.LEFT*1.8),"open gate has full NPC clearance")
	print("COASTER_GEOMETRY_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
