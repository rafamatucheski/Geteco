extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
func await_boarding(car: Node2D) -> void:
	# Boarding is an animated action; throttle held before seating stays disarmed.
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)
	var deadline := Time.get_ticks_msec() + 5000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not car.has_meta("vehicle_boarding"), "boarding completes before driving")
	for i in 3: await physics_frame
	check(car._drive_input_armed, "released controls arm driving after boarding")

func _run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met",&"harbor_delivery_started",&"harbor_delivery_picked_up"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	var manager: Node = world.get_node("PersonalCarManager")
	var player: Node2D = world.get_node("Player")
	var car: Node2D = manager.car
	var garage: Node2D = manager.garage
	check(player.active_weapon_id == "fists" and player.weapon_inventory.values().count(true) == 1, "new game starts unarmed with no owned weapons")
	check(player.weapon_ammo.pistol == {"clip":0,"reserve":0}, "new game has no starter pistol ammunition")
	player.set_physics_process(false)
	player.global_position = car.global_position+Vector2(50,0)
	car.enter_vehicle(player)
	check(not car.is_driven_by_player and not car.unlocked,"display Monaliza cannot be stolen before first delivery")
	car.take_damage(500,true)
	check(car.health == car.max_health,"reward car cannot be destroyed before unlock")
	world.get_node("ChopShopZone")._on_body_entered(car)
	check(world.get_node("ChopShopZone")._processing_car == null,"personal car is protected from automatic scrapping")
	var id := car.get_instance_id()
	player.global_position = garage.jager_npc.global_position+Vector2(0,30)
	var cash: int = player.money
	check(world.campaign_controller.interact_with_objective(),"actual first mission hand-in succeeds")
	check(manager.delivery_in_progress and not car.unlocked, "keys stay with mechanic during arrival")
	while manager.delivery_in_progress:
		await process_frame
	check(garage.showroom.mechanic_working, "mechanic reaches workbench after handoff")
	check(car.unlocked and car.get_instance_id()==id and player.money==cash+150,"same display car unlocked plus original cash reward")
	var bridge: Node = world.get_node("CobraCampaign")
	check(bridge._messages.size()>=1,"Maciota car dialogue queued after brother clue")
	while bridge._dialog.visible: bridge._next_message()
	player.global_position = car.global_position-car.global_transform.x*47
	manager._process(0.2)
	await key(KEY_T)
	check(manager.panel.visible and car.trunk_open,"trunk opens on foot behind personal vehicle")
	check(player.personal_loadout_enabled and player.world_pickups_collected.has("monaliza_starter_case"),"surprise grants loadout and unique case flag")
	check(player.weapon_inventory.values().count(true) == 2 and player.weapon_inventory.pistol, "first trunk grants only the pistol")
	check(player.weapon_ammo.pistol == {"clip":12,"reserve":60}, "starter pistol is loaded and has reserve ammunition")
	check(manager.pending_loadout == {"curta":"pistol","longa":"","corpo":"","granada":""}, "shotgun, melee and grenade spaces start empty")
	check(manager.live_view.slot_models.longa.get_child_count() == 0 and manager.live_view.slot_models.granada.get_child_count() == 0, "empty shotgun and grenade spaces contain no weapon geometry")
	check(manager.first_trunk_hint._box.visible and manager.first_trunk_hint.layer > manager.panel.get_parent().layer, "first trunk tip appears above the open trunk")
	check(manager.first_trunk_hint._box.anchor_left == 0.5 and manager.first_trunk_hint._box.anchor_top == 0.5, "first trunk tip is centered on screen")
	check(not paused and manager.live_view.live_world.world_2d == world.get_viewport().world_2d, "trunk projects the live simulation without pausing")
	check(not manager.live_view.mirrors.has(player) and manager.live_view.hand != null, "close-up shows handling hands without Dante's body")
	check(manager.live_view.weapons.find_children("*", "Sprite3D", true, false).is_empty(), "arsenal uses mesh geometry, never flat weapon sprites")
	check(not manager.message.visible and manager.rows.get_child_count() == 4, "trunk contains four selectors including the dedicated grenade slot")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-live-review.png")
	if DisplayServer.get_name() == "headless": await create_timer(1.3).timeout
	var view: Control = manager.live_view
	check(is_instance_valid(view.weather), "trunk finds the world's weather controller")
	if is_instance_valid(view.weather):
		var original_time: float = view.weather.time_of_day
		view.weather.time_of_day = 0.5
		view._sync_trunk_light(1.0)
		check(view.trunk_light.light_energy == 0.0, "courtesy light stays off during daylight")
		view.weather.time_of_day = 0.95
		view._sync_trunk_light(1.0)
		check(view.trunk_light.light_energy > 0.0 and view.trunk_light.light_energy < 1.0, "subtle courtesy light turns on at night")
		check(view.model.trunk_pivot.has_node("EmergencyWarningTriangle"), "warning triangle is attached to the opening lid")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-night-triangle.png")
		view.weather.time_of_day = original_time
		view._sync_trunk_light(1.0)
		var ambience: Node = view.weather.weather_audio
		var ambience_id := ambience.get_instance_id()
		for kind in view.weather_emitters:
			var source: CPUParticles2D = view.weather.get(kind)
			var was_emitting := source.emitting
			source.emitting = true
			view._sync_weather()
			check(view.weather_emitters[kind].emitting, "3D weather follows " + kind)
			source.emitting = false
			view._sync_weather()
			check(not view.weather_emitters[kind].visible, "weather clears immediately for " + kind)
			source.emitting = was_emitting
		view._sync_weather()
		check(ambience.get_instance_id() == ambience_id and not paused and ambience.is_processing(), "ambient audio controller keeps running during trunk view")
	var pistol_mesh: MeshInstance3D = view.slot_models.curta.find_children("*", "MeshInstance3D", true, false)[0]
	var hit: Vector2 = view.camera.unproject_position(pistol_mesh.global_transform * pistol_mesh.get_aabb().get_center()) * view.size / Vector2(view.stage.size)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = hit
	view._gui_input(click)
	check(manager.weapon_stats.visible and manager.weapon_stats.text.contains("PISTOLA"), "clicking the 3D weapon displays its catalog stats")
	check(view.selection_audio.playing, "weapon inspection plays selection sound")
	check(player.personal_loadout.longa == "", "inspection does not fill the empty long-gun space")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-inspect-review.png")
	var reserve: int = player.weapon_ammo.pistol.reserve
	await key(KEY_ESCAPE)
	check(not manager.panel.visible and not paused and not player.is_control_disabled,"Escape closes trunk and releases controls without pausing")
	manager.open_panel()
	check(player.weapon_ammo.pistol.reserve==reserve and manager.first_trunk_hint == null,"reopening cannot duplicate ammunition or replay the introduction")
	manager.close_panel()
	player.add_weapon_loot(&"shotgun",16)
	check(player.personal_loadout.longa == "shotgun", "a later weapon pickup fills the empty long-gun slot")
	manager.open_panel()
	await create_timer(1.2).timeout
	player.weapon_inventory.ak47 = true
	check(manager.set_slot("longa","ak47"),"long gun can be changed in personal trunk")
	await create_timer(0.46).timeout
	check(manager.live_view.swapping and manager.live_view.hand.visible, "hand reaches and lifts the selected weapon")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-hand-swap.png")
	await create_timer(1.1).timeout
	check(manager.live_view.displayed.longa == "ak47" and not manager.live_view.swapping, "hand completes the replacement with the selected 3D weapon")
	manager.close_panel()
	check(player.personal_loadout.longa == "shotgun", "cancel discards pending loadout")
	manager.open_panel()
	manager.set_slot("longa", "ak47")
	var selection: OptionButton = manager.rows.get_child(1).get_child(0).get_child(2)
	for index in selection.item_count:
		if selection.get_item_metadata(index)=="shotgun": selection.item_selected.emit(index); break
	check(player.personal_loadout.longa=="shotgun","actual long-gun selector updates the correct slot")
	manager.set_slot("longa","ak47")
	check(player.personal_loadout.longa == "shotgun", "selection remains pending until Save")
	manager.save_loadout()
	player.add_weapon_loot(&"grenade", 3)
	manager.open_panel()
	check(manager.pending_loadout.granada == "grenade" and manager.pending_loadout.longa == "ak47", "grenades occupy their own slot without replacing the long gun")
	check(manager.live_view.slot_models.granada.get_meta("weapon_id") == "grenade", "owned grenade has a 3D model in its dedicated space")
	check(manager._ammo_text("pistol").contains("/12") and manager._ammo_text("grenade").contains(str(int(player.weapon_ammo.grenade.clip) + int(player.weapon_ammo.grenade.reserve))), "ammo labels show magazine capacity and total grenades")
	var migrated: Dictionary = manager.RULES.normalize({"longa": "grenade"}, player.weapon_inventory)
	check(migrated.granada == "grenade" and migrated.longa == "", "legacy grenade loadout migrates into its dedicated slot")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/trunk-centered-grenade.png")
	manager.save_loadout()
	var original_cash: int = player.money
	player.money = 10000
	var quote: Dictionary = player.car_loadout_ammo_quote()
	player.buy_car_loadout_ammo()
	check(player.money == 10000 - int(quote.price), "ammo basket charges exactly the displayed quote")
	var refilled_cash: int = player.money
	player.buy_car_loadout_ammo()
	check(player.money == refilled_cash, "full loadout cannot be charged again")
	player.money = original_cash
	check(not player.can_carry_weapon("shotgun") and player.weapon_inventory.shotgun and player.can_carry_weapon("ak47"),"three-slot loadout preserves stored gun ownership")
	manager.close_panel()
	check(not manager.set_slot("longa","shotgun"),"remote swaps rejected")
	car.health = 111
	car.repaint_vehicle(Color("254dad"))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	check(snapshot.personal_car_state.health==111 and snapshot.personal_loadout.longa=="ak47","parked car damage and loadout included in player JSON save")
	var saved_car_position: Vector2 = car.global_position
	car.global_position += Vector2(400,0)
	car.health = 10
	player.restore(snapshot)
	player.set_physics_process(false)
	check(car.health==111 and car.global_position.distance_to(saved_car_position)<1,"restoring a save while on foot restores parked car state")
	check(car.engine_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and car.spool.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,"exported engine and turbo WAVs loop in actual car")
	car.enter_vehicle(player)
	check(car.is_driven_by_player,"earned car is driveable")
	var travel: Node = root.get_node("RegionTravel")
	var world_data: Dictionary = JSON.parse_string(JSON.stringify(travel.snapshot_world()))
	car.exit_vehicle()
	travel.pending_world=world_data
	travel._restore_saved_vehicle(world,player)
	check(get_nodes_in_group("personal_vehicle").size()==1 and car.is_driven_by_player,"driven save restore reuses one personal car")
	travel.pending_world.clear()
	car.exit_vehicle()
	player.set_physics_process(false)
	player.global_position = manager.bay_position()+Vector2(-60,0)
	car.global_position = Vector2(2100,1300)
	player.money = 300
	check(manager.recover() and player.money==50 and car.health==180,"garage recovery has a cost and restores owned car")
	check(car.global_position.distance_to(manager.bay_position())<1,"recovered car returns to display bay")
	car.enter_vehicle(player)
	await await_boarding(car)
	Input.action_press("ui_up")
	for i in 180:
		await physics_frame
		if car.global_position.distance_to(garage.global_position)>1500: break
	print("MONALIZA_DRIVE_DIAGNOSTIC local=", garage.to_local(car.global_position), " velocity=", car.velocity, " health=", car.health, " recoveries=", car.get_meta("motion_recoveries",0), " rotation=", car.rotation)
	Input.action_release("ui_up")
	for i in 2: await physics_frame
	check(car.release.playing,"turbo release plays after accelerating out of the garage")
	check(car.engine_audio.stream == preload("res://world/harbor/monaliza/MonalizaAudio.gd").stream("engine"),"shared RPM controller retains exclusive Monaliza engine while driving")
	check(car.global_position.distance_to(garage.global_position)>1500,"actual driving input exits showroom gate to Harbor")
	car.exit_vehicle()
	player.set_physics_process(false)
	car.global_position = manager.bay_position()
	car.rotation = PI/2
	car.velocity = Vector2.ZERO
	player.global_position = manager.bay_position()+Vector2(-60,0)
	if DisplayServer.get_name()!="headless":
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.position = garage.global_position+Vector2(130,0)
		camera.zoom = Vector2.ONE*1.5
		camera.make_current()
		garage.set_npc_rendering_active(true)
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/monaliza-garage-review.png")
		player.global_position = car.global_position-car.global_transform.x*47
		manager.open_panel()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/monaliza-loadout-review.png")
		manager.close_panel()
	# Real scene replacement exercises the deferred SaveManager -> Player -> manager order.
	car.global_position = Vector2(850,1300)
	car.health = 97
	car.repaint_vehicle(Color("355bb0"))
	var saved: Dictionary = player.serialize()
	root.get_node("SaveManager")._pending_save_data = {"player": JSON.parse_string(JSON.stringify(saved)),"world":{}}
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 35: await process_frame
	var restored_manager: Node = current_scene.get_node("PersonalCarManager")
	var restored_player: Node = current_scene.get_node("Player")
	check(get_nodes_in_group("personal_vehicle").size()==1 and restored_manager.car.unlocked,"fresh scene save restore creates one earned personal car")
	check(restored_player.personal_loadout.longa=="ak47" and restored_player.world_pickups_collected.has("monaliza_starter_case"),"fresh scene keeps chosen loadout and consumed surprise")
	check(restored_manager.car.global_position.distance_to(Vector2(850,1300))<1 and restored_manager.car.health==97 and restored_manager.car.paint_color.is_equal_approx(Color("355bb0")),"fresh scene restores parked position, damage and custom paint")
	print("MONALIZA REWARD FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)
