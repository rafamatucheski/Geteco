extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var output_dir := OS.get_temp_dir().path_join("geteco-port-boss-inline-0923")
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("test-saves"))
	root.get_node("SaveManager")._save_dir = output_dir.path_join("test-saves")+"/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag),true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	var garage = get_first_node_in_group("port_boss_garage")
	var p: CharacterBody2D = world.get_node("Player")
	world._walk()
	world.weather.is_dynamic_time = false
	for hour in [0.99,1.0,4.99,5.0,23.0]:
		world.weather.time_of_day = hour/24.0
		p.global_position = garage.EXTERIOR
		garage.cooldown = 0
		var expected: bool = hour>=1 and hour<5
		check(garage.enter()==expected,"Schedule boundary %s" % hour)
		if expected:
			p.global_position=garage.spawn_point.global_position
			garage.cooldown=0
			check(garage.leave(),"Exit allowed")
			p.global_position=garage.EXTERIOR
	world.weather.time_of_day=1.5/24
	var bridge=world.get_node("CobraCampaign")
	bridge.ledger.data.day_elapsed=fposmod(1.5/24.0-.35,1.0)*bridge.LEDGER.DAY_SECONDS
	p.global_position=garage.EXTERIOR
	garage.cooldown=0
	check(garage.enter(),"Pedestrian enters")
	p.global_position=garage.spawn_point.global_position
	p.velocity=Vector2.ZERO
	for i in 4: await physics_frame
	check(garage.contains_point(p.global_position) and garage.active,"Pedestrian occupies physical garage")
	check(garage.cars.size()==5,"Five actual drivable cars")
	check(garage.boss.active_archetype_id=="porto_rosso","Exclusive model identity")
	check(garage.boss.body_model.is_open_top(),"Open cockpit")
	check(garage.boss.body_model.get_parent()==garage.showroom.viewport_3d,"Car shares room depth")
	for person in [p,garage.guards[0]]:
		check(person.has_meta("interior_actor_presentation"),"Player and guard use shared depth")
		await depth_check(garage,person)
	await photo(garage,"garagem",false)
	for i in 3: await physics_frame
	await verify_solids(garage,p)
	if "--solids-only" in OS.get_cmdline_user_args():
		p.global_position=garage.EXTERIOR
		garage.set_npc_rendering_active(false)
		check(not p.has_meta("interior_actor_presentation") and p.model_root.get_parent()==p.viewport_3d,"Exterior respawn restores native player rig")
		print("PORT_BOSS_SOLIDS checks=%d failures=%s" % [checks,failures])
		quit(0 if failures.is_empty() else 1)
		return
	var walk_start: Vector2=p.global_position
	Input.action_press("move_up")
	await create_timer(.45).timeout
	Input.action_release("move_up")
	check(p.global_position.distance_to(walk_start)>10,"Native walking moves through clear aisle")
	var car: CharacterBody2D=garage.boss
	p.global_position=garage.showroom.to_global(garage.showroom.project_floor(Vector2(1.8,-4)))
	garage.detach_actor(p)
	car.enter_vehicle(p)
	for i in 4: await physics_frame
	check(car.is_driven_by_player,"Player steals boss car")
	check(garage.alerted,"Guards react immediately")
	check(float(garage.data().alarm_remaining)>14,"15 second escape deadline")
	await create_timer(2.2).timeout
	var occupant=car.body_model.get_node_or_null("DanteCabinOccupant")
	check(occupant!=null and occupant.seated,"Dante remains seated in convertible")
	await photo(garage,"porto-rosso-dante",true)
	for guard in garage.guards:
		check(guard.security_alert==3 and guard.target==car,"Real guard targets stolen car")
	garage.capture_for_save()
	check(garage.data().car.health==car.health,"Boss state captured for disk save")
	world.weather.time_of_day=5.1/24
	garage.cooldown=0
	car.rotation=0
	car.global_position=garage.showroom.to_global(garage.showroom.project_floor(Vector2(8.4,0)))
	car.velocity=Vector2.ZERO
	for i in 4: await physics_frame
	while not car._drive_input_armed: await physics_frame
	Input.action_press("move_up")
	var exit_deadline := Time.get_ticks_msec()+4500
	while garage.contains_point(car.global_position) and Time.get_ticks_msec()<exit_deadline: await physics_frame
	Input.action_release("move_up")
	check(not garage.contains_point(car.global_position),"Native driving exits through aisle and ramp after closing time")
	check(not car.has_meta("interior_vehicle_presentation"),"Exterior vehicle presentation restored")
	check(car.body_model.get_parent()==car.body_viewport,"Driver and car return to native viewport")
	check(not bool(garage.data().police_called),"Police do not arrive early")
	check(root.get_node("WantedManager").current_stars==0,"Garage theft does not call police before 15 seconds")
	await create_timer(maxf(0,float(garage.data().alarm_remaining))+.2).timeout
	check(bool(garage.data().police_called),"Police called after deadline")
	check(root.get_node("WantedManager").current_stars>=3,"Police dispatch integrated")
	var neco=world.get_node("ChopShopZone")
	check(neco._reward(car)==50000,"Neco offers exactly 50000")
	car.force_exit_vehicle()
	root.get_node("WantedManager").clear_wanted_level()
	for guard in garage.guards: guard.set_physics_process(false)
	car.global_position=neco.to_global(neco.dock)
	car.velocity=Vector2.ZERO
	p.global_position=car.global_position+Vector2(0,48)
	var previous_money: int=p.money
	var previous_scrap: int=p.chop_shop_total_scrap
	var achievements: Array=p.unlocked_achievements.duplicate()
	check(neco.confirm_delivery(car),"Actual Neco delivery accepts boss car")
	await create_timer(15.0).timeout
	var achievement_bonus := 0
	for id in p.unlocked_achievements:
		if not achievements.has(id): achievement_bonus+=p.ACHIEVEMENT_CATALOG.cash_reward(id)
	print("NECO_PAYMENT money_delta=",p.money-previous_money," achievement_bonus=",achievement_bonus," scrap_delta=",p.chop_shop_total_scrap-previous_scrap)
	check(p.money==previous_money+50000+achievement_bonus and p.chop_shop_total_scrap-previous_scrap==50000,"Actual crusher pays exactly 50000 plus separate achievement bonuses")
	check(garage.data().status=="delivered","One-off payment persisted")
	var copy=garage.FACTORY.spawn_parked_vehicle(world,"DuplicateBoss",Vector2(1000,1000),0,"porto_rosso",2)
	check(neco._reward(copy)==0 and not neco.eligible(copy),"Duplicate boss cannot be sold twice")
	var saved: Dictionary=root.get_node("CampaignState").to_save_data()
	root.get_node("CampaignState").restore_from_save(JSON.parse_string(JSON.stringify(saved)))
	check(garage.data().status=="delivered" and neco._reward(copy)==0,"JSON save/load preserves paid status")
	var saved_slot: Dictionary = root.get_node("SaveManager").save_game("port_boss_test","Garage integration test")
	check(saved_slot.get("success",false),"Real disk save succeeds after delivery")
	print("PORT_BOSS_TEST checks=%d failures=%s" % [checks,failures])
	world.queue_free()
	quit(0 if failures.is_empty() else 1)

func depth_check(garage: Node, person: CharacterBody2D) -> void:
	if DisplayServer.get_name()=="headless": return
	paused=true
	var helper: Node=person.get_meta("interior_actor_presentation")
	var view=garage.showroom
	var original: Vector2=person.global_position
	person.global_position=view.to_global(view.project_floor(Vector2(9.7,4.0)))
	helper._update_scale()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_image: Image=view.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_image: Image=view.viewport_3d.get_texture().get_image()
	var pixel: Vector2=view.camera_3d.unproject_position(helper.anchor.position+Vector3(0,.9,0))
	var behind := difference(visible_image,hidden_image,pixel)
	person.global_position=view.to_global(view.project_floor(Vector2(8.4,4.0)))
	helper._update_scale()
	helper.anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	visible_image=view.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	hidden_image=view.viewport_3d.get_texture().get_image()
	pixel=view.camera_3d.unproject_position(helper.anchor.position+Vector3(0,.9,0))
	var clear := difference(visible_image,hidden_image,pixel)
	print("GARAGE_DEPTH actor=",person.name," behind=",behind," clear=",clear)
	check(behind<clear*.25 and clear>50,"Authored pillar occludes actor with visible control")
	person.global_position=original
	helper._update_scale()
	helper.anchor.show()
	paused=false

func difference(a: Image,b: Image,pixel: Vector2) -> int:
	var changed := 0
	for y in range(int(pixel.y)-20,int(pixel.y)+20):
		for x in range(int(pixel.x)-12,int(pixel.x)+12):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): changed+=1
	return changed

func photo(garage: Node, filename: String, close: bool) -> void:
	if DisplayServer.get_name()=="headless": return
	paused=true
	var view=garage.showroom
	var old_size: Vector2i=view.viewport_3d.size
	var old_transform: Transform3D=view.camera_3d.transform
	var old_zoom: float=view.camera_3d.size
	view.viewport_3d.size=Vector2i(3200,2400)
	if close:
		var target: Vector3=garage.boss.body_model.position+Vector3(0,.65,0)
		view.camera_3d.position=target+Vector3(5,5,7)
		view.camera_3d.look_at(target)
		view.camera_3d.size=6.8
	view.viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	await process_frame
	await RenderingServer.frame_post_draw
	view.viewport_3d.get_texture().get_image().save_png(OS.get_temp_dir().path_join("geteco-port-boss-inline-0923").path_join(filename+".png"))
	view.viewport_3d.size=old_size
	view.camera_3d.transform=old_transform
	view.camera_3d.size=old_zoom
	paused=false

func verify_solids(garage: Node,p: CharacterBody2D) -> void:
	var solids: Array=garage.showroom.find_children("*","CollisionPolygon2D",true,false)
	var solid_body := solids[0].get_parent() as StaticBody2D
	var old_layer: int=solid_body.collision_layer
	# The inline showroom overlaps district seawalls and the exterior shutter.
	# Use a dedicated test layer to probe its authored footprints in isolation.
	solid_body.collision_layer=1 << 29
	for person in [p,garage.guards[0]]:
		person.set_physics_process(false)
		var original: Vector2=person.global_position
		var mask: int=person.collision_mask
		person.collision_mask=1 << 29
		for shape in solids:
			# Individual mesh footprint coverage. Integrated movement is tested separately.
			for other in solids: other.disabled = other != shape
			await physics_frame
			await physics_frame
			var center := Vector2.ZERO
			for point in shape.polygon: center+=point
			center=shape.to_global(center/shape.polygon.size())
			for edge in shape.polygon.size():
				var a: Vector2=shape.to_global(shape.polygon[edge])
				var b: Vector2=shape.to_global(shape.polygon[(edge+1)%shape.polygon.size()])
				var middle: Vector2=(a+b)*.5
				var outward := Vector2((b-a).y,-(b-a).x).normalized()
				if outward.dot(middle-center)<0: outward=-outward
				# The compact facade brings thin walls within the actor's body radius.
				person.global_position=middle+outward*28
				var hit: KinematicCollision2D=person.move_and_collide(-outward*56,true)
				var owner_matches := false
				if hit!=null and hit.get_collider()==shape.get_parent():
					owner_matches=hit.get_collider_shape()==shape
				check(owner_matches,"Real actor sweep hits authored "+String(shape.name)+" edge "+str(edge))
		for shape in solids: shape.disabled=false
		person.global_position=original
		person.collision_mask=mask
		person.set_physics_process(true)
	solid_body.collision_layer=old_layer
