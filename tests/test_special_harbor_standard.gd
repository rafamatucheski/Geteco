extends "res://tests/test_projected_interior_contract.gd"

class RoomProbe extends Node2D:
	var source: Node2D
	var viewport_3d: SubViewport
	var camera_3d: Camera3D
	var focus := Vector2(0,.4)
	func project_floor(_point: Vector2) -> Vector2: return source.project_floor(focus)

func run() -> void:
	create_timer(360).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	artifact_dir = "res://docs/measurements/interior-standard-0920/"
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("special_harbor_test_%d" % Time.get_ticks_usec()) + "/"
	saves._save_directory_ready = false
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]: campaign.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"): await process_frame
	world = current_scene
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	player.money = 1000000
	if OS.get_cmdline_user_args().has("service"):
		await verify_preserved_service(player)
		print("NORTHGATE_PRESERVED failures=",failures)
		world.queue_free()
		await process_frame
		quit(0 if failures == 0 else 1)
		return
	var manager := world.get_node("ResidencePrototype")
	var signatures: Array[String] = []
	for id in ["westgate_garden","quayside_house","canal_north"]:
		manager.purchase_home(id)
		check(manager.enter_home(id), "Real residence entry " + id)
		while world.get_node("Interiors").is_transitioning(): await process_frame
		var room: Node2D = manager.residence_interiors[id]
		check(room.contains_point(player.global_position), "Matching residence spawn " + id)
		check(stations_reachable(room),"All four home functions remain reachable " + id)
		var signature := str(room.art.solid_rects)
		check(not signatures.has(signature), "Distinct furniture layout " + id)
		signatures.append(signature)
		var cash := room.get_node("RoomCash")
		var money: int = player.money
		check(await walk_to(player,cash.global_position), "Clear route to reward " + id)
		for frame in 4: await physics_frame
		check(cash.collected and player.money == money + cash.amount, "Persistent contact reward " + id)
		check(player.serialize().world_pickups_collected.has(cash.pickup_id), "Reward in player save " + id)
		await verify_room(room,player,room.room_camera,room.room_display,Vector2(0,.4))
		player.global_position = room.spawn_point.global_position
		check(manager.exit_home(id), "Real residence exit " + id)
		while world.get_node("Interiors").is_transitioning(): await process_frame
		check(room.viewport_3d.size == Vector2i(2,2) and room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Empty residence target compacted " + id)
		check(manager.enter_home(id),"Residence reentry " + id)
		while world.get_node("Interiors").is_transitioning(): await process_frame
		check(cash.collected and not cash.model.visible,"Reward does not respawn " + id)
		manager.exit_home(id)
		while world.get_node("Interiors").is_transitioning(): await process_frame
	var sewer: Node2D = world.get_node("Interiors/InteriorSpaces/PoliceManholeSewer")
	player.global_position = sewer.STREET_POSITION + Vector2(-22,0)
	sewer.debug_enter_immediately(player)
	var underground: Node2D = sewer._interior_overlay
	var model: Node2D = underground.get_node("RoomModel")
	check(player.has_meta("interior_actor_presentation"),"Sewer shares player depth")
	check(sewer._secret_art.model.has_node("FloorHalo"),"Sewer shotgun has a ground ring")
	var lift: float = sewer._secret_art.model.get_node("FloorWeapon").position.y
	await create_timer(.3).timeout
	check(not is_equal_approx(lift,sewer._secret_art.model.get_node("FloorWeapon").position.y),"Sewer shotgun floats")
	await verify_room(underground,player,model.camera_3d,model.sprite_3d,Vector2(-2,0))
	sewer.debug_exit_immediately()
	check(not player.has_meta("interior_actor_presentation"),"Sewer exit restores native rig")
	await verify_preserved_service(player)
	print("SPECIAL_HARBOR_STANDARD failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func walk_to(actor: CharacterBody2D,target: Vector2) -> bool:
	for step in 240:
		var motion := target-actor.global_position
		if motion.length()<1: return true
		if actor.move_and_collide(motion.limit_length(4)) != null: return false
		await physics_frame
	return false

func stations_reachable(room: Node2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10
	query.shape = shape
	query.collision_mask = 1
	var pending: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO:true}
	var reached := {}
	var cursor := 0
	while cursor < pending.size():
		var cell := pending[cursor]
		cursor += 1
		var point: Vector2 = room.spawn_point.global_position+Vector2(cell)*16
		for station in room.stations:
			if point.distance_to(room.to_global(station.position))<25: reached[station.kind]=true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+offset
			if visited.has(next): continue
			visited[next]=true
			var candidate: Vector2 = room.spawn_point.global_position+Vector2(next)*16
			if not room.contains_point(candidate): continue
			query.transform = Transform2D(0,candidate)
			if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): pending.append(next)
	return reached.size()==4

func verify_room(room: Node2D, player: CharacterBody2D, camera: Camera3D, display: Sprite2D, focus: Vector2) -> void:
	var was_processing := room.is_processing()
	room.set_process(false)
	var manager := world.get_node("Interiors")
	manager.set_physics_process(false)
	world.set_process(false)
	check(player.has_meta("interior_actor_presentation"),"Player shares projected room " + String(room.name))
	var helper: Node = player.get_meta("interior_actor_presentation")
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
	room.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = player.global_position + Vector2(35,0)
	var visitor_helper := PRESENTATION.new()
	room.add_child(visitor_helper)
	visitor_helper.configure(visitor,camera,display)
	var probe := RoomProbe.new()
	probe.source = room
	probe.camera_3d = camera
	probe.viewport_3d = camera.get_viewport()
	probe.focus = focus
	room.add_child(probe)
	cabin = probe
	var shapes: Array = room.find_children("*","CollisionPolygon2D",true,false)
	shapes.append_array(room.find_children("*","CollisionShape2D",true,false))
	for pair in [[player,helper],[visitor,visitor_helper]]:
		var actor: CharacterBody2D = pair[0]
		var presentation: Node = pair[1]
		var other: Node2D = visitor if actor == player else player
		other.global_position = room.spawn_point.global_position
		for shape in shapes:
			if not shape.get_parent() is StaticBody2D or shape.disabled: continue
			var bounds := Rect2()
			if shape is CollisionPolygon2D:
				if shape.polygon.is_empty(): continue
				bounds = Rect2(shape.polygon[0],Vector2.ZERO)
				for point in shape.polygon: bounds = bounds.expand(point)
			elif shape.shape is RectangleShape2D:
				bounds = Rect2(-shape.shape.size*.5,shape.shape.size)
			else: continue
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				actor.global_position = shape.to_global(bounds.get_center()+direction*(bounds.size*.5+Vector2.ONE*24))
				presentation._update_scale()
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = presentation.collider.shape
				query.collision_mask = 1
				query.exclude = [actor.get_rid()]
				for attempt in 24:
					query.transform = presentation.collider.global_transform
					if actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): break
					actor.global_position += direction.normalized()*16
					presentation._update_scale()
				await physics_frame
				var target: Vector2 = shape.to_global(bounds.get_center())
				var hit := actor.move_and_collide(target-actor.global_position)
				check(hit != null and actor.global_position.distance_to(target)>1,"Swept solid " + String(room.name) + "/" + String(shape.name))
		await check_depth_occlusion(actor,presentation)
		presentation.set_process(true)
	visitor_helper.restore()
	visitor_helper.queue_free()
	visitor.queue_free()
	player.global_position = room.spawn_point.global_position
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifact_dir+String(room.name)+"-standard.png")
	probe.queue_free()
	manager.set_physics_process(true)
	world.set_process(true)
	room.set_process(was_processing)

func verify_preserved_service(player: CharacterBody2D) -> void:
	var service: Node2D = world.get_node("PayNSpray")
	check(not service.has_node("ProjectedServiceBay") and not service.has_node("ServiceCash"),"Northgate renovation/content removed as requested")
	player.global_position = service.global_position+Vector2(0,15)
	for frame in 2: await process_frame
	var personal := world.get_node("PersonalCarManager")
	personal.introduction_seen = true
	var car: CharacterBody2D = personal.car
	car.global_position = service.global_position+Vector2(0,15)
	car.rotation = -PI/2
	car.enter_vehicle(player)
	while car.has_meta("vehicle_boarding"): await process_frame
	check(car.is_driven_by_player,"Northgate real vehicle boarding")
	car.health = 45
	player.money = 500
	await create_timer(.5).timeout
	check(service.shutter.position.y < -40,"Northgate shutter opens on approach")
	check(not car.test_move(car.global_transform,Vector2(0,-145)),"Actual vehicle hull fits Northgate entrance")
	car.global_position += Vector2(0,-145)
	car.velocity = Vector2.ZERO
	var deadline := Time.get_ticks_msec()+2000
	while not service.busy and Time.get_ticks_msec()<deadline: await process_frame
	check(service.busy,"Parking starts Northgate repair")
	deadline = Time.get_ticks_msec()+8000
	while service.busy and Time.get_ticks_msec()<deadline: await process_frame
	check(not service.busy and car.health==car.max_health and player.money==400,"Repair completes and charges once")
	check(car.is_driven_by_player and car.is_physics_processing() and not player.is_control_disabled,"Repair restores driving controls")
	for frame in 5: await process_frame
	check(not car.has_meta("interior_vehicle_presentation"),"Northgate retains original vehicle presentation")
	car.global_position = service.global_position+Vector2(0,15)
	for frame in 2: await process_frame
	check(not car.has_meta("interior_vehicle_presentation"),"Vehicle leaving bay restores its native rig")
	car.force_exit_vehicle()
	player.global_position = service.global_position+Vector2(0,-55)
	player.get_node("Camera").reset_smoothing()
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifact_dir+"northgate-preserved.png")
