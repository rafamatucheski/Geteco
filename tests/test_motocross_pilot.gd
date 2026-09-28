extends SceneTree
const PILOT := preload("res://activities/motocross/MotocrossPilot.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
class InputBike extends CharacterBody3D:
	var speed := 0.0
	var max_speed := 18.0
	var wetness := 0.0
	var grip_multiplier := 1.0
	var rider_name := "DecisionFixture"
	var crash_state := "riding"
	var throttle := 0.0
	var steering := 0.0
	var braking := false
	func drive(gas: float, steer: float, brake: bool) -> void:
		throttle = gas; steering = steer; braking = brake
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_PILOT ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var course := COURSE.new()
	world.add_child(course)
	var bike := InputBike.new()
	var lead := InputBike.new()
	var blocker := InputBike.new()
	world.add_child(bike); world.add_child(lead); world.add_child(blocker)
	bike.global_transform = course.pose(110)
	var row := {"bike": bike, "lane": 0.0, "pilot_seed": 18}
	PILOT.drive(row, course, [row], 17.0, 1.0 / 60.0)
	check(bike.throttle == 1.0 and not bike.braking, "an open straight produces full physical acceleration")
	bike.speed = 18.0
	bike.global_transform = course.pose(229)
	row = {"bike": bike, "lane": 0.0, "pilot_seed": 18}
	PILOT.drive(row, course, [row], 17.0, 1.0 / 60.0)
	check(bike.braking and float(row.pilot_state.target_speed) < 14.0, "fast approach to a hairpin commands real braking")
	bike.speed = 12.0
	bike.global_transform = course.pose(110)
	lead.speed = 5.0
	lead.global_transform = course.pose(116, 0)
	blocker.speed = 8.0
	blocker.global_transform = course.pose(113, -1.5)
	row = {"bike": bike, "lane": 0.0, "pilot_seed": 18}
	var neighbors := [row, {"bike": lead}, {"bike": blocker}]
	PILOT.drive(row, course, neighbors, 17.0, 1.0 / 60.0)
	check(int(row.pilot_state.pass_side) == 1 and float(row.pilot_state.lane_target) > 1.0, "a slower leader and occupied left lane cause a right-side pass")
	for index in 60:
		lead.global_transform = course.pose(116, sin(float(index) * 0.1) * 0.18)
		PILOT.drive(row, course, neighbors, 17.0, 1.0 / 60.0)
	check(int(row.pilot_state.pass_side) == 1 and int(row.pilot_state.overtake_attempts) == 1, "passing side stays committed instead of oscillating every frame")
	check(absf(float(row.lane)) <= COURSE.HALF_WIDTH - 1.35 and float(row.pilot_state.target_speed) <= bike.max_speed, "planned lane and speed remain within physical course limits")
	bike.crash_state = "fallen"
	PILOT.drive(row, course, neighbors, 17.0, 1.0 / 60.0)
	check(bike.throttle == 0.0 and bike.braking, "fallen riders stop issuing acceleration")
	bike.free(); lead.free(); blocker.free()
	var fast = BIKE.new()
	fast.rider_name = "Faísca"
	fast.max_speed = 17.0
	var slow = BIKE.new()
	slow.rider_name = "Lobo"
	slow.max_speed = 10.0
	world.add_child(fast); world.add_child(slow)
	fast.reset_to(course.pose(110, 0))
	slow.reset_to(course.pose(116, 0))
	var fast_row := {"bike": fast, "lane": 0.0, "pilot_seed": 312}
	var slow_row := {"bike": slow, "lane": 0.0, "pilot_seed": 710}
	var pack := [fast_row, slow_row]
	var previous_fast := 110.0
	var previous_slow := 116.0
	var fast_progress := 110.0
	var slow_progress := 116.0
	var passed_physically := false
	var maximum_lateral := 0.0
	for _i in 4800:
		PILOT.drive(fast_row, course, pack, 16.5, 1.0 / 60.0)
		PILOT.drive(slow_row, course, pack, 9.0, 1.0 / 60.0)
		await physics_frame
		var fast_nearest := course.nearest(fast.position)
		var slow_nearest := course.nearest(slow.position)
		fast_progress += wrapf(float(fast_nearest.distance) - previous_fast, -course.length * 0.5, course.length * 0.5)
		slow_progress += wrapf(float(slow_nearest.distance) - previous_slow, -course.length * 0.5, course.length * 0.5)
		previous_fast = float(fast_nearest.distance)
		previous_slow = float(slow_nearest.distance)
		maximum_lateral = maxf(maximum_lateral, float(fast_nearest.lateral))
		if fast_progress > slow_progress + 3.0: passed_physically = true
		if fast_progress >= 110.0 + course.length: break
	var state: Dictionary = fast_row.pilot_state
	print("MOTOCROSS_PILOT_TRACE progress=", fast_progress - 110.0, " lane_span=", float(state.lane_max) - float(state.lane_min), " speed_min=", state.min_target_speed, " speed_max=", state.max_target_speed, " brakes=", state.brake_frames, " acceleration=", state.accelerate_frames, " attempts=", state.overtake_attempts, " lateral=", maximum_lateral, " crashes=", fast.crash_count)
	check(passed_physically and int(state.overtake_attempts) > 0, "a faster physical rider overtakes the slower motorcycle")
	check(fast_progress >= 110.0 + course.length, "dynamic pilot completes the physical course without checkpoint teleporting")
	check(float(state.lane_max) - float(state.lane_min) > 1.5, "racing line changes visibly across the lap")
	check(int(state.brake_frames) > 5 and int(state.accelerate_frames) > 60, "a lap includes braking zones and repeated acceleration")
	check(float(state.max_target_speed) - float(state.min_target_speed) > 4.0, "straight and corner target speeds differ materially")
	check(maximum_lateral < COURSE.HALF_WIDTH, "dynamic racing stays inside the track")
	world.free()
	print("MOTOCROSS_PILOT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
