extends SceneTree
var world
var folder := "res://evidence/supermarket-20261002/before"
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	print("MARKET_MAIN ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func walk_to(target: Vector3) -> bool:
	for i in 900:
		var direction: Vector3 = target-world.player.global_position
		direction.y = 0
		if direction.length()<.15:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func record_lighting() -> void:
	var previous_cap := Engine.max_fps
	Engine.max_fps = 30
	var stamps: Array = []
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<30000000:
		await RenderingServer.frame_post_draw
		var stamp := Time.get_ticks_usec()
		var frame := Engine.get_frames_drawn()
		root.get_texture().get_image().save_jpg(folder.path_join("motion-%04d.jpg"%stamps.size()),.88)
		stamps.append({"us":stamp-started,"drawn":frame})
	Engine.max_fps = previous_cap
	FileAccess.open(folder.path_join("motion.json"),FileAccess.WRITE).store_string(JSON.stringify(stamps))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): folder = "res://evidence/supermarket-20261002/"+arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	for i in 600:
		if not world.session.is_transition_blocked() and not world.player.input_locked: break
		await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	var point := Vector3(990.0/16, .08, 140.0/16+8)
	world.player.teleport(point)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	await frames(240)
	await shot("exterior")
	if "--before" in OS.get_cmdline_user_args(): quit(); return
	# Approach on foot: the production door controller owns admission.
	world.player.automatic_direction = Vector3.FORWARD
	for i in 900:
		await physics_frame
		if world.session.state.place_id == "harbor_supermarket" and not world.session.is_transition_blocked(): break
	world.player.automatic_direction = Vector3.ZERO
	check(world.session.state.place_id == "harbor_supermarket","physical exterior approach opens door and enters")
	if not failures.is_empty(): quit(1); return
	await frames(120)
	await shot("interior")
	var room = world.session.room
	check(world.session.room_npcs.size()==2 and room.customers.size()==4,"two cashiers and four customers")
	check(await walk_to(room.to_global(Vector3(0,0,2.65))),"walk from entrance into main aisle")
	check(await walk_to(room.to_global(Vector3(-4.15,0,2.65))),"walk in front of gondolas")
	check(await walk_to(room.interaction_points.service),"reach customer side of checkout")
	world.session.state.economy.grant_reward("supermarket_review",2000)
	world.gameplay.health = 50
	check(world.session.interact() and world.session.modal,"functional purchase menu opens at checkout")
	await frames(8)
	await shot("checkout")
	var shop = load("res://runtime/SupermarketShop.gd")
	var market_ui = world.hud.get_node_or_null("SupermarketPanel")
	check(market_ui!=null and market_ui.cards.size()==7,"focused product cards replace generic menu")
	if market_ui!=null:
		check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(market_ui.shell.get_global_rect()),"market panel fits gameplay viewport")
		check(market_ui.shell.get_global_rect().encloses(market_ui.close_button.get_global_rect()),"return button remains visible")
		market_ui.cards.apple.button.grab_focus()
		var input := InputEventAction.new()
		input.action = "ui_down"
		input.pressed = true
		Input.parse_input_event(input)
		await frames(3)
		check(root.gui_get_focus_owner()==market_ui.cards.juice.button,"controller focus moves by grid row")
		input = InputEventAction.new(); input.action="ui_down"; input.pressed=false
		Input.parse_input_event(input)
	var result: Dictionary = shop.buy(world.session,"apple")
	check(result.ok,"food purchase through real shop")
	await frames(4)
	await shot("purchase-feedback")
	world.session.close_menu()
	var inventory: Dictionary = world.session.state.economy.grid_snapshot()
	var index := -1
	for i in inventory.pockets.size():
		if inventory.pockets[i].id == "apple": index = i
	check(index>=0 and world.session.field_inventory.consume("pockets",index),"purchased food consumed through inventory")
	check(world.gameplay.health==58,"food actually heals player")
	world.gameplay.armor = 0
	check(shop.buy(world.session,"armor").ok and world.gameplay.armor==100,"purchased vest equips full protection")
	market_ui = world.hud.get_node_or_null("SupermarketPanel")
	if market_ui!=null:
		market_ui._select("Colete")
		await frames(4)
		await shot("armor")
	world.session.close_menu()
	await walk_to(room.to_global(Vector3(-4.15,0,2.65)))
	await walk_to(room.to_global(Vector3(0,0,2.65)))
	await frames(180)
	await shot("customers")
	if "--temporal" in OS.get_cmdline_user_args(): await record_lighting()
	var refs: Array[WeakRef] = []
	for customer in room.customers: refs.append(weakref(customer))
	await walk_to(room.to_global(Vector3(0,0,5.8)))
	world.player.automatic_direction = Vector3.BACK
	for i in 600:
		await physics_frame
		if world.session.state.place_id.is_empty() and not world.player.input_locked: break
	world.player.automatic_direction = Vector3.ZERO
	check(world.session.state.place_id.is_empty(),"walk through exit returns to Harbor")
	await frames(10)
	check(refs.all(func(ref):return ref.get_ref()==null),"customers released on exit")
	check(world.session.room_npcs.is_empty(),"cashiers released on exit")
	check(not shop.buy(world.session,"apple").ok,"remote purchase denied")
	check(await world.session.enter_place("harbor_supermarket",false,"harbor_supermarket"),"return visit admits player")
	check(world.session.room_npcs.size()==2 and world.session.room.customers.size()==4,"return visit has one population")
	await world.session.leave_place()
	FileAccess.open(folder.path_join("integration.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Main, real walk-in/out, checkout and inventory; setup teleports near entrance; isolated no-save session; no performance certification"},"\t"))
	world.queue_free()
	await frames(12)
	quit(0 if failures.is_empty() else 1)
