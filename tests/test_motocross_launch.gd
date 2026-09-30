extends SceneTree
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const PILOT := preload("res://activities/motocross/MotocrossPilot.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func verify(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var course := COURSE.new(); root.add_child(course)
	course.finish_build()
	var bike := BIKE.new(); root.add_child(bike)
	bike.max_speed = 17
	bike.reset_to(course.pose(course.length*.32))
	for i in 5: await physics_frame
	bike.speed = 15
	bike._planar_velocity = -bike.global_basis.z*15
	var row := {"bike":bike,"lane":0.0}
	var clearance := 0.0; var rising := 0.0; var flight := 0.0
	var launched := false; var landed := false; var compression := 0.0
	for i in 900:
		PILOT.drive(row,course,[row],16.0,1.0/60.0)
		await physics_frame
		if not bike.is_on_floor():
			launched = launched or bike.jump_count>0
			rising = maxf(rising,bike.velocity.y)
			flight = maxf(flight,bike._air_time)
			var query := PhysicsRayQueryParameters3D.create(bike.global_position+Vector3.UP*.1,bike.global_position-Vector3.UP*12,1)
			var hit := bike.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty(): clearance = maxf(clearance,bike.global_position.y-float(hit.position.y))
		elif launched:
			landed = true
			compression = minf(compression,bike._suspension)
	verify(bike.jump_count>0 and rising>1.5,"ramp crest retains real upward velocity")
	verify(clearance>.35 and flight>.25,"launch visibly clears the real physical ramp")
	verify(landed and compression<-.01,"landing compresses the rider suspension")
	verify(bike.crash_count<=1,"normal ramp landing remains playable")
	print("MOTOCROSS_LAUNCH_RESULT checks=4 failures=",failures," jumps=",bike.jump_count," height=",clearance," rising=",rising," flight=",flight," compression=",compression)
	bike.free(); course.free()
	quit(0 if failures.is_empty() else 1)
