extends SceneTree
## Main + native pavement + live vehicle physics. --no-save is mandatory.
## Samples theft and exit, including a real rear-end impact before the theft.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const OUTPUT := "res://evidence/video-review-20260924/"
var world
var failures: Array[String] = []
var checks := 0
var cases: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var report_name := "phase3-vehicle-before.json"
var selected_cases: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_name = arg.trim_prefix("--report=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main is ready")
	if not failures.is_empty(): await finish(); return
	world.production.set_population(0)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.driving.car.hide()
	world.driving.car.collision_layer = 0
	world.driving.car.set_physics_process(false)
	world.player.teleport(Vector3(30, .05, 110))
	world.production._update_physical_residency(world.player.global_position)
	await frames(30)
	for row in [
		{"name":"stopped_coupe", "id":"sport_coupe", "speed":0.0, "crash":false, "delay":0},
		{"name":"moving_sedan", "id":"union_sedan", "speed":7.0, "crash":false, "delay":0},
		{"name":"fresh_impact_coupe", "id":"sport_coupe", "speed":0.0, "crash":true, "delay":0},
		{"name":"recovering_impact_coupe", "id":"sport_coupe", "speed":0.0, "crash":true, "delay":72},
	]:
		if not selected_cases.is_empty() and row.name not in selected_cases: continue
		await run_case(row)
	await finish()

func spawn(id: String, point: Vector3) -> CharacterBody3D:
	var car: CharacterBody3D = world.production.spawn_vehicle(id, point, 0.0)
	if is_instance_valid(car):
		car.vehicle_id = "phase3_" + str(Time.get_ticks_usec())
		car.paint_color = Color.WHITE
	return car

func run_case(row: Dictionary) -> void:
	var label: String = row.name
	world.player.teleport(Vector3(30, .05, 110))
	var car := spawn(row.id, Vector3(26.7, .12, 109.0))
	check(is_instance_valid(car), label + ": admitted on real Westgate pavement")
	if not is_instance_valid(car): return
	await frames(20)
	check(car.is_on_floor(), label + ": floor contact before theft")
	car.traffic = true
	car.set_meta("ambient_traffic", true)
	if row.crash:
		var striking := spawn("sport_coupe", car.global_position + Vector3(0, .12, 7))
		check(is_instance_valid(striking), label + ": striking vehicle admitted")
		if not is_instance_valid(striking): car.queue_free(); await frames(2); return
		striking.set_external_driver(true)
		striking.speed = 12.0
		striking.horizontal_velocity = Vector3(0, 0, -12)
		for frame in 120:
			await physics_frame
			if car.has_meta("crash_stun"): break
		check(car.has_meta("crash_stun") and car.health < car.max_health, label + ": real body collision produces a crash")
		striking.queue_free()
		await frames(1 + int(row.delay))
	else:
		car.speed = row.speed
		car.horizontal_velocity = Vector3(0, 0, -float(row.speed))
	var prior := {"traffic":car.traffic,"ambient":car.get_meta("ambient_traffic",false),"stun":car.get_meta("crash_stun",0),"slide":str(car.get_meta("crash_slide",Vector3.ZERO)),"position":str(car.global_position)}
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .20)
	var baseline: Vector3 = world.player.visual.position
	var admitted: bool = world.driving.interact(true)
	check(admitted and world.driving.car == car, label + ": normal interaction starts theft")
	if not admitted:
		car.queue_free(); await frames(2); return
	var outcome := await observe(car, label, "entry", 180)
	check(not world.driving.is_body_transition_active() and world.driving.occupied, label + ": entry completes")
	check(not car.traffic and not car.has_meta("ambient_traffic"), label + ": stolen vehicle never returns to ambient ownership")
	check(not outcome.traffic_resumed, label + ": traffic AI never resumes during boarding")
	check(car.is_physics_processing() and outcome.airborne_frames == 0, label + ": physics and actual floor contact remain active")
	check(outcome.min_y > -.25 and outcome.max_y < .3, label + ": vehicle remains at road height")
	check(outcome.max_step < .8, label + ": no frame teleport")
	check(outcome.max_anchor_error < .1, label + ": boarding seat stays attached to moving vehicle")
	check(world.player.visual.position.is_equal_approx(baseline), label + ": boarding leaves no vertical body offset")
	if label == "stopped_coupe":
		# A handoff clears old momentum, without disabling future physical impacts.
		var striking := spawn("sport_coupe", car.global_position + Vector3(0, .12, 7))
		check(is_instance_valid(striking), label + ": post-theft collision fixture admitted")
		if is_instance_valid(striking):
			var health_before: float = car.health
			striking.set_external_driver(true)
			striking.speed = 12.0
			striking.horizontal_velocity = Vector3(0, 0, -12)
			for frame in 120:
				await physics_frame
				if car.health < health_before: break
			check(car.health < health_before and car.has_meta("crash_slide"), label + ": new real impact still damages and pushes occupied car")
			striking.queue_free()
			await frames(90)
			check(car.is_on_floor() and car.is_physics_processing() and not car.traffic, label + ": occupied car stays grounded and player-owned after impact")
	car.stop_boarding_motion()
	var exited: bool = world.driving.leave()
	check(exited, label + ": exit admitted")
	var exit_outcome := await observe(car, label, "exit", 160)
	check(not world.driving.occupied and not world.driving.is_body_transition_active(), label + ": exit completes")
	check(world.player.visible and world.player.collision_mask == 7 and world.player.visual.position.is_equal_approx(baseline), label + ": visible physical player restored without residue")
	check(exit_outcome.min_y > -.25 and exit_outcome.max_y < .3, label + ": exit preserves vehicle height")
	for hinge in car.door_presentation.hinges.values():
		check(absf(hinge.rotation.y) < .001, label + ": door closed")
		if not car.door_presentation.coupe_ready: check(not hinge.visible, label + ": substitute leaf hidden")
	cases.append({"name":label,"before":prior,"entry":outcome,"exit":exit_outcome})
	world.player.teleport(Vector3(30, .05, 110))
	car.queue_free()
	await frames(3)

func observe(car: CharacterBody3D, label: String, phase: String, count: int) -> Dictionary:
	var outcome := {"min_y":INF,"max_y":-INF,"max_step":0.0,"max_anchor_error":0.0,"traffic_resumed":false,"airborne_frames":0}
	var previous: Vector3 = car.global_position
	for frame in count:
		await physics_frame
		if not is_instance_valid(car): check(false, label + ": car removed during " + phase); break
		outcome.min_y = minf(outcome.min_y, car.global_position.y)
		outcome.max_y = maxf(outcome.max_y, car.global_position.y)
		outcome.max_step = maxf(outcome.max_step, car.global_position.distance_to(previous))
		outcome.traffic_resumed = outcome.traffic_resumed or car.traffic
		if not car.is_on_floor(): outcome.airborne_frames += 1
		previous = car.global_position
		var transition = world.driving.transition
		if is_instance_valid(transition):
			outcome.max_anchor_error = maxf(outcome.max_anchor_error, transition._seat.distance_to(car.driver_seat_anchor()))
		if frame % 3 == 0:
			samples.append({"case":label,"phase":phase,"frame":frame,"car":[car.global_position.x,car.global_position.y,car.global_position.z],"player":[world.player.global_position.x,world.player.global_position.y,world.player.global_position.z],"speed":car.speed,"floor":car.is_on_floor(),"traffic":car.traffic,"crash_slide":str(car.get_meta("crash_slide",Vector3.ZERO)),"body_transition":world.driving.is_body_transition_active()})
		if frame == 20 or frame == count - 1: await capture_state(car, label, phase, frame)
	return outcome

func capture_state(_car: CharacterBody3D, _label: String, _phase: String, _frame: int) -> void:
	pass

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + report_name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"samples":samples,"type":"Main functional physics, not FPS benchmark"}, "\t"))
	file.close()
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	print("VIDEO_PHASE3_VEHICLE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
