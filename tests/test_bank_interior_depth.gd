extends SceneTree
var checks := 0
var failures := 0
var room: Node2D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	print("BANK_DEPTH ","PASS " if ok else "FAIL ",label)
func frames(n := 4) -> void:
	for i in n: await process_frame
func run() -> void:
	create_timer(180, true, false, true).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var saves = root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("bank_depth_%d" % OS.get_process_id()) + "/"
	saves.clear_pending_save()
	var campaign = root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]: campaign.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var world = current_scene
	while not world.gameplay_ready: await process_frame
	var manager = world.get_node("Interiors")
	room = manager.get_node("InteriorSpaces/BankInterior")
	var player = world.get_node("Player")
	# Other open editor/game windows and physical input must not inject combat
	# or movement into this automated session. Scripted public actions remain.
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	player.active_weapon_id = "fists"
	player.weapon_aim_active = false
	var originals := {}
	for npc in room.guards+room.civilians:
		originals[npc] = npc.global_position
		# Freeze only AI for repeatable geometric probes; physical bodies and
		# animated production rigs stay real and share the room rendering.
		npc.set_physics_process(false)
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	await create_timer(.7).timeout
	check(room.actor_inside() and player.has_meta("interior_actor_presentation"), "real entry binds player depth")
	check(not room.alarm_started,"peaceful visit does not start robbery")
	for npc in originals:
		check(npc.global_position.distance_to(originals[npc])<.1,"NPC authored spawn clear without relocation: "+str(npc.name))
		check(npc.has_meta("interior_actor_presentation"),"NPC shares room depth: "+str(npc.name))
	var solids = room.get_node("BankVisualSolids").get_children()
	check(solids.size()>=20,"walls, counters, benches, ATMs, planters and posts have projected coverage")
	for mesh in room.bank_model.find_children("*","MeshInstance3D",true,false):
		check(mesh.has_meta("interior_surface"), "classified visual: "+str(mesh.name))
	player.set_physics_process(false)
	room.set_process(false)
	# Sweeps stage actors around every object, including the exit threshold.
	# Do not interpret those fixture relocations as a player's door crossing.
	room.get_node("BankPassage").set_physics_process(false)
	for actor in [player,room.civilians[0]]:
		var helper: Node = actor.get_meta("interior_actor_presentation")
		for shape in solids:
			var rect: Rect2 = shape.get_meta("model_floor_rect")
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				var start: Vector2 = rect.get_center()+direction*(rect.size*.5+Vector2.ONE)
				actor.global_position = room.to_global(room.project_floor(start))
				helper._update_scale()
				await physics_frame
				var target: Vector2 = room.to_global(room.project_floor(rect.get_center()))
				var hit: KinematicCollision2D = actor.move_and_collide(target-actor.global_position)
				check(hit!=null and actor.global_position.distance_to(target)>1,"swept body blocks "+str(shape.name)+" / "+str(actor.name)+" / "+str(direction))
		actor.global_position = room.spawn_point.global_position if actor == player else originals[actor]
		helper._update_scale()
		if DisplayServer.get_name() != "headless": await occlusion(actor,helper)
		actor.global_position = room.spawn_point.global_position if actor == player else originals[actor]
		helper._update_scale()
		actor.velocity = Vector2.ZERO
		actor.reset_physics_interpolation()
	# Walk with production input down the open aisle and through the real exit.
	player.global_position=room.to_global(room.project_floor(Vector2(0,0)))
	player.get_meta("interior_actor_presentation")._update_scale()
	player.reset_physics_interpolation()
	# The rendered occlusion probe moved a frozen civilian into this aisle.
	# Flush its restored body transform before turning the player back on,
	# otherwise CharacterBody treats the fixture relocation as platform motion.
	for i in 3: await physics_frame
	player.set_physics_process(true)
	room.set_process(true)
	room.get_node("BankPassage").has_previous = false
	room.get_node("BankPassage").pending_door = null
	room.get_node("BankPassage").set_physics_process(true)
	# Drive the public touch input vector so an editor/test window taking
	# keyboard focus cannot release the held key halfway through this walk.
	root.get_node("GameInput").touch_move = Vector2.DOWN
	# The production walk speed is 24 px/s. Budget the actual aisle distance,
	# rather than the shorter spawn-to-door route exercised by onboarding.
	var walking_frames := ceili(player.global_position.distance_to(room.exit_door.global_position) / player.speed * Engine.physics_ticks_per_second) + 120
	for i in walking_frames:
		root.get_node("GameInput").touch_move = Vector2.DOWN
		await physics_frame
		if not room.actor_inside(): break
	root.get_node("GameInput").touch_move = Vector2.ZERO
	await frames(30)
	check(not room.actor_inside() and not player.has_meta("interior_actor_presentation"),"physical aisle and exit restore player")
	check(room._bank_presentations.is_empty(),"empty room releases NPC depth adapters")
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	await create_timer(.7).timeout
	check(player.has_meta("interior_actor_presentation"),"reentry binds again")
	player.global_position=room.to_global(room.project_floor(Vector2(-4.5,-1)))
	room.actor_scale.restore()
	room.actor_scale.queue_free()
	room.actor_scale=null
	room._sync_actor_scale()
	check(player.global_position.distance_to(room.spawn_point.global_position)<.1,"old invalid spawn inside counter recovers to clear spawn")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/chapter-one-0913")
		root.get_texture().get_image().save_png("D:/geteco/artifacts/chapter-one-0913/bank-shared-depth.png")
	world.queue_free()
	await frames()
	print("BANK_INTERIOR_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func occlusion(actor: Node2D, helper: Node) -> void:
	actor.global_position=room.to_global(room.project_floor(Vector2(0,0)))
	helper._update_scale()
	helper.set_process(false)
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(4,4,.2)
	panel.mesh=mesh
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("427766")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override=material
	room.view.add_child(panel)
	panel.position=helper.anchor.position+Vector3(0,1,0)+(room.room_camera.position-helper.anchor.position).normalized()*1.5
	panel.look_at(room.room_camera.global_position)
	var pixel: Vector2=room.room_camera.unproject_position(helper.anchor.position+Vector3.UP*.9)
	for blocked in [true,false]:
		panel.visible=blocked
		helper.anchor.show()
		await frames(2)
		await RenderingServer.frame_post_draw
		var shown: Image=room.view.get_texture().get_image()
		helper.anchor.hide()
		await frames(2)
		await RenderingServer.frame_post_draw
		var hidden: Image=room.view.get_texture().get_image()
		var difference := 0
		for y in range(int(pixel.y)-25,int(pixel.y)+25):
			for x in range(int(pixel.x)-20,int(pixel.x)+20):
				if shown.get_pixel(x,y)!=hidden.get_pixel(x,y): difference+=1
		check(difference==0 if blocked else difference>100,"depth with positive control / "+str(actor.name)+" blocked="+str(blocked)+" pixels="+str(difference))
	panel.queue_free()
	helper.anchor.show()
	helper.set_process(true)
