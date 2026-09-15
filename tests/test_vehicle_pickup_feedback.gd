extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(70).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var road := Polygon2D.new()
	road.z_index = 2
	road.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(4000,-1000),Vector2(4000,1000),Vector2(-1000,1000)])
	road.color = Color("394144")
	world.add_child(road)
	var effects := preload("res://guns/combat/WeaponEffects.gd").new()
	world.add_child(effects)
	var player = preload("res://characters/Player.gd").new()
	player.collision_layer = 4
	var player_camera := Camera2D.new()
	player_camera.name = "Camera"
	player.add_child(player_camera)
	var player_shape := CollisionShape2D.new()
	player_shape.shape = CircleShape2D.new()
	player_shape.shape.radius = 10
	player.add_child(player_shape)
	world.add_child(player)
	for i in 5: await physics_frame
	var start_money: int = player.money
	var cash := preload("res://economy/CashPickup.gd").new()
	cash.amount = 75
	cash.position = player.global_position
	world.add_child(cash)
	for i in 6: await physics_frame
	check(player.money==start_money+75 and cash._is_collected,"physical cash overlap awards money once")
	check(world.find_children("*","AudioStreamPlayer2D",false,false).size()>0,"cash collection creates its audio feedback")
	cash._on_body_entered(player)
	check(player.money==start_money+75,"cash cannot be collected twice")
	player._create_3d_blood_puddle()
	var puddle := get_nodes_in_group("ground_blood").back() as Node2D
	check(puddle.z_index>road.z_index and not puddle.z_as_relative,"blood puddle draws above the road")
	var police = root.get_node("EmergencyPool").get_vehicle("police")
	police.position = Vector2(0,120)
	police.set_physics_process(false)
	check(police.z_index>road.z_index and police.visual.texture!=null and police.visual.is_visible_in_tree(),"activated police body is visible above roads")
	var reviewed_car: Node2D
	for id in ["sedan_classic","union_sedan","summit_suv"]:
		var car = ModernTrafficFactory.spawn_parked_vehicle(world,"Boarding_"+id,Vector2(600,0),0,id,0,Color("3588b5"))
		player.global_position = car.global_position+Vector2(0,-45)
		Input.action_press("ui_up")
		Input.action_press("interact")
		var before: Vector2 = car.global_position
		var health: int = car.health
		car.enter_vehicle(player)
		for i in 20: await physics_frame
		check(car.is_driven_by_player,"held entry key does not eject "+id)
		check(car.global_position.distance_to(before)<1 and car.velocity.length()<1 and car.health==health,"walking input cannot launch or damage "+id)
		Input.action_release("ui_up")
		Input.action_release("interact")
		for i in 3: await physics_frame
		Input.action_press("ui_up")
		for i in 25: await physics_frame
		Input.action_release("ui_up")
		check(car.global_position.x>before.x+10 and absf(car.global_position.y-before.y)<1 and car.health==health,"fresh throttle drives straight without self damage "+id)
		if car.is_3d_vehicle:
			check(is_instance_valid(car._door_3d) and car._door_3d.extracted_triangles>0,"native body mesh supplies the hinged door "+id)
			check(car._door_visual==null,"3D car does not create a 2D door overlay "+id)
		car.exit_vehicle()
		if id=="summit_suv": reviewed_car=car
		else: car.queue_free()
		for i in 4: await physics_frame
	var driver := preload("res://characters/CarjackedDriver.tscn").instantiate()
	world.add_child(driver)
	driver.setup(reviewed_car,Vector2(0,60))
	driver._begin_civilian_routine()
	var old_position: Vector2 = driver.global_position
	for i in 240: await physics_frame
	check(driver.driver_model is Node3D and driver.shirt_color==Color("39835a"),"ejected civilian uses articulated green 3D model")
	check(driver.civilian_routine and driver.global_position.distance_to(old_position)>5,"civilian resumes a walking routine")
	var effect_count := effects.get_child_count()
	var bullet = preload("res://guns/Bullet.tscn").instantiate()
	world.add_child(bullet)
	bullet._hit(driver,driver.global_position,Vector2.UP)
	check(effects.get_child_count()>effect_count,"flesh impact emits combat feedback")
	if DisplayServer.get_name()!="headless":
		player.global_position = Vector2(-90,55)
		reviewed_car.position = Vector2(-75,-20)
		police.position = Vector2(80,-20)
		driver.position = Vector2(20,50)
		driver.set_physics_process(false)
		driver.speech_bubble.hide()
		var camera := Camera2D.new()
		camera.zoom = Vector2.ONE*3
		world.add_child(camera)
		camera.make_current()
		reviewed_car._animate_car_door()
		await create_timer(0.32).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/vehicle-feedback-review.png")
	print("VEHICLE/PICKUP FEEDBACK FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)

