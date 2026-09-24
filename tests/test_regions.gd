extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool,label: String) -> void:
	if not value: failures.append(label)
func run() -> void:
	var catalog = load("res://world/places/PlaceCatalog.gd")
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .88
	probe.add_child(collision)
	root.add_child(probe)
	for definition in catalog.definitions():
		var room = catalog.create_place(definition.id)
		root.add_child(room)
		await physics_frame
		await physics_frame
		verify(room.model != null,definition.id+": model")
		verify(room.solid_bodies.size()>4,definition.id+": physics")
		for point in [room.spawn_position,room.exit_position]:
			probe.global_position = point+Vector3(0,.08,0)
			verify(probe.move_and_collide(Vector3(0,.001,0),true)==null,definition.id+": blocked approach "+str(point))
		verify(room.find_children("*","SubViewport",true,false).is_empty(),definition.id+": hybrid render")
		for npc in definition.get("npcs",[]):
			probe.global_position = room.to_global(npc.local_position)+Vector3.UP*.08
			verify(probe.move_and_collide(Vector3.UP*.001,true)==null,definition.id+": NPC blocked "+npc.id)
			verify(room.interaction_points.has(npc.id),"NPC interaction "+npc.id)
			var resident = preload("res://world/places/OriginalResidents.gd").create_model(npc)
			room.add_child(resident)
			verify(not resident.find_children("*","MeshInstance3D",true,false).is_empty(),"NPC original mesh "+npc.id)
			resident.free()
		if definition.id == "port_boss_garage":
			var hull := CharacterBody3D.new()
			hull.collision_mask = 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.46,1.5,5.21)
			shape.shape = box
			shape.position.y = .8
			hull.add_child(shape)
			root.add_child(hull)
			for point in [definition.vehicle_spawn,definition.vehicle_exit,Vector3(-8,.04,-4),Vector3(-4,.04,-4),Vector3(0,.04,-4),Vector3(4,.04,-4),Vector3(8,.04,-4)]:
				hull.global_position = room.to_global(point)
				verify(hull.move_and_collide(Vector3.UP*.001,true)==null,"garage full hull "+str(point))
			hull.free()
		if definition.id == "mountain_cabin":
			verify(room.reward_points.size()==3,"cabin original three weapons")
			var ids: Array = []
			for reward in room.reward_points:
				ids.append(reward.id)
				verify(reward.reward.id == reward.id,"individual reward contract")
				probe.global_position = reward.position+Vector3.UP*.08
				verify(probe.move_and_collide(Vector3.UP*.001,true)==null,"cabin reward approach "+reward.id)
			room.set_reward_available(false,"mountain_cabin_axe")
			for reward in room.reward_points: verify(reward.visual.visible == (reward.id!="mountain_cabin_axe"),"independent collection")
		var source_points := {"harbor_bank":[Vector3(0,0,-2.5),Vector3(-5,0,.5),Vector3(5,0,.5)],"harbor_fuel":[Vector3(4.6,0,-3.8)],"harbor_police":[Vector3(1.4,0,3.8)],"harbor_hospital":[Vector3(2,0,-1),Vector3(2,0,-3.5)],"harbor_fire_station":[Vector3(10,0,-120.0/28)]}
		for point in source_points.get(definition.id,[]):
			probe.global_position = room.to_global(point)+Vector3.UP*.08
			verify(probe.move_and_collide(Vector3.UP*.001,true)==null,definition.id+": original service blocked "+str(point))
		if definition.id == "harbor_bank":
			room.set_vault_open(1)
			await physics_frame
			for point in [Vector3(-3,0,-4.2),Vector3(0,0,-4.2),Vector3(3,0,-4.2)]:
				probe.global_position = room.to_global(point)+Vector3.UP*.08
				verify(probe.move_and_collide(Vector3.UP*.001,true)==null,"bank vault loot approach "+str(point))
			verify(room.vault_bodies.size()>0,"bank physical door identified")
			room.set_vault_open(0)
		room.set_active(false)
		verify(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED,definition.id+": inactive")
		print("PLACE_CHECK ",definition.id," solids=",room.solid_bodies.size())
		room.free()
		await physics_frame
	for model_path in ["res://world/places/ServiceResidentModel.gd","res://world/places/NecoModel.gd","res://assets/regions/source/world/harbor/events/BankClerkModel.gd"]:
		var resident = load(model_path).new()
		root.add_child(resident)
		verify(not resident.find_children("*","MeshInstance3D",true,false).is_empty(),model_path+": original geometry")
		resident.free()
	var region_script = load("res://world/regions/NativeRegion.gd")
	for id in ["harbor","mountain"]:
		var region = region_script.build_region(id)
		root.add_child(region)
		await process_frame
		verify(region.chunks.size()<=9,id+": bounded loading")
		verify(region.roads.size()>0,id+": roads")
		region.set_focus(region.spawn_position+Vector3(512,0,512))
		await process_frame
		verify(region.chunks.size()<=9,id+": unload old chunks")
		if id == "harbor":
			for point in [Vector3(3515.0/16,0,1450.0/16),Vector3(3250.0/16,0,1762.0/16),Vector3(-750.0/16-6,0,550.0/16+8.7),catalog.get_definition("harbor_hospital").entry_position]:
				region.set_focus(point)
				for frame in 12: await physics_frame
				probe.global_position = point+Vector3(0,.08,0)
				verify(probe.move_and_collide(Vector3(0,.001,0),true)==null,"world approach blocked: "+str(point))
				var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP,1)
				var hit := root.world_3d.direct_space_state.intersect_ray(ray)
				verify(not hit.is_empty(),"missing floor: "+str(point))
		else:
			region.set_focus(catalog._at(Vector2(7750,-220),"mountain"))
			for frame in 12: await process_frame
			region.set_focus(catalog.get_definition("mountain_bunker").entry_position)
			for frame in 12: await physics_frame
			probe.global_position = catalog.get_definition("mountain_bunker").entry_position+Vector3.UP*.08
			verify(probe.move_and_collide(Vector3.UP*.001,true)==null,"bunker original entrance blocked")
		region.free()
	for variant in ["secret","alpine"]:
		var lake = load("res://world/regions/NativeLake.gd").new()
		lake.variant = variant
		root.add_child(lake)
		verify(lake.water_polygon.size()>5,"lake original polygon")
		if variant == "secret":
			verify(not lake.contains_water(Vector3(0,0,0)),"plane deck dry")
			verify(lake.contains_water(Vector3(-5,0,0)),"glacial water domain")
		lake.free()
	var plane = load("res://world/places/CargoPlaneNative.gd").new()
	root.add_child(plane)
	await physics_frame
	await physics_frame
	verify(plane.reward_points.size()==2,"plane original cash/SMG")
	var previous_y := 0.0
	for index in 85:
		var z := 9.5-index*.25
		var point := Vector3(-.25 if z > -8 and z < -6.6 else 0,0,z)
		var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
		verify(not hit.is_empty(),"plane missing walkway "+str(z))
		if hit.is_empty(): continue
		probe.global_position = hit.position+Vector3.UP*.035
		verify(probe.move_and_collide(Vector3.UP*.001,true)==null,"plane blocked walkway "+str(z))
		verify(absf(hit.position.y-previous_y)<.24,"plane excessive step "+str(z))
		previous_y = hit.position.y
	for reward in plane.reward_points:
		probe.global_position = reward.position+Vector3.UP*.04
		verify(probe.move_and_collide(Vector3.UP*.001,true)==null,"plane reward blocked "+reward.id)
	plane.free()
	for failure in failures: push_error(failure)
	print("REGIONS ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	probe.free()
	quit(0 if failures.is_empty() else 1)
