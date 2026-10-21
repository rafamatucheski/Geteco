extends SceneTree
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var checks := 0
var failures: Array[String] = []
const OUT := "res://evidence/residence-immersive"
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("IMMERSIVE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count := 4) -> void:
	for i in count: await physics_frame
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/after-"+label+".png")
func temporal(stage: String) -> void:
	if not "--temporal" in OS.get_cmdline_user_args(): return
	print("TEMPORAL_READY ",stage)
	var directory := OUT+"/frames-"+stage
	DirAccess.make_dir_recursive_absolute(directory)
	var previous_limit := Engine.max_fps
	Engine.max_fps = 30
	var start := Time.get_ticks_usec()
	var count := 0
	var cycle := -1
	var times: Array = []
	while Time.get_ticks_usec()-start < 30000000:
		var next_cycle := int((Time.get_ticks_usec()-start)/5000000)
		if next_cycle != cycle:
			cycle = next_cycle
			if stage == "wardrobe": world.session.residence_services._wear("dante_classic" if cycle%2 == 0 else "dante_suit")
			else: world.session.residence_services._preview_custom_part("sand" if cycle%2 == 0 else "olive")
		await RenderingServer.frame_post_draw
		times.append((Time.get_ticks_usec()-start)/1000.0)
		root.get_texture().get_image().save_jpg(directory+"/%05d.jpg"%count,.94)
		count += 1
	Engine.max_fps = previous_limit
	FileAccess.open(directory+"/timestamps.json",FileAccess.WRITE).store_string(JSON.stringify(times))
	print("TEMPORAL_DONE ",stage)
func open(station: String) -> bool:
	world.player.teleport(world.session.room.interaction_points[station]+Vector3.UP*.08)
	await frames()
	var ok: bool = world.session.interact()
	await create_timer(.7).timeout
	return ok
func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	create_timer(240).timeout.connect(func(): push_error("IMMERSIVE timeout"); quit(3))
	root.title = "Geteco Residence Review"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.gameplay.dispatch_owned=true
	world.gameplay.emergency.dispatch_owned=true
	var session = world.session
	var services = session.residence_services
	session.weather.set_process(false)
	session.state.economy.grant_outfit("dante_suit")
	session.state.economy.grant_weapon("pistol")
	session.state.economy.grant_weapon("ak47")
	session.state.economy.grant_reward("home_workbench_test",10000)
	for id in ["westgate_garden","quayside_house","canal_north"]:
		session.activities.residence.data.active_home=id
		check(await session.enter_place(id,false),id+" enter")
		await frames(8)
		var room = session.room
		for station in services.LABELS:
			var point: Vector3=room.to_local(room.interaction_points[station])
			check(room.is_floor_clear(point,.34),id+" full body fits "+station)
		var npc = preload("res://scripts/Actor.gd").new()
		npc.controlled_automatically=true
		world.add_child(npc)
		for key in room.model.solid_rects:
			if key in ["BackWall","LeftWall","RightCutaway","SouthLeft","SouthRight","DoorBoundary"]: continue
			var rect: Rect2=room.model.solid_rects[key]
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				var distance: float=(rect.size.x if direction.x!=0 else rect.size.y)*.5+.7
				var start: Vector2=rect.get_center()+direction*distance
				if not room.is_floor_clear(Vector3(start.x,0,start.y),.34): continue
				var transform:=Transform3D(Basis.IDENTITY,room.to_global(Vector3(start.x,.08,start.y)))
				var motion:=Vector3(-direction.x,0,-direction.y)*distance*2
				check(world.player.test_move(transform,motion) and npc.test_move(transform,motion),id+" player/NPC blocked "+key+str(direction))
		npc.queue_free()
		var quality_before := {"msaa_3d":root.msaa_3d,"scaling_3d_scale":root.scaling_3d_scale,"scaling_3d_mode":root.scaling_3d_mode}
		var interpolation_before: int = world.player.visual.physics_interpolation_mode
		var shadow_before := Vector2(session.controller.sun.shadow_bias,session.controller.sun.shadow_normal_bias)
		check(await open("wardrobe"),id+" wardrobe opens")
		check(root.msaa_3d == quality_before.msaa_3d and is_equal_approx(root.scaling_3d_scale,quality_before.scaling_3d_scale),id+" close view respects selected graphics quality")
		check(services.presentation.is_active() and root.get_camera_3d()==services.presentation.camera,id+" interaction camera current")
		check(is_instance_valid(services.presentation.mirror_viewport),id+" live mirror")
		var original: String=world.player.outfit_id
		services._wear("dante_arctic")
		check(world.player.outfit_id==original,id+" rejects unowned outfit")
		services._wear("dante_suit")
		await frames()
		check(world.player.outfit_id=="dante_suit" and session.modal and services.presentation.is_active(),id+" wardrobe stays open after dressing")
		await photo(id+"-wardrobe")
		if id == "westgate_garden": await temporal("wardrobe")
		session.close_menu()
		await frames()
		check(root.get_camera_3d()==world.camera and world.player.is_physics_processing() and not world.player.input_locked,id+" cancel restores camera/physics/control")
		check(root.msaa_3d == quality_before.msaa_3d and is_equal_approx(root.scaling_3d_scale,quality_before.scaling_3d_scale) and root.scaling_3d_mode == quality_before.scaling_3d_mode,id+" original quality settings restored")
		check(world.player.visual.physics_interpolation_mode == interpolation_before,id+" visual interpolation restored")
		check(Vector2(session.controller.sun.shadow_bias,session.controller.sun.shadow_normal_bias).is_equal_approx(shadow_before),id+" city shadow settings restored")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		# parse_input_event receives window pixels, then applies viewport stretch.
		click.position = root.get_final_transform()*root.get_camera_3d().unproject_position(room.model.to_global(room.model.presentation_points.wardrobe))
		click.pressed = true
		Input.parse_input_event(click)
		await frames()
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
		check(session.modal and services.presentation.station == "wardrobe",id+" mouse click opens physical wardrobe")
		session.close_menu()
		await frames()
		check(await open("arsenal"),id+" arsenal opens")
		services._select_slot("curta")
		services.presentation.preview_weapon("pistol")
		await create_timer(.25).timeout
		check(is_instance_valid(services.presentation.weapon_preview),id+" real weapon on bench")
		await photo(id+"-pistol")
		services._select_slot("longa")
		services._set_slot("longa","ak47")
		await frames()
		services.presentation.preview_weapon("ak47")
		await create_timer(.25).timeout
		check(session.state.economy.personal_loadout().longa=="ak47" and session.modal,id+" weapon selection stays open")
		await photo(id+"-rifle")
		if id == "westgate_garden":
			var balance: int = session.state.economy.balance
			services._customize_weapon("ak47","longa","finish")
			check(services._custom_categories.get_node(services._custom_categories.focus_neighbor_bottom) == services._custom_options[0],"keyboard reaches nested customization choices")
			services._preview_custom_part("sand")
			check(not services.CUSTOM.owns(world.gameplay.customization,"ak47","sand") and session.state.economy.balance == balance,"finish preview does not purchase")
			await create_timer(.4).timeout
			await photo(id+"-custom-finish")
			await temporal("workbench")
			services._preview_custom_part("sand")
			services._apply_custom_part()
			check(services.CUSTOM.selected(world.gameplay.customization,"ak47","finish") == "sand" and session.state.economy.balance == balance-200,"finish applied at catalog price")
			services._apply_custom_part()
			check(session.state.economy.balance == balance-200,"installed finish cannot charge twice")
			services._customize_weapon("ak47","longa","muzzle")
			services._preview_custom_part("suppressor")
			await create_timer(.4).timeout
			await photo(id+"-custom-muzzle")
			services._apply_custom_part()
			check(services.CUSTOM.selected(world.gameplay.customization,"ak47","muzzle") == "suppressor","accessory changes real combat customization")
			check(is_instance_valid(services.presentation.weapon_preview),"custom weapon remains visible on bench")
		session.close_menu()
		check(not room.model.bench_light.visible,id+" bench lamp inactive outside interaction")
		check(await open("food"),id+" fridge opens")
		check(absf(room.model.fridge_hinge.rotation.y)>1.5,id+" physical fridge door opens")
		await photo(id+"-fridge")
		session.close_menu()
		world.gameplay.health=40
		await open("food")
		services._consume("meal")
		check(world.gameplay.health==75 and is_zero_approx(room.model.fridge_hinge.rotation.y),id+" meal heals and door closes")
		await open("food")
		services._consume("drink")
		check(world.gameplay.health==90,id+" drink heals")
		if id == "westgate_garden":
			await open("food")
			world.gameplay.health = 85
			await frames(3)
			check(not session.modal and not services.presentation.is_active() and not world.player.input_locked,"damage interrupts interaction and restores control")
		await open("time")
		world.gameplay.stars=1
		services._rest_for(15)
		check(not is_instance_valid(services._rest_tween),id+" wanted blocks rest")
		world.gameplay.stars=0
		var start_time: float=session.weather.time_of_day
		services._rest_for(15)
		await create_timer(1.3).timeout
		check(services._rest_progress>0 and world.player.visual.global_position.distance_to(world.player.global_position)>1,id+" lies on bed and clock animates")
		await photo(id+"-rest")
		session.close_menu()
		check(is_equal_approx(session.weather.time_of_day,start_time),id+" interrupted rest does not skip time")
		await open("time")
		services._rest_for(15)
		await create_timer(5).timeout
		check(is_equal_approx(session.weather.time_of_day,fposmod(start_time+15.0/1440.0,1.0)) and not session.modal,id+" completed rest advances chosen minutes once")
		check(world.player.visual.position.length()<.1 and world.player.is_physics_processing(),id+" getting up restores visual/body")
		if id=="westgate_garden":
			check(await open("backpack"),"take home backpack")
			check(session.state.economy.grid_snapshot().bag=="backpack" and not room.model.backpack_prop.visible,"backpack worn and removed from corner")
			check(not services._backpack_available(),"backpack cannot duplicate")
			var restored=preload("res://systems/economy/Economy.gd").new()
			check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(session.state.economy.snapshot()))) and restored.grid_snapshot().bag=="backpack" and services.BACKPACK_CLAIM in restored.grid_snapshot().claimed,"backpack/claim persist JSON")
			check(services.storage.unlocked(),"home chest bound to real backpack")
			session.state.economy.grant_item("sandwich")
			check(services.storage.deposit(session.activities.residence.data.chest,"sandwich") and services.storage.withdraw(session.activities.residence.data.chest,"sandwich"),"chest transfers through actual inventory")
			var previous_path: String = session.controller.store.path
			session.controller.store.path = OUT+"/house-save.json"
			session.controller.no_save = false
			check(session.save_game(true),"full house save published in isolated file")
			var loaded = preload("res://runtime/GameState.gd").new()
			var loaded_ok: bool = session.controller.store.load_into(loaded).get("ok",false)
			check(loaded_ok and loaded.economy.grid_snapshot().bag == "backpack" and services.CUSTOM.selected(loaded.combat_state.get("customization",{}),"ak47","finish") == "sand" and services.CUSTOM.selected(loaded.combat_state.get("customization",{}),"ak47","muzzle") == "suppressor","full save reloads backpack and installed customization")
			session.controller.no_save = true
			session.controller.store.path = previous_path
		await photo(id+"-room")
		check(await session.leave_place(),id+" leave")
		check(not services.presentation.is_active() and not world.player.input_locked,id+" exit releases controls")
	print("IMMERSIVE_RESULT checks=",checks," failures=",failures.size()," ",failures)
	world.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
