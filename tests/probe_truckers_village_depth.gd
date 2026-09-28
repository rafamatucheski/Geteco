extends SceneTree
var world
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func safe_place(player_point: Vector3,npc_point: Vector3,npc: CharacterBody3D) -> void:
	# Godot publishes moved body transforms at the next physics boundary.
	# Vacate each old position before letting the other actor occupy it.
	npc.global_position=Vector3(-350,.1,108)
	npc.velocity=Vector3.ZERO
	for i in 2: await physics_frame
	world.player.teleport(player_point)
	for i in 2: await physics_frame
	npc.global_position=npc_point
	npc.velocity=Vector3.ZERO
	npc.model.teleported()
	for i in 2: await physics_frame

func assert_ground(actor: CharacterBody3D,label: String) -> void:
	if absf(actor.global_position.y)>.15:
		failures.append(label+" left ground "+str(actor.global_position))
		push_error(failures[-1])
func report(label: String,npc: CharacterBody3D) -> void:
	for actor in [world.player,npc]:
		var contacts: Array = []
		for i in actor.get_slide_collision_count():
			var contact: KinematicCollision3D = actor.get_slide_collision(i)
			contacts.append({"body":str(contact.get_collider().get_path()) if contact.get_collider()!=null else "none","normal":str(contact.get_normal()),"velocity":str(contact.get_collider_velocity())})
		print("DEPTH_PROBE ",label," actor=",actor.name," at=",actor.global_position," velocity=",actor.velocity," platform=",actor.get_platform_velocity()," contacts=",contacts)
func run() -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	for i in 5000:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(2); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.player.teleport(Vector3(-353,.1,102.2))
	world.production.region.set_focus(world.player.position)
	for i in 20: await physics_frame
	var npc=world.session.urban_operations.village.tonico
	var safe := "--safe-placement" in OS.get_cmdline_user_args()
	for entry in [{"id":"front","z":98.0,"x":-364.0},{"id":"behind","z":94.0,"x":-364.0},{"id":"side","z":96.0,"x":-362.0}]:
		for x in [entry.x,entry.x+1.6]:
			var capsule:=CapsuleShape3D.new()
			capsule.radius=.32
			capsule.height=1.8
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=capsule
			query.transform.origin=Vector3(x,1,entry.z)
			query.collision_mask=7
			var hits:Array=world.get_world_3d().direct_space_state.intersect_shape(query)
			var names:=[]
			for hit in hits: names.append(str(hit.collider.get_path()))
			print("DEPTH_FREE ",entry.id," at=",query.transform.origin," overlaps=",names)
		world.production.region.prepare_collision_at(Vector3(entry.x,0,entry.z))
		if safe: await safe_place(Vector3(entry.x,.1,entry.z),Vector3(entry.x+1.6,.1,entry.z),npc)
		else:
			world.player.teleport(Vector3(entry.x,.1,entry.z))
			npc.global_position=Vector3(entry.x+1.6,.1,entry.z)
			npc.velocity=Vector3.ZERO
			npc.model.teleported()
		report(entry.id+"_teleport",npc)
		for i in 15:
			await physics_frame
			if i in [0,1,2,4,14]: report(entry.id+"_tick"+str(i),npc)
		if safe:
			assert_ground(world.player,entry.id)
			assert_ground(npc,entry.id)
			await safe_place(Vector3(entry.x+1.6,.1,entry.z),Vector3(entry.x,.1,entry.z),npc)
		else:
			world.player.teleport(Vector3(entry.x+1.6,.1,entry.z))
			npc.global_position=Vector3(entry.x,.1,entry.z)
			npc.velocity=Vector3.ZERO
			npc.model.teleported()
		for i in 15:
			await physics_frame
			if i in [0,1,2,4,14]: report(entry.id+"_swap"+str(i),npc)
		if safe:
			assert_ground(world.player,entry.id+"swap")
			assert_ground(npc,entry.id+"swap")
	if safe:
		await safe_place(Vector3(-362,.1,98),Vector3(-350,.1,108),npc)
		for point in [Vector3(-362,0,94),Vector3(-364,0,94)]:
			for i in 240:
				var offset:Vector3=point-world.player.global_position
				offset.y=0
				if offset.length()<.12: break
				world.player.automatic_direction=offset.normalized()
				await physics_frame
				assert_ground(world.player,"player walk")
			world.player.automatic_direction=Vector3.ZERO
			if Vector2(world.player.position.x-point.x,world.player.position.z-point.z).length()>.2: failures.append("Player did not reach walk point")
			report("PLAYER_ACTUAL_WALK",npc)
		await safe_place(Vector3(-350,.1,113),Vector3(-362.4,.1,98),npc)
		npc.stationary=false
		for point in [Vector3(-362.4,0,94),Vector3(-364,0,94)]:
			npc.patrol_points=PackedVector3Array([point])
			npc.point_index=0
			npc._pause=0
			for i in 360:
				await physics_frame
				assert_ground(npc,"npc walk")
				if Vector2(npc.global_position.x-point.x,npc.global_position.z-point.z).length()<.25: break
			if Vector2(npc.global_position.x-point.x,npc.global_position.z-point.z).length()>.3: failures.append("NPC did not reach walk point")
			report("NPC_ACTUAL_WALK",npc)
	print("DEPTH_PROBE_FINAL safe=",safe," failures=",failures)
	quit(0 if failures.is_empty() else 1)
