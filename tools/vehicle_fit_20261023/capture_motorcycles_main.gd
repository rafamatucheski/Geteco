extends SceneTree
## As três motos de produção revisadas no Main de verdade.
## Embarque público, entrada, empinada, pausa/menu, abaixamento e desmontagem segura.
## As leituras da captura documentam movimento e não são medição de FPS.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var world
var fit_case := ""
var checks := 0
var failures: Array[String] = []
var capture_dir := ""
var camera: Camera3D
var target: Node3D
var selected_ids: Array=["bike_sport","bike_cruiser","bike_urban"]
var route_anchor:=Vector3(66,.1,129)
func _initialize() -> void:
	# O modo candidato muda só a fonte do modelo; Main, Vehicle e Driving
	# continuam código de produção. Omita esta flag para inspecionar os assets instalados.
	if "--candidates" in OS.get_cmdline_user_args():
		for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
			preload("res://runtime/RedesignedFleet.gd")._scenes[id]=load("res://artifacts/vehicle-fit-20261023/motorcycles/"+id+".scn")
	process_frame.connect(update_camera)
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("WHEELIE_FLOW ",fit_case," ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(fit_case+"-"+label+".png"))
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
func update_camera() -> void:
	if is_instance_valid(camera) and is_instance_valid(target):
		camera.global_position = target.global_position+target.global_basis*Vector3(-5,2.4,2.2)
		camera.look_at(target.global_position+Vector3.UP*.9)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(23102026)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--ids="): selected_ids=Array(arg.trim_prefix("--ids=").split(","))
		elif arg=="--quay": route_anchor=Vector3(186.25,.1,80.5)
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	# Segue o contrato de estado pronto do benchmark do Main já comprovado. Uma contagem de quadros
	# não é prazo de inicialização quando a cadência do renderizador/pré-aquecimento muda.
	var startup_began := Time.get_ticks_msec()
	var startup_deadline := startup_began+300000
	var last_stage := ""
	while Time.get_ticks_msec()<startup_deadline:
		await process_frame
		var curtain: Node=world.get_node_or_null("LoadingCurtain")
		if curtain!=null:
			var stage_name := str(curtain.get("stage_message"))
			if stage_name!=last_stage:
				last_stage=stage_name
				print("MOTORCYCLES_MAIN_BOOT ",Time.get_ticks_msec()-startup_began," ",last_stage)
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		push_error("Main did not reach isolated ready state within the finite startup window")
		quit(3); return
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	controls.using_gamepad = false
	world.session.state.intro.stage = "complete"
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	for selected_id in selected_ids:
		fit_case=selected_id
		var bike = VEHICLE.new()
		bike.archetype = fit_case
		world.add_child(bike)
		var road: Curve3D = world.production.traffic_routes.route_near(route_anchor)
		var offset := road.get_closest_offset(route_anchor)
		var point := road.sample_baked(offset,true)
		var forward := road.sample_baked(minf(offset+1,road.get_baked_length()),true)-point
		if "--quay" in OS.get_cmdline_user_args():
			var admitted: Dictionary=await admit_review_road(bike)
			check(not admitted.is_empty(),"fifty metre authored road corridor is clear at admission")
			if admitted.is_empty(): bike.free(); break
			point=admitted.point
			forward=admitted.direction
			print("MOTO_MAIN_ADMITTED_ROAD ",JSON.stringify(admitted))
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
		print("MOTO_MAIN_LIFT_STATE ",fit_case," ",JSON.stringify({"health":bike.health,"max_health":bike.max_health,"occupied":world.driving.occupied,"seated":world.player.seated,"speed":bike.speed,"pitch":bike.manual_wheelie.pitch,"position":str(bike.global_position)}))
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
		world.driving.car=null
		target=null
		world.camera.make_current()
		if is_instance_valid(camera): camera.free()
		bike.free()
		await process_frame
	world.free()
	await process_frame
	print("WHEELIE_FLOW_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func admit_review_road(bike: CharacterBody3D) -> Dictionary:
	# Mesma admissão por segmento autoral usada pelos oito fluxos de carro que passam.
	# A curva de trânsito mais próxima pode dobrar; projetar a primeira tangente por50m
	# acerta indevidamente o cenário vizinho. Mantém o trânsito da cidade ativo.
	var graph=world.production.ambient_traffic_routes
	var candidates: Array[Dictionary]=[]
	for segment in graph.segments:
		var a: Vector3=segment.a
		var b: Vector3=segment.b
		if a.distance_to(b)<65.0 or absf(a.y-b.y)>.3: continue
		var direction:=a.direction_to(b)
		var offset: Vector3=graph._lane_offset(direction,segment)
		var length:=a.distance_to(b)
		for distance in [7.0,maxf(7.0,length*.5-25.0),length-57.0]:
			var point: Vector3=a+direction*distance+offset
			if point.distance_to(route_anchor)>250: continue
			candidates.append({"point":point,"direction":direction,"source":segment.id,"distance":point.distance_to(route_anchor)})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	var deadline:=Time.get_ticks_msec()+30000
	var rejected:=0
	for candidate in candidates:
		if Time.get_ticks_msec()>deadline: break
		var direction: Vector3=candidate.direction
		var yaw:=atan2(-direction.x,-direction.z)
		var clear:=true
		for index in range(14):
			var probe: Vector3=candidate.point+Vector3.UP*.12+direction*minf(index*4.0,50.0)
			world.production.region.prepare_collision_at(probe)
			await physics_frame
			if not world.production.vehicle_position_clear(bike,probe,yaw): clear=false; rejected+=1; break
		if clear:
			candidate.checked_metres=50.0
			candidate.rejected=rejected
			return candidate
	print("MOTO_MAIN_ROAD_REJECTED ",candidates.size()," rejected=",rejected)
	return {}
