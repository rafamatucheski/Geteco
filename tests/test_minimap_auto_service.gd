extends SceneTree
var failures: Array[String] = []
var leaked_cold_hud := false
func _process(_delta: float) -> bool:
	if is_instance_valid(current_scene):
		var stream: Node = current_scene.get_node_or_null("ContinuousWorld")
		if stream != null and is_instance_valid(stream.mountain) and is_instance_valid(stream.mountain.cold_hud):
			if not stream.mountain.region_selected and stream.mountain.cold_hud.visible: leaked_cold_hud = true
	return false
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func frames(n: int) -> void:
	for i in n: await process_frame
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await frames(30)
	var world := current_scene
	var player: Node2D = world.get_node("Player")
	var manager: Node = world.get_node("PersonalCarManager")
	var car: Node2D = manager.car
	var map: Node = world.get_node("Minimap")
	var service: Node2D = world.get_node("PayNSpray")
	player.set_physics_process(false)
	player.global_position = Vector2(715,1800)
	map.refresh()
	check(map.show_car and map.car_map_position.distance_to(world.get_node("District/Garage/Entrance/OutsideReturn").global_position)<1,"parked showroom car maps to real garage exterior")
	car.global_position = Vector2(9800,-5200)
	map.refresh()
	check(map.car_offscreen and Rect2(Vector2.ZERO,map.MAP_SIZE).has_point(map.car_marker),"distant personal car keeps a bounded directional marker")
	check(map._roads.size()>10,"minimap uses real road network")
	car.global_position = service.global_position+Vector2(0,15)
	car.rotation = -PI/2
	service._clock = 999
	player.money = 50
	car.enter_vehicle(player)
	await frames(3)
	map.refresh()
	check(not map.show_car,"personal parked marker hides while driving it")
	service._clock = 999
	player.money = 50
	check(not service.start_service(car) and car.is_physics_processing(),"insufficient balance leaves driver in control")
	player.money = 500
	car.health = 45
	car.repaint_vehicle(Color("355bb0"))
	var paint: Color = car.paint_color
	var layer: int = car.collision_layer
	service._clock = 0
	while not service.busy: await process_frame
	check(not car.is_physics_processing() and player.is_control_disabled,"slow arrival automatically starts protected vehicle movement")
	check(not car.headlight.enabled and not car.second_headlight.enabled,"both headlamps stop emitting before entering facade")
	var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(Vector2(snapshot.vehicle.x,snapshot.vehicle.y).distance_to(service.global_position+service.EXIT_OFFSET)<1,"save during service stores a safe exterior vehicle position")
	manager.capture_state()
	check(player.personal_car_state.position[1]==service.global_position.y+service.EXIT_OFFSET.y,"parked personal save also uses safe service exit")
	while service.phase != "repair": await process_frame
	check(car.modulate.a<0.01 and not service.shutter.position.y,"vehicle stays behind closed shutter during repair")
	car._apply_headlight_state()
	check(not car.headlight.enabled and not car.second_headlight.enabled,"headlight refresh cannot light through closed workshop")
	var started := Time.get_ticks_msec()
	while service.phase == "repair": await process_frame
	var seconds := (Time.get_ticks_msec()-started)/1000.0
	check(seconds>=4.25 and seconds<5.2,"repair holds approximately 4.5 real seconds")
	while service.busy: await process_frame
	check(car.headlight.enabled and car.second_headlight.enabled,"headlamp emission returns outside workshop")
	check(car.health==car.max_health and car.paint_color.is_equal_approx(paint),"Monaliza restored without changing paint")
	check(player.money==400 and service.serviced_count==1,"service charges exactly once")
	check(car.is_driven_by_player and car.is_physics_processing() and not player.is_control_disabled and car.collision_layer==layer and car.modulate.a==1,"automatic exit restores visibility, physics and controls")
	check(car.global_position.distance_to(service.global_position+service.EXIT_OFFSET)<2,"vehicle returns outside instead of remaining in wall")
	var collider: CollisionShape2D = car.get_node("Collision")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = car.global_transform*collider.transform
	query.collision_mask = 1
	query.exclude = [car.get_rid()]
	check(car.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"returned car hull is clear of building and curb solids")
	check(car.global_position.y+43<=-1160,"personal car exits onto apron before active traffic lanes")
	await frames(20)
	check(not service.busy and player.money==400,"exit cannot retrigger repeated service")
	car.exit_vehicle()
	player.set_physics_process(false)
	player.global_position = car.global_position+Vector2(-65,10)
	map.refresh()
	check(map.show_car and not map.car_offscreen,"parking outside updates local personal marker")
	if DisplayServer.get_name()!="headless":
		var camera: Camera2D = player.get_node("Camera")
		camera.global_position = service.global_position+Vector2(0,-50)
		camera.make_current()
		camera.zoom = Vector2.ONE*1.1
		camera.reset_smoothing()
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/minimap-paynspray-review.png")
	# A second ordinary car keeps the normal repaint service.
	var other := preload("res://world/mountain_pass/MountainSUV.gd").new()
	world.add_child(other)
	other.global_position = service.global_position+Vector2(0,15)
	other.rotation = -PI/2
	other.repaint_vehicle(Color("123456"))
	other.health = 55
	var normal_speed: float = other.max_speed
	other.puncture_tires()
	other.enter_vehicle(player)
	service._clock = 999
	check(not service.start_service(other),"service waits until boarding finishes")
	while other.has_meta("vehicle_boarding"): await process_frame
	check(service.start_service(other),"ordinary vehicles can use the same service")
	while service.busy: await process_frame
	check(other.health==other.max_health and not other.paint_color.is_equal_approx(Color("123456")),"ordinary vehicle repaired and repainted")
	check(not other.has_punctured_tires and is_equal_approx(other.max_speed,normal_speed),"repaired tires recover original performance")
	other.exit_vehicle()
	service._departing = null
	other.global_position = service.global_position
	other.enter_vehicle(player)
	while other.has_meta("vehicle_boarding"): await process_frame
	check(service.start_service(other),"another visit can start after departure")
	service._cancel()
	check(other.headlight.enabled and other.second_headlight.enabled,"cancel restores both headlamps")
	check(not service.busy and other.is_physics_processing() and not player.is_control_disabled and other.modulate.a==1,"interrupted service releases car and controls")
	check(not leaked_cold_hud,"background mountain loading never shows cold HUD in Northgate")
	print("MINIMAP AUTO SERVICE FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)
