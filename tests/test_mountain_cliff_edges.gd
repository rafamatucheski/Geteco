extends SceneTree

class Walker extends CharacterBody2D:
	var damage := 0
	func take_environment_damage(amount: int) -> void: damage += amount

var failures := 0
var capture_camera: Camera2D
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ",description)
	if not ok: failures += 1

func wait_for_recovery(player: Node2D) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while (player.is_dead or player.is_recovering) and Time.get_ticks_msec() < deadline:
		await process_frame

func capture(label: String) -> void:
	if capture_camera == null: return
	capture_camera.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/mountain-rebuild-0913/verified-" + label + ".png")

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-cliffs-0912/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	var road = preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	root.add_child(road)
	var cliffs = road.cliff_edges
	check(cliffs.patches.size()>20,"cliffs follow multiple mountain bends")
	var full_length := 0.0
	var protected_length := 0.0
	for section in road._guard_rail_sections(true):
		for i in section.size()-1: full_length += section[i].distance_to(section[i+1])
	for section in road._guard_rail_sections():
		for i in section.size()-1: protected_length += section[i].distance_to(section[i+1])
	check(protected_length<full_length*.8 and protected_length>full_length*.2,"guardrail protects apexes and leaves substantial openings")
	var walker := Walker.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 1
	walker.add_child(shape)
	root.add_child(walker)
	var patch: Dictionary = cliffs.patches[2]
	var lip: Vector2 = (patch.lip[0]+patch.lip[1])*.5
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
		root.content_scale_size = root.size
		var terrain := Polygon2D.new()
		terrain.polygon = PackedVector2Array([lip+Vector2(-1000,-1000),lip+Vector2(1000,-1000),lip+Vector2(1000,1000),lip+Vector2(-1000,1000)])
		terrain.z_index = -3
		terrain.color = Color("344535")
		root.add_child(terrain)
		capture_camera = Camera2D.new()
		root.add_child(capture_camera)
		capture_camera.position = lip + patch.normal * 60.0 + Vector2(0, 30)
		capture_camera.zoom = Vector2.ONE * 2.5
	walker.position = road.curve.get_closest_point(lip)
	for i in 4: await physics_frame
	check(not walker.has_meta("mountain_falling"),"lane does not trigger fall")
	walker.position = lip+patch.normal*12
	for i in 5: await physics_frame
	check(walker.has_meta("mountain_falling"),"crossing actual lip starts fall")
	await create_timer(.4).timeout
	var effect := root.get_node_or_null("MountainCliffFall") as Node2D
	check(effect != null and effect.scale.x<1.0 and walker.scale==Vector2.ONE and walker.damage==0,"presentation descends without shrinking the actor or camera")
	cliffs.process_mode = Node.PROCESS_MODE_DISABLED
	await create_timer(.6).timeout
	check(walker.damage==10000,"one impact even when the streamed cliff is disabled mid-fall")
	cliffs.process_mode = Node.PROCESS_MODE_INHERIT
	check(walker.scale==Vector2.ONE and walker.collision_layer==2 and walker.process_mode==Node.PROCESS_MODE_INHERIT,"fall restores presentation and control state for recovery")
	walker.queue_free()
	var relocated := Walker.new()
	root.add_child(relocated)
	cliffs._fall(relocated, Vector2.RIGHT)
	relocated.position += Vector2(1000, 1000)
	await process_frame
	await process_frame
	check(relocated.damage==0 and relocated.process_mode==Node.PROCESS_MODE_INHERIT and relocated.visible and not relocated.has_meta("mountain_falling"),"external relocation cancels fall and releases controls")
	relocated.queue_free()
	var player = preload("res://Player.gd").new()
	player.position = Vector2(0,300)
	player.collision_layer = 4
	player.collision_mask = 1
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var player_shape := CollisionShape2D.new()
	player_shape.shape = CircleShape2D.new()
	player_shape.shape.radius = 5
	player.add_child(player_shape)
	root.add_child(player)
	player.set_physics_process(false)
	for i in 5: await process_frame
	player.position = lip+patch.normal*12
	await create_timer(.35).timeout
	await capture("foot-falling")
	await create_timer(.75).timeout
	await capture("foot-impact")
	check(player.is_dead,"production Dante receives fatal environmental impact")
	await wait_for_recovery(player)
	check(not player.is_dead and player.health==player.max_health and player.scale==Vector2.ONE,"production hospital recovery restores Dante")
	player._respawn_grace_active = false
	var car = preload("res://world/mountain_pass/MountainSUV.gd").new()
	car.position = road.curve.get_closest_point(lip)
	root.add_child(car)
	player.position = car.position+Vector2(0,30)
	car.enter_vehicle(player)
	await create_timer(1.2).timeout
	car.set_physics_process(false)
	check(car.is_driven_by_player,"production Summit SUV has its driver")
	car.position = lip-patch.normal*12
	for i in 5: await physics_frame
	check(not car.has_meta("mountain_falling"),"vehicle overhang alone does not trigger fall")
	car.position = lip+patch.normal*12
	await create_timer(.35).timeout
	await capture("car-falling")
	await create_timer(.75).timeout
	await capture("car-impact")
	check(player.is_dead and not car.is_driven_by_player,"falling SUV releases and damages its driver")
	check(car.health==0,"falling SUV receives impact damage")
	check(not car.visible and car.collision_layer==0 and not car.is_exploding and not car._fire_truck_dispatched,"wreck below cliff does not block road, explode or summon firefighters")
	await wait_for_recovery(player)
	check(not player.is_dead and player.is_physics_processing() and player.process_mode==Node.PROCESS_MODE_INHERIT,"driver recovers with controls enabled")
	car.repair_vehicle()
	check(car.visible and car.collision_layer!=0 and not car.has_meta("mountain_falling") and car.global_position.distance_to(road.to_global(road.curve.get_closest_point(road.to_local(car.global_position))))<1.0,"repair recovers the wreck to the road with collision restored")
	player._respawn_grace_active = false
	car.enter_vehicle(player)
	await create_timer(2.3).timeout
	cliffs._fall(car, patch.normal)
	car.queue_free()
	await process_frame
	await process_frame
	check(player.visible and player.is_physics_processing() and not player.is_control_disabled and not player.has_meta("mountain_falling"),"removing a falling vehicle cannot strand its hidden driver")
	print("CLIFF_TEST failures=",failures)
	quit(failures)
