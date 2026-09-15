extends SceneTree
## Real Harbor PlayerCar, unchanged controller, only Input actions after staging.
const CONTROLLER = preload("res://world/harbor/campaign/CobraCampaignController.gd")
const STATE = preload("res://world/harbor/campaign/CobraCampaignState.gd")
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func run() -> void:
	seed(63421)
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 12:
		await physics_frame
	var player = scene.get_node("Player")
	var car = scene.get_node("PlayerCar")
	var state = STATE.new()
	state.bind(null)
	state.data.completed["cobra_contact"] = true
	var controller = CONTROLLER.new()
	scene.add_child(controller)
	controller.configure(player, state, scene.get_node_or_null("CobraTerritory"))
	# The organizer closes the track while Dante is still away from it, as
	# happens when accepting at Maciota's garage. Every ambient car exits by
	# driving its real lane; no fleet member is deleted or relocated by test.
	check(controller.start_mission("cobra_race"), "race preparation begins")
	var clearing_positions: Dictionary = {}
	var clearing_cars: Array[Node2D] = []
	for actor in get_nodes_in_group("modern_traffic"):
		if actor is Node2D and absf(actor.global_position.distance_to(controller.CENTER)-controller.RACE_RADIUS) < controller.RACE_HALF_WIDTH + 25.0:
			clearing_cars.append(actor)
			clearing_positions[actor.get_instance_id()] = actor.global_position
	var clearing_max_step := 0.0
	var clearing_travel := 0.0
	var last_preparation_report := 0.0
	var preparation_deadline := Time.get_ticks_msec() + 200000
	while not controller.active_id.is_empty() and is_instance_valid(controller._race_traffic) and not controller._race_traffic.is_clear() and Time.get_ticks_msec() < preparation_deadline:
		await physics_frame
		if is_instance_valid(controller._race_traffic) and controller._race_traffic.elapsed > last_preparation_report + 15.0:
			last_preparation_report = controller._race_traffic.elapsed
			for actor in get_nodes_in_group("vehicle"):
				if actor is Node2D and actor.get("is_driven_by_player") != true and controller._race_traffic.blocks_route(actor):
					print("RACE_WAIT t=%.1f remaining=%d car=%s at=%s health=%s speed=%s lane=%s" % [last_preparation_report, controller._race_traffic.remaining, actor.name, actor.global_position, actor.get("health"), actor.get("_lane_motion_speed"), actor.get_parent().get_parent().name])
					if actor.name in ["HarborTraffic_03", "HarborTraffic_06"]:
						print("RACE_BLOCK_CONTRACT car=%s contract=%s planned=%s" % [actor.name, actor.get("_last_lane_motion_contract"), actor.get_parent().get_meta("traffic_planned_connection_id", "")])
						for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
							var ray := actor.get_node_or_null(ray_name) as RayCast2D
							if ray != null and ray.is_colliding():
								print("RACE_BLOCK_RAY car=%s ray=%s hit=%s" % [actor.name, ray_name, ray.get_collider().get_path()])
			if OS.get_cmdline_user_args().has("--debug-race-clearance"):
				scene.queue_free()
				await process_frame
				quit(2)
				return
		for actor in clearing_cars:
			if not is_instance_valid(actor): continue
			var key := actor.get_instance_id()
			var step: float = actor.global_position.distance_to(clearing_positions[key])
			clearing_max_step = maxf(clearing_max_step, step)
			clearing_travel += step
			clearing_positions[key] = actor.global_position
	if controller.active_id.is_empty() or not is_instance_valid(controller._race_traffic) or not controller._race_traffic.is_clear():
		check(false, "physical race preparation failed to clear the track: %s" % controller._last_message)
		scene.queue_free()
		await process_frame
		quit(1)
		return
	check(clearing_max_step < 30.0, "race organizers clear traffic with continuous physical driving")
	for actor in clearing_cars:
		check(is_instance_valid(actor), "event preserves each evacuated car")
	print("RACE_PREPARED elapsed=%.2f fleet=%d cleared=%d travel=%.1f max_step=%.2f" % [controller._race_traffic.elapsed, get_nodes_in_group("modern_traffic").size(), clearing_cars.size(), clearing_travel, clearing_max_step])
	# Fixture preparation only. No transform or velocity writes below this block.
	car.position = controller.RACE_START
	car.rotation = -PI / 2.0
	player.position = car.position + Vector2(-45,0)
	car.enter_vehicle(player)
	check(car.is_driven_by_player, "production car entered")
	controller.interact()
	var travel := 0.0
	var previous: Vector2 = car.global_position
	var max_step := 0.0
	var max_radial := 0.0
	var prior_hp: int = car.health
	var prior_player_hp: int = player.health
	var collisions: Array[String] = []
	var passing := false
	var passing_vehicle: Node2D
	var passing_clearance := 120.0
	var stalled_frames := 0
	var reversing_frames := 0
	var recoveries := 0
	var test_deadline := Time.get_ticks_msec() + 200000
	for frame in 6600: # The authored 100s trial plus countdown and boarding.
		await physics_frame
		if Time.get_ticks_msec() > test_deadline:
			check(false, "real-input trial exceeded its 200s wall-clock budget")
			break
		var step := previous.distance_to(car.global_position)
		travel += step
		max_step = maxf(max_step, step)
		previous = car.global_position
		max_radial = maxf(max_radial, absf(car.global_position.distance_to(controller.CENTER)-300.0))
		for i in car.get_slide_collision_count():
			var hit: KinematicCollision2D = car.get_slide_collision(i)
			var object := hit.get_collider()
			var label := str(object.get_path()) if object is Node else str(object)
			if not collisions.has(label):
				collisions.append(label)
				print("RACE_COLLIDER frame=%d at=%s speed=%.1f body=%s normal=%s" % [frame,car.global_position,car.velocity.length(),label,hit.get_normal()])
		if car.health != prior_hp or player.health != prior_player_hp:
			print("RACE_DAMAGE frame=%d at=%s car=%d->%d player=%d->%d speed=%.1f colliders=%s" % [frame,car.global_position,prior_hp,car.health,prior_player_hp,player.health,car.velocity.length(),collisions])
			prior_hp = car.health
			prior_player_hp = player.health
		if controller.active_id.is_empty():
			break
		if controller._countdown > 0.0:
			continue
		# Pure-pursuit steering feedback. Analogue action strength feeds the same
		# input axes used by keyboard/gamepad; no physics bypass or teleport.
		var radial: Vector2 = car.global_position - controller.CENTER
		var ahead := false
		var oncoming := false
		var nearest_ahead: Node2D
		var nearest_gap := INF
		for other in get_nodes_in_group("vehicle"):
			if other == car or not other is Node2D:
				continue
			var offset: Vector2 = other.global_position - controller.CENTER
			if absf(offset.length()-300.0)>55.0:
				continue
			var gap := fposmod(offset.angle()-radial.angle(),TAU)*300.0
			var direction := int(other.get_meta("traffic_direction",1))
			if direction < 0 and gap < 500.0:
				oncoming = true
			if direction > 0 and gap < 190.0:
				ahead = true
				if gap < nearest_gap:
					nearest_gap = gap
					nearest_ahead = other
		if not passing and ahead and not oncoming:
			passing = true
			passing_vehicle = nearest_ahead
		elif passing:
			# Passing ends only when the whole car has cleared the target.
			# "Ahead" changes sign as soon as the nose passes its centre;
			# using that to merge immediately causes a side-on collision.
			if not is_instance_valid(passing_vehicle):
				passing = false
			else:
				var target_radial: Vector2 = passing_vehicle.global_position - controller.CENTER
				var passed_distance := wrapf(radial.angle()-target_radial.angle(),-PI,PI)*300.0
				if passed_distance > passing_clearance:
					passing = false
					passing_vehicle = null
		var lane_radius := 279.0 if passing else 321.0
		var goal: Vector2 = controller.CENTER + radial.normalized().rotated(0.22) * lane_radius
		var desired: float = (goal-car.global_position).angle()
		var steering := clampf(wrapf(desired-car.rotation,-PI,PI)*2.3,-1.0,1.0)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if steering > 0.0:
			Input.action_press("move_right", steering)
		else:
			Input.action_press("move_left", -steering)
		var desired_speed := 65.0 if ahead and not passing else (140.0 if passing else 110.0)
		# A human can back away from a blocked bumper instead of holding the
		# throttle against it forever. Recovery still uses production inputs.
		stalled_frames = stalled_frames + 1 if car.velocity.length() < 3.0 else 0
		if stalled_frames > 60 and reversing_frames == 0 and recoveries < 6:
			reversing_frames = 55
			recoveries += 1
			stalled_frames = 0
		var signed_speed: float = car.velocity.dot(car.transform.x)
		if reversing_frames > 0:
			reversing_frames -= 1
			Input.action_release("move_up")
			if signed_speed > -45.0:
				Input.action_press("move_down")
			else:
				Input.action_release("move_down")
			Input.action_release("move_left")
			Input.action_release("move_right")
		elif signed_speed < desired_speed:
			Input.action_release("move_down")
			Input.action_press("move_up")
		else:
			Input.action_release("move_up")
			if signed_speed > desired_speed + 10.0:
				Input.action_press("move_down")
			else:
				Input.action_release("move_down")
	for action in ["move_up","move_down","move_left","move_right"]:
		Input.action_release(action)
	check(bool(state.data.completed.get("cobra_race", false)), "production input-driven car wins: %s position=%s" % [{"objective":controller.get_objective(),"progress":controller._race_progress,"seconds":controller._race_elapsed,"message":controller._last_message},car.global_position])
	check(travel>1500.0 and max_step<20.0,"continuous driving without jumps")
	check(get_nodes_in_group("modern_traffic").size() > 0, "ambient traffic remains enabled")
	print("COBRA PLAYER CAR RACE failures=%d travel=%.1f max_step=%.2f radial=%.1f car_hp=%d player_hp=%d ambient=%d recoveries=%d" % [failures.size(),travel,max_step,max_radial,car.health,player.health,get_nodes_in_group("modern_traffic").size(),recoveries])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
