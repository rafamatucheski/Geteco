extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("BANK_VIDEO ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	create_timer(180,true,false,true).timeout.connect(func(): quit(2))
	seed(13092026)
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var saves=root.get_node("SaveManager")
	saves._save_dir=OS.get_temp_dir().path_join("bank_video_%d" % OS.get_process_id())+"/"
	saves.clear_pending_save()
	var state=root.get_node("CampaignState")
	state.reset_campaign()
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met"]: state.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene==null or not current_scene.gameplay_ready: await process_frame
	for action in InputMap.get_actions(): InputMap.action_erase_events(action); Input.action_release(action)
	var world=current_scene
	var player=world.get_node("Player")
	var manager=world.get_node("Interiors")
	var room=manager.get_node("InteriorSpaces/BankInterior")
	player.active_weapon_id="fists"
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	await create_timer(3).timeout
	var loot_measure := OS.get_cmdline_user_args().has("loot-baseline") or OS.get_cmdline_user_args().has("loot-after")
	if loot_measure:
		player._respawn_grace_active=true
		for guard in room.guards:
			guard.police_loot.armor_drop_chance=1.0
			guard.take_damage(1000,true)
		await create_timer(3).timeout
	if loot_measure or OS.get_cmdline_user_args().has("baseline") or OS.get_cmdline_user_args().has("after"):
		var samples:Array[float]=[]
		var start=Time.get_ticks_usec()
		var previous=start
		while Time.get_ticks_usec()-start<30000000:
			await process_frame
			var now=Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous=now
		var label="baseline" if OS.get_cmdline_user_args().has("baseline") else "after"
		if loot_measure: label="loot-baseline" if OS.get_cmdline_user_args().has("loot-baseline") else "loot-after"
		FileAccess.open("D:/geteco/artifacts/bank-video-0913/"+label+"-frames.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
		samples.sort()
		print("BANK_PERF ",JSON.stringify({"label":label,"fps":samples.size()/((previous-start)/1000000.0),"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"gpu":RenderingServer.get_video_adapter_name(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}))
		quit(); return
	player._respawn_grace_active=true
	player.weapon_fired.emit()
	check(not room.status.visible,"no top narration")
	var civilians=room.civilians.duplicate()
	var evacuated := {}
	for i in 600:
		await physics_frame
		for n in civilians:
			if is_instance_valid(n) and n.outside_bank: evacuated[n.resident_name]=true
		if evacuated.size()==2: break
	check(evacuated.size()==2,"both clerks physically evacuate")
	for n in civilians:
		if is_instance_valid(n): print("EVAC_DIAG ",n.resident_name," active=",n.can_process()," mode=",n.process_mode," floor=",room.actor_scale.floor_position(n.global_position)," route=",n.route_index," outside=",n.outside_bank," frightened=",n.frightened," dead=",n.is_dead," velocity=",n.velocity)
	if OS.get_cmdline_user_args().has("evac"):
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/evac.png")
		quit(); return
	var guard=room.guards[0]
	guard.weapon_reload.equip(String(guard.dropped_weapon))
	var ammunition:int=guard.weapon_reload.clip
	guard._shoot_at_target(player.global_position)
	check(guard.weapon_reload.clip==ammunition-1,"shotgun consumes one cartridge per blast")
	var helper=guard.get_meta("interior_actor_presentation")
	var chest:Vector2=helper.project_world(helper.floor_position(guard.global_position)+Vector3.UP*1.1)
	var round=load("res://Bullet.tscn").instantiate()
	round.owner_body=player
	round.damage=5
	round.global_position=chest+Vector2(16,0)
	round.direction=Vector2.LEFT
	world.add_child(round)
	round.set_physics_process(false)
	await process_frame
	check(is_equal_approx(round.get_node("Core").scale.x,.03125),"interior projectile graphic is quarter size")
	round.set_physics_process(true)
	var old_health:int=guard.health
	await physics_frame
	await physics_frame
	await physics_frame
	check(guard.health<old_health,"projectile damages upper body above foot collider")
	check(guard.mat_uniform.albedo_color.r<.5,"damage does not flash only trousers red")
	for officer in room.guards: officer.take_damage(1000,true)
	await create_timer(1.4).timeout
	check(room.keycard_visual is Node3D,"security card is a depth-tested 3D object")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/keycard.png")
	player.global_position=room.keycard_position
	room._tick_vault(1.3,true)
	check(room.keycard_taken,"E collects card")
	player.global_position=room.to_global(room.vault_position)
	room._tick_vault(.7,true)
	check(room.lockpick.active,"card enables lockpick at door")
	room.lockpick.finish(true)
	await create_timer(3.2).timeout
	check(room.vault_open and room.vault_body.collision_layer==0,"unlock opens physical vault passage")
	await create_timer(32).timeout
	check(room.guards.all(func(n): return is_instance_valid(n) and n.visible and n.has_meta("interior_actor_presentation")),"corpses persist during robbery")
	check(is_instance_valid(room.blockade) and room.blockade.is_ready(),"police cars arrive before escape")
	for unit in room.blockade.units: print("UNIT_DIAG pos=",unit.global_position," target=",unit.target.global_position," acting=",unit.is_acting," speed=",unit.velocity)
	var posted:=0
	for officer in get_nodes_in_group("police_officer"):
		if is_instance_valid(officer.service_vehicle) and officer.service_vehicle in room.blockade.units:
			print("POST_DIAG ",officer.global_position," target=",officer.target," slot=",officer.target in room.blockade.slots)
			if officer.target in room.blockade.slots: posted+=1
	check(posted>=2,"officers hold blockade instead of chasing interior coordinates")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/after.png")
		var street:=Camera2D.new()
		world.add_child(street)
		street.global_position=room.entrance.global_position+Vector2(0,100)
		street.zoom=Vector2(2,2)
		street.make_current()
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/blockade.png")
		player.get_node("Camera").make_current()
		street.queue_free()
	player._respawn_grace_active=false
	player.take_damage(10000)
	await create_timer(.6).timeout
	check(player.has_meta("interior_actor_presentation"),"death keeps player in room depth until respawn")
	print("BANK_VIDEO failures=",failures)
	quit(0 if failures==0 else 1)
