extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func wait_body_transition(world, limit := 240) -> void:
	for i in limit:
		if not world.driving.is_body_transition_active(): return
		await physics_frame
	check(false,"Vehicle body transition timed out")

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(10)
	var car = world.driving.car
	car.place(Vector3(0,0.04,0),0)
	world.player.teleport(Vector3(-1.65,0.04,0.15))
	await frames(2)
	check(world.driving.interact(),"Enter car for steering test")
	await wait_body_transition(world)
	car.external_input = true
	car.throttle_input = 1
	car.steer_input = 1
	await frames(60)
	check(car.rotation.y > 0.2,"Steering left must turn the moving car left")
	check(absf(car.wheels[0].rotation.x) > 0.5,"Wheels must roll with travelled distance")
	car.place(Vector3(0,0.04,0),0)
	car.steering = 0
	car.steer_input = 0
	car.throttle_input = -1
	car.brake_input = false
	await frames(60)
	check(car.speed < -2,"Reverse must engage from rest")
	check(car.position.z > 1,"Reverse must move backwards")
	check(absf(car.speed) <= car.REVERSE_SPEED+0.01,"Reverse speed must respect its limit")
	world.activity.stage = 0
	world.activity.dwell = 0
	world.activity.completed = false
	car.place(world.activity.points[-1]+Vector3.UP*0.04,0)
	car.throttle_input = 0
	car.brake_input = true
	await frames(70)
	check(world.activity.stage == 0,"Out-of-order checkpoint must not advance activity")
	check(world.driving.leave(),"Can leave at destination")
	await wait_body_transition(world)
	world.player.teleport(world.activity.points[0]+Vector3.UP*0.04)
	await frames(70)
	check(world.activity.stage == 0,"Walking into checkpoint must not complete a vehicle stop")
	world.player.teleport(car.to_global(Vector3(-1.65,0.04,0.15)))
	await frames(2)
	check(world.driving.interact(),"Re-enter for moving checkpoint test")
	await wait_body_transition(world)
	car.place(world.activity.points[0]+Vector3(0,0.04,3),0)
	car.external_input = true
	car.throttle_input = 1
	car.brake_input = false
	car.speed = 6
	await frames(30)
	check(world.activity.stage == 0,"Driving through the marker without stopping must not advance")
	world._toggle_pause()
	var reset_button: Button = world.pause_panel.get_child(0).get_child(2)
	reset_button.pressed.emit()
	for i in 10: await process_frame
	check(not paused,"Restart must clear paused state")
	check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://Main.tscn","Restart must reopen actual main scene")
	check(not current_scene.driving.occupied and current_scene.player.visible,"Restart from driving must restore a visible pedestrian")
	check(current_scene.traffic.cars.size() == 6 and current_scene.people.size() == 24,"Restart must rebuild default population and traffic once")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://evidence/controls-functional.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CONTROLS_VALIDATION ",JSON.stringify(report))
	current_scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
