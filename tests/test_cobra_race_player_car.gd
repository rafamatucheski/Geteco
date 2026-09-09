extends SceneTree
## Real Harbor PlayerCar, unchanged controller, only Input actions after staging.
const CONTROLLER = preload("res://district/harbor_preview/campaign/CobraCampaignController.gd")
const STATE = preload("res://district/harbor_preview/campaign/CobraCampaignState.gd")
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func run() -> void:
	seed(63421)
	var scene = load("res://district/harbor_preview/HarborPreview.tscn").instantiate()
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
	# Fixture preparation only. No transform or velocity writes below this block.
	car.position = controller.RACE_START
	car.rotation = -PI / 2.0
	player.position = car.position + Vector2(-45,0)
	car.enter_vehicle(player)
	check(car.is_driven_by_player, "production car entered")
	check(controller.start_mission("cobra_race"), "race begins")
	controller.interact()
	var travel := 0.0
	var previous: Vector2 = car.global_position
	var max_step := 0.0
	var max_radial := 0.0
	var prior_hp: int = car.health
	var prior_player_hp: int = player.health
	var collisions: Array[String] = []
	var passing := false
	for frame in 3600:
		await physics_frame
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
			if direction > 0 and gap < 130.0:
				ahead = true
		if not passing and ahead and not oncoming:
			passing = true
		elif passing and (oncoming or not ahead):
			passing = false
		var lane_radius := 318.0 if passing else 282.0
		var goal: Vector2 = controller.CENTER + radial.normalized().rotated(0.22) * lane_radius
		var desired: float = (goal-car.global_position).angle()
		var steering := clampf(wrapf(desired-car.rotation,-PI,PI)*2.3,-1.0,1.0)
		Input.action_release("ui_left")
		Input.action_release("ui_right")
		if steering > 0.0:
			Input.action_press("ui_right", steering)
		else:
			Input.action_press("ui_left", -steering)
		var desired_speed := 95.0 if ahead and not passing else 145.0
		if car.velocity.length() < desired_speed:
			Input.action_press("ui_up")
		else:
			Input.action_release("ui_up")
	for action in ["ui_up","ui_down","ui_left","ui_right"]:
		Input.action_release(action)
	check(bool(state.data.completed.get("cobra_race", false)), "production input-driven car wins: %s position=%s" % [controller.get_status(),car.global_position])
	check(travel>1500.0 and max_step<20.0,"continuous driving without jumps")
	check(get_nodes_in_group("modern_traffic").size() > 0, "ambient traffic remains enabled")
	print("COBRA PLAYER CAR RACE failures=%d travel=%.1f max_step=%.2f radial=%.1f car_hp=%d player_hp=%d ambient=%d" % [failures.size(),travel,max_step,max_radial,car.health,player.health,get_nodes_in_group("modern_traffic").size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
