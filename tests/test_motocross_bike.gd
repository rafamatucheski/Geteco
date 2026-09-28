extends SceneTree
## Real collision/driver regression: no personal save, game session or FPS claim.
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const CONTROLLER := preload("res://activities/motocross/Motocross.gd")
const EFFECTS := preload("res://activities/motocross/MotocrossSurfaceEffects.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_BIKE ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var bike = BIKE.new()
	world.add_child(bike)
	await frames(20)
	check(bike.is_on_floor() and absf(bike.position.y) < 0.035, "tires rest on real ground")
	bike.drive(1, 0)
	await frames(90)
	check(bike.speed > 8 and bike.position.z < -5, "explicit shared input accelerates toward -Z")
	var dry_acceleration_speed: float = bike.speed
	bike.drive(0, 0, true)
	await frames(80)
	check(absf(bike.speed) < 0.1, "braking stops the bike")
	bike.drive(1, 0)
	await frames(45)
	bike.crash(0.8)
	check(bike.health < 100 and bike.health >= 15 and bike.crash_state == "fallen", "crash injures and detaches rider without death")
	var states := {}
	for _i in 600:
		states[bike.crash_state] = true
		await physics_frame
		if bike.crash_state == "riding": break
	check(states.has("standing") and states.has("returning") and states.has("mounting"), "injured rider gets up walks back and mounts")
	check(bike.crash_state == "riding", "recovery completes without controller teleport")
	for _i in 12:
		bike.crash(1)
		bike.reset_to(Transform3D(Basis.IDENTITY, Vector3(8, 0.1, 8)))
	check(bike.health == 15 and bike.speed == 0, "repeated falls stay nonfatal and checkpoint clears speed")
	bike.wetness = 1.0
	bike.drive(1, 0)
	await frames(90)
	check(bike.speed < dry_acceleration_speed * 0.85, "heavy mud measurably reduces acceleration")
	bike.max_speed = 0.0
	bike.reset_to(Transform3D(Basis.IDENTITY, Vector3(8, 0.1, 8)))
	await frames(10)
	check(bike.position.is_finite() and bike.rotation.is_finite(), "zero maximum speed cannot poison physics with NaN")
	bike.free()
	floor_body.free()
	var course = COURSE.new()
	world.add_child(course)
	await frames(4)
	var surface_misses := 0
	for index in 20:
		var sample: Vector3 = course.sample(course.length * float(index) / 20.0)
		var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 3, sample - Vector3.UP * 2, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or absf(float(hit.position.y) - sample.y) > 0.08: surface_misses += 1
	check(surface_misses == 0, "course ribbon collision faces upward at 20 checkpoints")
	bike = BIKE.new()
	bike.max_speed = 14.0
	world.add_child(bike)
	bike.reset_to(course.pose(0))
	await frames(20)
	var previous := 0.0
	var progress := 0.0
	var maximum_lateral := 0.0
	var highest := 0.0
	var airborne_frames := 0
	var seconds := 0.0
	for _i in 7200:
		var near: Dictionary = course.nearest(bike.global_position)
		var distance: float = near.distance
		progress += wrapf(distance - previous, -course.length * 0.5, course.length * 0.5)
		previous = distance
		maximum_lateral = maxf(maximum_lateral, near.lateral)
		highest = maxf(highest, bike.global_position.y)
		if not bike.is_on_floor(): airborne_frames += 1
		var target: Vector3 = course.sample(distance + 4.0)
		var toward: Vector3 = target - bike.global_position
		var desired := atan2(-toward.x, -toward.z)
		var error := angle_difference(bike.rotation.y, desired)
		var target_speed := lerpf(13.0, 6.0, clampf(absf(error) / 0.8, 0.0, 1.0))
		bike.drive(target_speed / bike.max_speed, clampf(error * 1.8, -1, 1), false)
		await physics_frame
		seconds += 1.0 / 60.0
		if progress >= course.length - 1.0: break
		if bike.global_position.y < -5.0: break
	print("MOTOCROSS_BIKE_ROUTE length=", course.length, " progress=", progress, " seconds=", seconds, " lateral=", maximum_lateral, " peak=", highest, " air_frames=", airborne_frames, " crashes=", bike.crash_count, " position=", bike.global_position)
	check(progress >= course.length - 1.0, "AI completes a whole physical circuit within 120 seconds")
	check(maximum_lateral < course.HALF_WIDTH, "AI remains within circuit width through turns")
	check(highest > 11.0 and airborne_frames > 0, "rider physically climbs and leaves ramp surfaces")
	check(bike.crash_count <= 2, "normal racing does not produce repeated unavoidable crashes")
	bike.free()
	var controller := CONTROLLER.new()
	world.add_child(controller)
	var effects := EFFECTS.new()
	effects.configure(course)
	world.add_child(effects)
	var mud_seen := false
	for scenario in [Vector2(0, 0), Vector2(3, 0), Vector2(3, 1)]:
		var level := int(scenario.x)
		var surface_wetness: float = scenario.y
		controller.difficulty = level
		var spec: Dictionary = controller.PROGRESS.LEVELS[level]
		var opponents: Array = []
		for index in int(spec.rivals) + 1:
			var opponent = BIKE.new()
			opponent.wetness = surface_wetness
			opponent.max_speed = 18.0 if index == 0 else (float(spec.speed)+1.0) * (1.0 - float(index - 1) * 0.022)
			opponent.rider_name = ["Dante","Faísca","Lobo","Nina","Beto","Iara"][index]
			world.add_child(opponent)
			opponent.reset_to(course.pose(-float(index / 2) * 3.5, -1.4 if index % 2 == 0 else 1.4))
			opponents.append({"bike": opponent, "lane": -0.9 if index % 2 == 0 else 0.9, "previous": opponent.position, "gate": 1, "passed": 0})
		controller.racers = opponents
		await frames(20)
		var finished := 0
		var opponent_crashes := 0
		for _i in 7200:
			finished = 0
			effects.update_riders(opponents, surface_wetness)
			for slot in effects._emitters:
				if slot.mud.emitting: mud_seen = true
			for row in opponents:
				controller._drive_ai(row)
				var target: Vector3 = course.gates[int(row.gate)]
				var previous_position: Vector3 = row.previous
				var current: Vector3 = row.bike.position
				var crossing := Geometry3D.get_closest_point_to_segment(target, previous_position, current)
				var forward: Vector3 = course.sample(float(row.gate) * course.length / course.gates.size() + 1) - target
				if current.distance_to(previous_position) <= 3 and row.bike.crash_state == "riding" and crossing.distance_to(target) < 5.6 and (current - previous_position).dot(forward) > 0:
					row.passed += 1
					row.gate = (int(row.gate) + 1) % course.gates.size()
				row.previous = current
				if row.passed >= 32: finished += 1
			await physics_frame
			if finished == opponents.size(): break
		for row in opponents: opponent_crashes += row.bike.crash_count
		print("MOTOCROSS_BIKE_PACK level=", level, " wetness=", surface_wetness, " finished=", finished, " count=", opponents.size(), " crashes=", opponent_crashes)
		check(finished == opponents.size(), "%d actual controller racers cross all 32 gates together (wetness %.1f)" % [opponents.size(), surface_wetness])
		controller.racers = []
		for row in opponents: row.bike.free()
	check(effects.mark_count > 100 and effects.mark_count <= 2048, "physical tire marks use a bounded shared ring")
	check(effects._emitters.size() <= 6 and mud_seen, "rain switches on bounded brown mud spray")
	await frames(10)
	var stopped := true
	for slot in effects._emitters:
		if slot.dust.emitting or slot.mud.emitting: stopped = false
	check(stopped, "surface emitters stop after race participants disappear")
	world.free()
	print("MOTOCROSS_BIKE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
