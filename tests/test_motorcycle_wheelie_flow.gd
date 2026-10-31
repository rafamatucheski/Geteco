extends SceneTree
## Main integration: public boarding, touch controls, pause/menu and dismount.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var world
var checks := 0
var failures: Array[String] = []
var capture_dir := ""
var camera: Camera3D
var target: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("WHEELIE_FLOW ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))
func motion(prefix: String, count: int, stride: int) -> void:
	for i in count:
		await frames(stride)
		await capture("%s-%02d"%[prefix,i])
func touch(action: String, finger: int, down: bool) -> void:
	var overlay = world.find_child("AndroidControls",true,false)
	if overlay == null or not overlay.buttons.has(action): check(false,"touch action present: "+action); return
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = overlay.buttons[action].rect.get_center()
	event.pressed = down
	root.push_input(event,true)
	await process_frame
	await process_frame
func _process(_delta: float) -> bool:
	if is_instance_valid(camera) and is_instance_valid(target):
		camera.global_position = target.global_position+target.global_basis*Vector3(-5,2.4,2.2)
		camera.look_at(target.global_position+Vector3.UP*.9)
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	controls.using_gamepad = false
	world.session.state.intro.stage = "complete"
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	var bike = VEHICLE.new()
	bike.archetype = "bike_sport"
	world.add_child(bike)
	var road: Curve3D = world.production.traffic_routes.route_near(Vector3(66,.1,129))
	var offset := road.get_closest_offset(Vector3(66,.1,129))
	var point := road.sample_baked(offset,true)
	var forward := road.sample_baked(minf(offset+1,road.get_baked_length()),true)-point
	bike.place(point+Vector3.UP*.12,atan2(-forward.x,-forward.z))
	world.player.teleport(bike.driver_door_anchor(-1))
	world.production.region.set_focus(point)
	await frames(20)
	check(world.driving.interact(),"public boarding accepts street motorcycle")
	for i in 300:
		await physics_frame
		if bike.controlled and not world.driving.is_body_transition_active(): break
	check(world.driving.occupied and bike.controlled and world.player.visible,"boarding gives control and shows rider")
	target = bike
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 6
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		world.add_child(camera)
		camera.make_current()
	await capture("street-grounded")
	var overlay = world.find_child("AndroidControls",true,false)
	if overlay != null:
		overlay._refresh()
		check(overlay.buttons.has("motorcycle_wheelie"),"street bike exposes touch wheelie")
		await touch("accelerate",90,true)
		await touch("motorcycle_wheelie",91,true)
	else:
		Input.action_press("move_up")
		Input.action_press("motorcycle_wheelie")
	if capture_dir.is_empty(): await frames(160)
	else:
		await motion("street-lift",20,6)
		await frames(40)
	check(bike.manual_wheelie.pitch > .25,"Main player input raises front while moving")
	await capture("street-wheelie")
	controls.sprint_toggled = false
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_STICK
	pad.pressed = true
	controls.observe_event(pad)
	check(not controls.sprint_toggled,"L3 wheelie does not toggle on-foot sprint")
	pad.pressed = false
	controls.observe_event(pad)
	controls.using_gamepad = false
	var paused_pose: Transform3D = bike.global_transform
	paused = true
	for i in 8: await process_frame
	check(bike.global_transform.is_equal_approx(paused_pose),"pause holds motorcycle still")
	paused = false
	world.session._menu("Wheelie integration")
	await frames(3)
	check(bike.manual_wheelie.pitch == 0,"modal menu clears street wheelie")
	world.session.close_menu()
	if overlay != null: overlay.release_all()
	for action in ["move_up","accelerate","motorcycle_wheelie"]: Input.action_release(action)
	Input.action_press("handbrake")
	await frames(120)
	Input.action_release("handbrake")
	check(world.driving.leave(),"public motorcycle dismount succeeds")
	for i in 300:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	check(not world.driving.occupied and world.player.is_physics_processing() and absf(world.player.visual.rotation.x) < .001,"dismount restores upright walking")
	await capture("street-dismounted")
	world.player.teleport(COURSE.ENTRY+Vector3.UP*.15)
	world.production.region.set_focus(COURSE.ENTRY)
	world.session.state.economy.grant_reward("wheelie_flow",1000)
	await frames(180)
	check(world.session.motocross.rent_bike(),"public rental mounts motocross bike")
	var dirt = world.session.motocross.player_bike
	if not is_instance_valid(dirt): world.free(); quit(1); return
	target = dirt
	# O aluguel muda o contexto de interação/arma. Deixa a sobreposição de toque assentar
	# antes de começar dedos novos para que a atualização de contexto dela não os solte.
	await frames(12)
	if overlay != null:
		overlay._refresh()
		check(overlay.buttons.has("motorcycle_wheelie"),"motocross exposes touch wheelie")
		await touch("accelerate",90,true)
		await touch("motorcycle_wheelie",91,true)
		check(Input.is_action_pressed("accelerate") and Input.is_action_pressed("motorcycle_wheelie"),"raw motocross touches reach both buttons")
	else:
		Input.action_press("move_up")
		Input.action_press("motorcycle_wheelie")
	if capture_dir.is_empty(): await frames(80)
	else: await motion("motocross-lift",10,8)
	print("WHEELIE_FLOW_DIRT input=",Input.get_action_strength("accelerate")," lift=",Input.is_action_pressed("motorcycle_wheelie")," brake=",Input.is_action_pressed("handbrake")," speed=",dirt.speed," pitch=",dirt.manual_wheelie.pitch," grounded=",dirt.is_on_floor()," state=",dirt.crash_state," mounted=",world.session.motocross.mounted)
	check(dirt.manual_wheelie.pitch > .25,"Main motocross controller forwards manual lift")
	await capture("motocross-wheelie")
	if overlay != null:
		await touch("motorcycle_wheelie",91,false)
		await touch("accelerate",90,false)
	for action in ["move_up","accelerate","motorcycle_wheelie"]: Input.action_release(action)
	Input.action_press("handbrake")
	await frames(70)
	Input.action_release("handbrake")
	check(dirt.manual_wheelie.pitch == 0,"motocross controller releases lift and lowers front")
	check(world.session.motocross.dismount(),"public motocross dismount succeeds")
	check(world.player.visible and not world.player.input_locked,"motocross returns player control")
	world.free()
	await process_frame
	print("WHEELIE_FLOW_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
