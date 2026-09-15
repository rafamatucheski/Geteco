extends SceneTree
const CAR := preload("res://world/harbor/campaign/MaciotaTourCar.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func obstacle(at: Vector2, size: Vector2, parent: Node, vehicle := true) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.position = at
	body.collision_layer = 4 if vehicle else 2
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	parent.add_child(body)
	if vehicle: body.add_to_group("vehicle")
	return body
func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var lane := ModernTrafficFactory.create_lane(stage,"DetourLane",PackedVector2Array([Vector2(-100,0),Vector2(900,0)]))
	lane.set_meta("traffic_road_width",120.0)
	lane.set_meta("traffic_lane_offset",30.0)
	lane.set_meta("traffic_sidewalk_width",40.0)
	var car := CAR.new()
	car.heading = 0
	stage.add_child(car)
	car.set_physics_process(false)
	var points := PackedVector2Array()
	for x in range(0,701,10): points.append(Vector2(x,0))
	car.start(points)
	var stopped := obstacle(Vector2(210,0),Vector2(72,30),stage)
	await physics_frame
	await physics_frame
	for i in 200: car._wait_for_obstacle(stopped,1.0/60)
	check(car.pass_plan != null,"a sustained blockage starts bounded pavement-aware detour search")
	var deadline := Time.get_ticks_msec()+10000
	while car.pass_plan != null and not car.pass_plan.valid and Time.get_ticks_msec()<deadline:
		car._advance_pass(1.0/60)
		await physics_frame
	check(car.pass_plan != null and car.pass_plan.valid,"a clear sidewalk or opposing lane admits the full car")
	print("DETOUR preferred offset=",car.PASS_OFFSETS[car.pass_side]," hull=",car.shape.shape.size)
	if car.pass_plan == null:
		print("DETOUR failure=",car.pass_reason)
		quit(1)
		return
	var pedestrian := obstacle(car.pass_plan.poses[mini(35,car.pass_plan.poses.size()-1)].origin,Vector2(18,18),stage,false)
	await physics_frame
	await physics_frame
	var blocked := false
	for i in range(1,car.pass_plan.poses.size()):
		if not car.pass_plan.clear(car.pass_plan.poses[i-1],car.pass_plan.poses[i]): blocked = true; break
	check(blocked,"a pedestrian arriving after planning blocks the live swept path")
	pedestrian.queue_free()
	await physics_frame
	await physics_frame
	deadline = Time.get_ticks_msec()+20000
	var previous := car.global_position
	var max_step := 0.0
	while car.pass_plan != null and Time.get_ticks_msec()<deadline:
		car._advance_pass(.05)
		max_step = maxf(max_step,previous.distance_to(car.global_position))
		previous = car.global_position
		await physics_frame
	check(car.pass_plan == null and car.global_position.x > 400,"detour passes obstacle and rejoins the original route")
	check(absf(car.global_position.y)<1 and max_step<=3.01,"return has no teleport or lateral snap")
	check(stopped.global_position == Vector2(210,0),"parked blocker is never pushed or relocated")
	# The preferred opposing lane is occupied; the sidewalk must remain an option.
	car.global_position = Vector2.ZERO
	car.heading = 0
	car.pose()
	car.start(points)
	var sidewalk_blocker := obstacle(Vector2(210,0)+Vector2.RIGHT.orthogonal()*44,Vector2(90,25),stage,false)
	await physics_frame
	await physics_frame
	car.stationary_time = 3
	car._try_pass_stopped_vehicle(stopped)
	deadline = Time.get_ticks_msec()+10000
	while car.pass_plan != null and not car.pass_plan.valid and Time.get_ticks_msec()<deadline:
		car._advance_pass(1.0/60)
		await physics_frame
	check(car.pass_plan != null and car.pass_plan.valid and car.PASS_OFFSETS[car.pass_side] < 0,"occupied opposing lane selects the clear sidewalk")
	sidewalk_blocker.queue_free()
	print("MACIOTA_DETOUR failures=",failures," reason=",car.pass_reason)
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)
