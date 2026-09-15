extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(55).timeout.connect(func(): print("SIREN TIMEOUT"); quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var capture := "--capture" in OS.get_cmdline_user_args()
	var capture_times: Array[float] = []
	var capture_frame := 0
	if capture: DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/siren-passage/motion")
	# The test road uses the same authored width and sidewalk that constrain
	# the maneuver, so its visible curb agrees with the clearance assertions.
	for layer in [[Rect2(-100,-132,2800,204),Color("aaa9a1")],[Rect2(-100,-90,2800,120),Color("202932")]]:
		var polygon := Polygon2D.new()
		var rect: Rect2 = layer[0]
		polygon.polygon = PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		polygon.color = layer[1]
		polygon.z_index = -10
		world.add_child(polygon)
	for x in range(0,2600,60):
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(x,-30),Vector2(x+28,-30)])
		line.default_color = Color("dfc84d")
		line.width = 2
		line.z_index = -9
		world.add_child(line)
	root.get_node("WantedManager").set_process(false)
	root.get_node("NPCMedicalCare").set_process(false)
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(2600,0))
	path.set_meta("traffic_road_width",120.0)
	path.set_meta("traffic_lane_offset",30.0)
	path.set_meta("traffic_sidewalk_width",42.0)
	path.add_to_group("unified_traffic_lane")
	world.add_child(path)
	var blocked_side := "--blocked-side" in OS.get_cmdline_user_args()
	if blocked_side:
		var post := StaticBody2D.new()
		post.position = Vector2(600,-40)
		var collision := CollisionShape2D.new()
		collision.shape = CircleShape2D.new()
		collision.shape.radius = 6
		post.add_child(collision)
		var visual := Polygon2D.new()
		var outline := PackedVector2Array()
		for vertex in 24: outline.append(Vector2.from_angle(vertex*TAU/24)*6)
		visual.polygon = outline
		visual.color = Color("d2a130")
		post.add_child(visual)
		world.add_child(post)
	var car := ModernTrafficFactory.spawn_moving_vehicle(path,"YieldingDriver","union_sedan",.25,35,1)
	car.set_process(false)
	car.set_physics_process(false)
	var second: CharacterBody2D
	if "--two-cars" in OS.get_cmdline_user_args():
		second = ModernTrafficFactory.spawn_moving_vehicle(path,"SecondYieldingDriver","union_sedan",850.0/2600,35,2)
		second.set_process(false)
		second.set_physics_process(false)
	var unit: CharacterBody2D
	for frame in 60:
		unit = root.get_node("EmergencyPool").get_vehicle("ambulance")
		if is_instance_valid(unit): break
		await process_frame
	unit.position = Vector2(250,0)
	unit.rotation = 0
	if "--joining" in OS.get_cmdline_user_args():
		unit.position.y = -70
		unit.rotation = PI*.5
	unit.set_physics_process(false)
	unit.target = Node2D.new()
	unit.target.position = Vector2(2400,0)
	world.add_child(unit.target)
	unit.siren_audio.play()
	print("SIREN_GEOMETRY car=",car.global_transform," hull=",car.collision.shape.get_rect()," local=",car.collision.transform," lane=",path.curve.sample_baked_with_rotation(650,true))
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(750,0)
	camera.zoom = Vector2.ONE*1.2
	var saw_pull := false
	var saw_hold := false
	var saw_merge := false
	var side := 0.0
	var ambulance_side := 0.0
	var overlaps := 0
	var max_jump := 0.0
	var max_side_step := 0.0
	var started := Time.get_ticks_msec()
	var actors: Array[CharacterBody2D] = [car,unit]
	if is_instance_valid(second): actors.append(second)
	for frame in 2400:
		await physics_frame
		var before: Array[Transform2D] = []
		for actor in actors: before.append(actor.global_transform)
		car.advance_on_lane(1.0/60)
		if is_instance_valid(second): second.advance_on_lane(1.0/60)
		unit._physics_process(1.0/60)
		if DisplayServer.get_name() != "headless":
			car._update_3d_orientation(1.0/60)
			if is_instance_valid(second): second._update_3d_orientation(1.0/60)
			if capture and frame%6==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/siren-passage/motion/%04d.png"%capture_frame)
				capture_frame += 1
				capture_times.append((Time.get_ticks_msec()-started)/1000.0)
		saw_pull = saw_pull or car._siren_maneuver.state == "pull_over"
		saw_hold = saw_hold or car._siren_maneuver.state == "hold"
		saw_merge = saw_merge or car.get_meta("emergency_yield_state","") == "resumed"
		side = maxf(side,absf(car.position.y))
		ambulance_side = maxf(ambulance_side,absf(unit.position.y))
		for i in actors.size():
			var actor: CharacterBody2D = actors[i]
			var shape: CollisionShape2D = unit.get_node("CollisionShape2D") if actor == unit else actor.collision
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape.shape
			query.transform = shape.global_transform
			query.collision_mask = 7
			query.exclude = [actor.get_rid()]
			overlaps += actor.get_world_2d().direct_space_state.intersect_shape(query,1).size()
			var motion: Vector2 = actor.global_position-before[i].origin
			var angle: float = before[i].get_rotation()+angle_difference(before[i].get_rotation(),actor.global_rotation)*.5
			max_jump = maxf(max_jump,motion.length())
			max_side_step = maxf(max_side_step,absf(motion.dot(Vector2.from_angle(angle).orthogonal())))
		if frame%300==0: print("SIREN_STATE ",frame," unit=",unit.position," ",unit._traffic_passage.state," car=",car.global_position," ",car._siren_maneuver.state," active=",car._emergency_yield_active," offsets=",car._siren_maneuver.offsets," reason=",car._siren_maneuver.route.failure if car._siren_maneuver.route else "no plan")
		var second_done: bool = not is_instance_valid(second) or second.get_meta("emergency_yield_state","") == "resumed"
		if saw_merge and second_done and unit._traffic_passage.completed>0 and unit.position.x>car.global_position.x+150: break
	check(saw_pull and saw_hold and saw_merge,"Real driver pulls over, holds until the siren passes and merges back")
	check(side>25,"Driver uses the authored clear sidewalk when the asphalt shoulder is insufficient")
	check(unit._traffic_passage.completed>0 and ambulance_side>25,"Ambulance creates a curved bypass and rejoins its road")
	if blocked_side: check(ambulance_side>90,"A solid in the first bypass forces selection of a different clear corridor")
	check(car.get_parent().get_parent()==path and absf(car.position.y)<.2,"Driver resumes the original lane without changing route")
	if is_instance_valid(second): check(second.get_meta("emergency_yield_state","") == "resumed","The second driver also yields and resumes, without competing for the first shoulder position")
	check(overlaps==0,"Neither vehicle intersects live solids during the complete maneuvers")
	check(max_jump<5 and max_side_step<.3,"Vehicle movement stays continuous and follows the turning wheels")
	print("SIREN_RESULT failures=",failures," side=",side," unit_side=",ambulance_side," overlap=",overlaps," jump=",max_jump," side_step=",max_side_step)
	if capture:
		var file := FileAccess.open("D:/geteco/artifacts/siren-passage/motion-times.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(capture_times))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
