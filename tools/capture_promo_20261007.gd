extends SceneTree
## Promotional capture only. No production changes; requires --no-save.
## Run with Godot .NET --write-movie <scene>.avi --fixed-fps 30.
var world
var scene_id := "motocross"
var output := "D:/geteco/artifacts/promo-20261007"
var camera: Camera3D
var subject: Node3D
var race
var pilot
var shot_clock := 0.0
var take_frames := 0
var shots: Array[Dictionary] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--promo-scene="): scene_id = arg.trim_prefix("--promo-scene=")
		if arg.begins_with("--promo-out="): output = arg.trim_prefix("--promo-out=")
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

func require(ok: bool, message: String) -> bool:
	print("PROMO_CHECK ", ok, " ", message)
	if not ok: push_error(message); quit(2)
	return ok

func run() -> void:
	if not require("--no-save" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless", "Rendered capture with saves disabled"): return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920,1080)
	root.canvas_cull_mask = 0
	root.get_node("V2Settings").mute_unfocused = false
	AudioServer.set_bus_mute(0,false)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if not require(world.session != null and world.session.ready_for_play,"Main ready"): return
	if not require(world.session.controller.no_save,"Save protection active"): return
	if not world.session.state.place_id.is_empty(): await world.session.leave_place()
	var intro: Dictionary = world.session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not require(world.session.state.intro.restore_snapshot(intro),"Intro fixture"): return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not require(world.dispatch.router._native != null,"Native .NET route backend"): return
	weather(.45)
	world.gameplay.health = 100000
	await frames(60)
	match scene_id:
		"motocross": await motocross()
		"downhill": await downhill()
		"drag": await drag()
		"drag_chase": await drag()
		"combat": await combat()
		_: await extra_scene()
	var file := FileAccess.open(output.path_join(scene_id+"-shots.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scene":scene_id,"fps":30,"resolution":[1920,1080],"hud":false,"no_save":true,"shots":shots},"\t"))
	print("PROMO_DONE ",scene_id)
	quit()

func extra_scene() -> void:
	require(false,"Unknown promo scene: "+scene_id)

func weather(hour: float) -> void:
	world.session.weather.time_of_day = hour
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather._update()
	world.session.weather.set_process(false)

func clean_overlay() -> void:
	root.canvas_cull_mask = 0
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	for label in world.find_children("RiderTag","Label3D",true,false): label.hide()
	if scene_id == "motocross" and is_instance_valid(race) and is_instance_valid(race._marker): race._marker.hide()
	if scene_id == "combat":
		for pickup in world.gameplay._loot:
			if is_instance_valid(pickup): pickup.hide()

func make_camera(size: float) -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.far = 1500
	world.add_child(camera)
	camera.make_current()

func aim_camera(focus: Vector3, offset: Vector3) -> void:
	camera.global_position = focus+offset
	camera.look_at(focus,Vector3.UP)
	camera.make_current()

func take(label: String, count: int, update: Callable) -> void:
	clean_overlay()
	var begin := Engine.get_frames_drawn()
	print("PROMO_TAKE ",label," begin=",begin)
	for i in count:
		shot_clock = float(i)/30.0
		update.call(i)
		clean_overlay()
		await RenderingServer.frame_post_draw
		if i%30 == 0:
			root.get_texture().get_image().save_jpg(output.path_join("%s-%s-%03d.jpg"%[scene_id,label,i/30]),.92)
		await process_frame
	shots.append({"label":label,"start_frame":begin,"frames":count,"seconds":float(count)/30.0})

func motocross() -> void:
	world.player.teleport(Vector3(-224,.15,-37))
	world.production.region.set_focus(world.player.position)
	await frames(150)
	world.session.state.economy.grant_reward("promo_capture",1000)
	race = world.session.motocross
	race.selected_model = 0
	if not require(race.start_race(0),"Motocross started"): return
	race.autopilot = true
	await frames(110)
	subject = race.player_bike
	make_camera(23)
	await take("race",420,func(_i):
		var focus := subject.global_position+Vector3.UP*.8
		aim_camera(focus,Vector3(13,20,24))
	)

func travel(region: String, point: Vector3) -> bool:
	if not require(world.production.travel(region,point),"Travel "+region): return false
	for i in 1200:
		await process_frame
		if not world.production.travel_busy and world.session.ready_for_play: break
	await frames(120)
	return require(world.session.state.region_id == region,"Arrived "+region)

func board(car) -> bool:
	if not require(is_instance_valid(car),"Vehicle spawned"): return false
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	await frames(4)
	if not require(world.driving.interact(),"Boarding begins"): return false
	await frames(120)
	return require(world.driving.occupied and world.driving.car==car,"Vehicle occupied")

func downhill() -> void:
	var coordinator := get_first_node_in_group("mountain_activities")
	race = coordinator.components.get("mountain_downhill")
	var start: Vector3 = race.course.start_position()
	var right: Vector3 = race.course.direction(10).cross(Vector3.UP).normalized()
	if not await travel("mountain",start+right*3.4): return
	var pose: Transform3D = race.course.grid(6)
	var car = world.production.spawn_vehicle("sport_coupe",pose.origin,pose.basis.get_euler().y)
	if not await board(car): return
	weather(.86)
	if not require(race.perform("start"),"Seven-car downhill started"): return
	if not require(race.racers.size()==7,"Six rivals plus Dante"): return
	pilot = preload("res://activities/mountain_downhill/MountainDownhillDriver.gd").new()
	pilot.setup(car,race.course,0)
	pilot.lane = -1.8
	pilot.desired_lane = -1.8
	subject = car
	physics_frame.connect(downhill_tick)
	await frames(105)
	make_camera(29)
	await take("descent",480,func(_i):
		var forward: Vector3 = -subject.global_basis.z
		var focus := subject.global_position+forward*5+Vector3.UP
		aim_camera(focus,subject.global_basis.z*24+Vector3.UP*24+subject.global_basis.x*8)
	)

func downhill_tick() -> void:
	if is_instance_valid(race) and race.active and race.racers.size()==7:
		pilot.tick(1.0/60.0,race.countdown>0,int(race.racers[6].run.checkpoint))

func drag() -> void:
	var fixture: Dictionary = preload("res://tests/fixtures/NorthGatewayFixtures.gd").full_snapshot(world.player.global_position,true,true)
	if not require(world.session.state.campaign.restore_snapshot(fixture.campaign),"Completed campaign capture fixture"): return
	race = world.session.desert.drag
	if not await travel("desert",race.staging_point): return
	var car = world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not await board(car): return
	weather(.70)
	if not require(race.perform("start"),"Physical drag started"): return
	physics_frame.connect(drag_tick)
	await frames(112)
	if scene_id == "drag_chase":
		make_camera(23)
		await take("acceleration",450,func(_i):
			if race.racers.size()!=2: return
			var a: Vector3 = race.racers[0].car.global_position
			var b: Vector3 = race.racers[1].car.global_position
			var focus: Vector3 = a.lerp(b,.5)+race.direction*3+Vector3.UP
			aim_camera(focus,-race.direction*26+Vector3.UP*23)
		)
	else:
		await take("acceleration",450,func(_i): pass)

func drag_tick() -> void:
	if not is_instance_valid(race) or not race.active: return
	if race.phase=="staging": race._throttle_override = .54
	else:
		race._throttle_override = 1.0
		race._nitro_override = true
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()

func combat() -> void:
	var gameplay = world.gameplay
	var state = world.session.state
	state.economy.activate_arsenal_cheat()
	# Keep background traffic out of the staged fight's camera corridor.
	# This affects this unsaved filming session only.
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and vehicle.traffic:
			vehicle.set_physics_process(false)
	var street: Vector3 = world.production.nearest_road(world.driving.car.global_position+Vector3(0,0,18))
	world.production.region.set_focus(street)
	world.player.teleport(street+Vector3.UP*.1)
	await frames(90)
	var car
	for offset in [Vector3(0,0,12),Vector3(12,0,0),Vector3(-12,0,0),Vector3(0,0,-12),Vector3(0,0,24)]:
		var candidate: Vector3 = world.production.nearest_road(street+offset)+Vector3.UP*.12
		for yaw in [0.0,PI*.5]:
			car = world.production.spawn_vehicle("sport_coupe",candidate,yaw)
			if is_instance_valid(car): break
		if is_instance_valid(car): break
		await frames(2)
	if not require(is_instance_valid(car),"Combat target vehicle"): return
	street = car.global_position+Vector3(3,0,7)
	world.player.teleport(street)
	await frames(25)
	subject = world.player
	make_camera(15)
	state.equip_weapon("m4a1")
	await frames(30)
	var enemies: Array[Node3D] = []
	for offset in [Vector3(-2,0,-8),Vector3(3,0,-12)]:
		var enemy := preload("res://gameplay/CobraAgent.gd").new()
		enemy.configure(gameplay,2)
		world.add_child(enemy)
		enemy.global_position = street+offset+Vector3.UP*.1
		enemy.cooldown = .15+enemies.size()*.3
		enemies.append(enemy)
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	Input.action_press("aim")
	await take("fire",180,func(i):
		var target: Vector3 = car.global_position
		for enemy in enemies:
			if not enemy.dead: target=enemy.global_position; break
		var flat := (target-subject.global_position).normalized()
		var right: Vector3 = world.camera.global_basis.x
		var down: Vector3 = world.camera.global_basis.z
		right.y=0; down.y=0
		controls.touch_aim = Vector2(flat.dot(right.normalized()),flat.dot(down.normalized()))
		aim_camera(subject.global_position.lerp(target,.4)+Vector3.UP*.8,Vector3(5,18,22))
		if i>12 and i<140 and i%9==0: gameplay.fire_at(target)
	)
	state.equip_weapon("rpg")
	await frames(24)
	await take("explosion",150,func(i):
		aim_camera(subject.global_position.lerp(car.global_position,.4)+Vector3.UP*.8,Vector3(5,18,22))
		if i==12: print("PROMO_ROCKET ",gameplay.fire_at(car.global_position))
	)
	Input.action_release("aim")
