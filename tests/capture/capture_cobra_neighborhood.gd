extends SceneTree
## Main real, sem saves pessoais. Capturas e amostras têm fases separadas.
var world
var tag := "before"
var folder: String
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	folder = "D:/geteco/artifacts/cobra-neighborhood-1002/" + tag
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(180).timeout.connect(func(): quit(3))
	seed(77001700)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for tick in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var points := {"entrance":Vector3(450,0,98),"garden":Vector3(481,0,104),"workshop":Vector3(510,0,110),"south":Vector3(484,0,136)}
	for label in points:
		world.player.teleport(points[label]+Vector3.UP*.1)
		await create_timer(3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(label+".png"))
		print("SITE ",label," player=",world.player.global_position," cobras=",get_nodes_in_group("iron_cobras").size())
	if "--night" in OS.get_cmdline_user_args():
		world.session.weather.time_of_day=.91
		world.session.weather._update()
		world.player.teleport(points.garden+Vector3.UP*.1)
		await create_timer(2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("garden_night.png"))
		world.session.weather.time_of_day=.45
		world.session.weather._update()
	world.player.teleport(points.entrance+Vector3.UP*.1)
	await create_timer(3).timeout
	if "--validate" in OS.get_cmdline_user_args():
		await validate_bench()
		await validate_life()
	if "--motion" in OS.get_cmdline_user_args(): await capture_motion()
	if "--measure" not in OS.get_cmdline_user_args(): quit(0 if failures.is_empty() else 1); return
	var samples: Array[float] = []
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec()-begin < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last = now
	var sorted := samples.duplicate()
	sorted.sort()
	var report := {"tag":tag,"samples_ms":samples,"fps":samples.size()*1000000.0/(last-begin),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(v): return v>33.3).size(),"over66":samples.filter(func(v): return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"cobras":get_nodes_in_group("iron_cobras").size()}
	report.merge({"duration_s":float(last-begin)/1000000.0,"frames":samples.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"engine":Engine.get_version_info().string,"population":world.people.size()})
	FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("COBRA_REPORT ",JSON.stringify(report))
	quit()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)

func validate_bench() -> void:
	var seat: MeshInstance3D
	for mesh in world.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("cobra_surface_label","")=="CobraBenchSeat" and mesh.is_visible_in_tree(): seat=mesh; break
	check(seat!=null,"Real garden bench is present")
	if seat==null: return
	var forward:=seat.global_basis.z.normalized()
	var approach:=seat.global_position+forward*1.6
	approach.y=.1
	world.player.teleport(approach)
	world.player.controlled_automatically=true
	world.player.automatic_direction=-forward
	await create_timer(1.4).timeout
	world.player.automatic_direction=Vector3.ZERO
	world.player.controlled_automatically=false
	check(seat.to_local(world.player.global_position).z>.45 and absf(world.player.global_position.y)<.2,"Player cannot walk through or on top of bench")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("bench_collision.png"))
	world.player.teleport(approach+forward*3)
	var npc:=preload("res://scripts/Actor.gd").new()
	npc.controlled_automatically=true
	npc.position=approach
	world.add_child(npc)
	npc.automatic_direction=-forward
	await create_timer(1.4).timeout
	check(seat.to_local(npc.global_position).z>.45 and absf(npc.global_position.y)<.2,"Real NPC body cannot walk through or on top of bench")
	npc.queue_free()

func validate_life() -> void:
	var life = world.find_child("CobraNeighborhoodLife",true,false)
	check(life!=null,"Local population is wired into the real session")
	if life==null: return
	check(life.guards.size()==3 and life.residents.size()==2,"Three authored guards and two neighbours spawn")
	if life.guards.size()!=3 or life.residents.size()!=2: return
	var ids := []
	for actor in life.guards.values()+life.residents.values():
		ids.append(actor.get_instance_id())
		check(actor.visible and actor.global_position.y>-.1 and actor.global_position.y<.3,"Local stands on ground: "+str(actor.get_meta("character_name","")))
		var shape := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .27
		capsule.height = 1.5
		shape.shape = capsule
		shape.transform.origin = actor.global_position+Vector3.UP*.95
		shape.collision_mask = 1
		check(world.get_world_3d().direct_space_state.intersect_shape(shape,1).is_empty(),"Local is not embedded in a solid")
	check(life.guards.values().all(func(a): return not a.engaged),"Normal visit does not trigger gunfire")
	var start: Vector3 = life.residents[0].global_position
	await create_timer(2).timeout
	check(start.distance_to(life.residents[0].global_position)>.8,"Neighbour walks its local route")
	world.player.teleport(Vector3(320,.1,149))
	await create_timer(2).timeout
	check(life.guards.values().all(func(a): return not a.visible and not a.is_physics_processing()),"Leaving suspends guards and physics")
	world.player.teleport(Vector3(450,.1,98))
	await create_timer(3).timeout
	var returned := []
	for actor in life.guards.values()+life.residents.values(): returned.append(actor.get_instance_id())
	check(ids==returned,"Return preserves identities without duplicating locals")
	life.guards[0].receive_damage(1,world.player)
	check(life.guards.values().all(func(a): return a.engaged),"Actual player aggression provokes the local guards")
	life.guards[0].receive_damage(999,world.player)
	check(world.session.state.world_state.get("cobra_local_dead_0",false),"Guard death is recorded for save/streaming")
	for guard in life.guards.values(): guard.set_engaged(false)
	var state := preload("res://runtime/GameState.gd").new()
	check(state.restore_snapshot(world.session.state.snapshot()) and state.world_state.get("cobra_local_dead_0",false),"Local death survives full game-state roundtrip")
	life.queue_free()
	await process_frame
	var restored := preload("res://gameplay/urban_v1/CobraNeighborhoodLife.gd").new()
	restored.configure(world.session)
	world.add_child(restored)
	await create_timer(1).timeout
	check(restored.guards.size()==2 and not restored.guards.has(0),"Rebuilding local population does not resurrect defeated guard")
	var campaign = world.session.state.campaign
	var original: Dictionary=campaign.snapshot()
	var fixture: Dictionary=preload("res://systems/campaign/CampaignRuntime.gd").new().snapshot()
	var missions=preload("res://data/campaign/HarborMissions.gd")
	fixture.completed=["primeiro_giro"]
	fixture.claimed_rewards=["primeiro_giro"]
	for flag in missions.MISSIONS.primeiro_giro.sets_flags: fixture.flags[flag]=true
	fixture.active_id="cobra_contact"
	check(campaign.restore_snapshot(fixture),"Valid campaign fixture restores a Cobra mission")
	restored.provoke(world.player)
	check(restored.guards.values().all(func(a): return not a.engaged),"Ambient guards preserve mission access")
	fixture.active_id=""
	fixture.completed=missions.ORDER.duplicate()
	fixture.claimed_rewards=missions.ORDER.duplicate()
	for id in missions.ORDER:
		for flag in missions.MISSIONS[id].sets_flags: fixture.flags[flag]=true
	check(campaign.restore_snapshot(fixture),"Valid campaign fixture restores the completed story")
	await create_timer(.5).timeout
	check(restored.guards.values().all(func(a): return not a.visible and not a.is_physics_processing()),"Defeated gang does not reoccupy the neighbourhood")
	check(restored.residents.values().all(func(a): return a.visible),"Civilian neighbours remain after gang defeat")
	check(campaign.restore_snapshot(original),"Restore original test campaign")
	print("COBRA_LIFE failures=",failures.size())

func capture_motion() -> void:
	# A fixture de história concluída pode abrir o telefonema real do desfecho.
	while world.session.dialogue_open: world.session._advance_dialogue()
	world.player.teleport(Vector3(476,.1,102))
	await create_timer(2).timeout
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.RIGHT
	var positions := []
	var start := Time.get_ticks_msec()
	for frame in 90:
		await create_timer(1.0/30.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(folder.path_join("motion_%03d.jpg"%frame),.88)
		positions.append({"ms":Time.get_ticks_msec()-start,"position":str(world.player.global_position)})
	world.player.automatic_direction=Vector3.ZERO
	world.player.controlled_automatically=false
	check(world.player.global_position.x>481 and absf(world.player.global_position.y)<.15,"Player crosses garden and paving on the ground")
	FileAccess.open(folder.path_join("motion.json"),FileAccess.WRITE).store_string(JSON.stringify(positions))
