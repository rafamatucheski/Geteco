extends SceneTree
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("FLOOR_LOOT ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func frames(n:int) -> void:
	for i in n: await process_frame
func run() -> void:
	create_timer(180,true,false,true).timeout.connect(func(): quit(2))
	seed(13092026)
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var saves=root.get_node("SaveManager")
	saves._save_dir=OS.get_temp_dir().path_join("bank_floor_loot_%d" % OS.get_process_id())+"/"
	saves.clear_pending_save()
	var campaign=root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met"]: campaign.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene==null or not current_scene.gameplay_ready: await process_frame
	for action in InputMap.get_actions(): InputMap.action_erase_events(action); Input.action_release(action)
	var world=current_scene
	var player=world.get_node("Player")
	var manager=world.get_node("Interiors")
	var room=manager.get_node("InteriorSpaces/BankInterior")
	player.active_weapon_id="fists"
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	await create_timer(2).timeout
	player._respawn_grace_active=true
	for guard in room.guards:
		guard.police_loot.armor_drop_chance=1
		guard.take_damage(1000,true)
	room.civilians[0].take_damage(1000,true)
	await create_timer(3).timeout
	var pools=get_nodes_in_group("bank_guard_blood")
	var armors=get_nodes_in_group("bank_guard_armor")
	var weapons=get_nodes_in_group("bank_guard_weapon")
	check(pools.size()==3,"guards and killed clerk create blood on the room floor")
	check(armors.size()==2 and weapons.size()==2,"real death drops both armor and weapon pickups")
	var origin:Vector2=player.global_position
	for item in armors+weapons:
		check(item.visual.get_parent()==room.view,"loot shares room light and depth")
		player.global_position=item.global_position
		room.actor_scale._update_scale()
		check(room.actor_scale._placement_is_clear(room),"player footprint fits at drop position")
	player.global_position=origin
	room.actor_scale._update_scale()
	for pool in pools:
		check(pool.visual.get_parent()==room.view and is_equal_approx(pool.visual.position.y,.024),"blood is on floor under characters")
		check(not pool.is_processing(),"settled blood needs no per-frame processing")
	await create_timer(32).timeout
	check(pools.all(func(p): return is_instance_valid(p) and p.visual.visible),"blood remains beyond former 17 second expiry")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/floor-loot.png")
		var pool=pools[0]
		var pixel:Vector2=room.room_camera.unproject_position(room.guards[0].torso_node.global_position)
		var shown:Image=room.view.get_texture().get_image()
		pool.visual.hide()
		await frames(3)
		await RenderingServer.frame_post_draw
		var hidden:Image=room.view.get_texture().get_image()
		var visible_pixels:=0
		for y in shown.get_height():
			for x in shown.get_width():
				if shown.get_pixel(x,y)!=hidden.get_pixel(x,y): visible_pixels+=1
		var body_pixels:=0
		for y in range(int(pixel.y)-2,int(pixel.y)+3):
			for x in range(int(pixel.x)-2,int(pixel.x)+3):
				if shown.get_pixel(x,y)!=hidden.get_pixel(x,y): body_pixels+=1
		check(visible_pixels>100,"positive control: pool is visible around body")
		check(body_pixels==0,"torso occludes the pool")
		pool.visual.show()
	# Drive the physical armor trigger; no direct reward-method substitution.
	player.armor=0
	player.global_position=armors[0].global_position
	room.actor_scale._update_scale()
	await create_timer(.5).timeout
	check(player.armor>0,"3D armor still grants protection through physical pickup")
	var weapon=weapons[0]
	player.global_position=weapon.global_position
	room.actor_scale._update_scale()
	await frames(3)
	var event:=InputEventAction.new()
	event.action="interact"
	event.pressed=true
	weapon._unhandled_input(event)
	check(weapon._consumed,"E collects production 3D weapon")
	var visuals:Array=[]
	for pool in pools: visuals.append(pool.visual)
	for item in get_nodes_in_group("bank_guard_armor")+get_nodes_in_group("bank_guard_weapon"): visuals.append(item.visual)
	room.reset_after_investigation()
	await frames(4)
	check(visuals.all(func(v): return not is_instance_valid(v)),"reopening clears blood and loot from shared viewport")
	print("FLOOR_LOOT failures=",failures)
	quit(0 if failures==0 else 1)
