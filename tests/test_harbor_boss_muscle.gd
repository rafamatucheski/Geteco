extends SceneTree

const CAR := preload("res://prototypes/living_cast/HarborBossMuscle.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := CAR.new()
	world.add_child(car)
	for i in 4: await physics_frame
	check(car.get_node("Collision").shape.size == Vector2(82,35),"Boss physical footprint")
	check(car.max_speed == 560 and not car.has_nitro,"Boss pacing must not enable nitro")
	check(car.wheels.size() == 4 and car.spinners.size() == 4,"Four real wheel rigs")
	for spinner in car.spinners:
		check(spinner.get_child_count() >= 5,"Wheel geometry must attach to animated hub")
	check(CAR.get_v8_stream() == car.engine_audio.stream and CAR.v8_stream_builds == 1,"V8 must be shared once")
	car._animate_car_door()
	check(car._door_visual.position.is_equal_approx(Vector2(0.58,-0.945)*car.PIXELS_PER_METRE),"Door hinge must match muscle seam")
	check(is_equal_approx(car._door_visual._door_length,1.66*car.PIXELS_PER_METRE),"Door length must match muscle cabin")
	car.is_driven_by_player = true
	Input.action_press("ui_up")
	for i in 60: await physics_frame
	check(car.position.x > 100 and car.velocity.length() <= 560.1,"Actual input forward pacing")
	Input.action_press("ui_left")
	for i in 12: await physics_frame
	Input.action_release("ui_left")
	Input.action_release("ui_up")
	check(absf(car.rotation) > 0.05 and absf(car.spinners[0].rotation.x) > 1,"Real steering and wheel spin")
	car.velocity = Vector2.ZERO
	car.is_driven_by_player = false
	car.repaint_vehicle(Color("263f73"))
	check(car.body_model.paint.albedo_color == Color("263f73") and car.sprite.modulate == Color.WHITE,"Paint preserves windows")
	car.body_model.apply_impact(Vector3(-0.61,0.80,-2.46),Vector3(0,0,1),12)
	check(car.body_model.max_deformation() > 0 and car.body_model.broken_lamps[0],"Muscle damage and front bar failure")
	car.max_speed = 0.0
	car.repair_vehicle()
	check(car.max_speed == 560.0,"Repair must restore speed after wreck")
	check(car.body_model.max_deformation() == 0 and not car.body_model.broken_lamps[0],"Repair geometry and lamps")
	check(car.headlight.position.x == 39 and car.second_headlight.position.x == 39,"Light originates at front lamps")
	for i in 5: await physics_frame
	var before: int = car.appearance_updates
	for i in 30: await physics_frame
	check(car.appearance_updates - before <= 1,"Parked vehicle must not redraw continuously")
	print("BOSS_MUSCLE_RESULT failures=%d meshes=%d" % [failures,car.body_model.get_child_count()])
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
