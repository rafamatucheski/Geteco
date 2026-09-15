extends SceneTree
## Production regression: native movement with exterior population budgeting active.
var failures := 0
var tested_interiors := 0
func _initialize():
	call_deferred("run")
func check(ok, label):
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func run():
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("geteco_interior_movement_%d/" % Time.get_ticks_usec())
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_maciota_met",true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	await create_timer(1).timeout
	var p = world.get_node("Player")
	var m = world.get_node("Interiors")
	for path in m._door_configs:
		var cfg = m._door_configs[path]
		var door = world.get_node_or_null(path)
		# Northgate is now a drive-in service and intentionally has no interior door.
		if path == "NorthDistrict/MotorWorkshop/Entrance" and door == null:
			continue
		check(door != null, str(path)+" entrance exists")
		if door == null: continue
		tested_interiors += 1
		m._on_exterior_destination_requested(door,p,cfg.id,null,&"",cfg.interior,cfg.spawn)
		await create_timer(0.5).timeout
		check(cfg.interior.contains_point(p.global_position),str(path)+" arrives inside room")
		var before = p.global_position
		Input.action_press("move_left")
		await create_timer(0.3).timeout
		Input.action_release("move_left")
		check(p.global_position.distance_to(before)>10, str(path)+" movement="+str(p.global_position.distance_to(before)))
		check(p.can_process(),str(path)+" player stays active")
		m._on_exit_door_requested(cfg.interior.exit_door,p,&"",null,&"",cfg.id)
		await create_timer(0.5).timeout
		check(not p.has_meta("harbor_interior"),str(path)+" exterior restored")
	var door = world.get_node("District/NorthFrontage2/AmmunationEntrance")
	p.global_position = door.global_position + Vector2(0,160)
	p.velocity = Vector2.ZERO
	await create_timer(0.5).timeout
	Input.action_press("move_up")
	await create_timer(1.25).timeout
	Input.action_release("move_up")
	print("AMMU_APPROACH ",p.global_position-door.global_position," range=",door.is_actor_in_range(p))
	for i in p.get_slide_collision_count(): print("AMMU_COLLIDER ",p.get_slide_collision(i).get_collider().get_path())
	check(door.is_actor_in_range(p),"Ammunation reachable from street")
	if door.is_actor_in_range(p):
		await key(KEY_E)
		await create_timer(1).timeout
		var room = m.ammunation_interior
		check(room.contains_point(p.global_position),"E enters Ammunation")
		check(await walk_to(p,room.to_global(room.merchant_point)),"Walk to gunsmith")
		await key(KEY_E)
		check(room.active and p.is_in_dialogue,"E opens catalog")
		await key(KEY_ESCAPE)
		check(not room.active and not p.is_in_dialogue,"Escape restores controls")
		check(await walk_to(p,room.exit_door.global_position),"Walk back to exit")
		await key(KEY_E)
		await create_timer(1).timeout
		check(p.global_position.distance_to(door.get_node("OutsideReturn").global_position)<10,"E returns to street")
	check(tested_interiors >= 11,"Current playable entrances covered")
	print("INTERIOR_MOVEMENT failures=",failures," interiors=",tested_interiors)
	if failures == 0: await after_checks(world)
	quit(1 if failures else 0)

func key(code):
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await create_timer(0.15).timeout
func walk_to(p,target):
	for i in 240:
		var delta = target-p.global_position
		if delta.length()<8: return true
		for pair in [["move_right",delta.x],["move_left",-delta.x],["move_down",delta.y],["move_up",-delta.y]]:
			if pair[1]>3: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
		for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
	return false

func after_checks(_world):
	pass
