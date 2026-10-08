extends "res://tests/test_vertice_depth.gd"
## Every effective facade footprint, inhabited floor and roof. The rendered
## branch records real actors and positive controls in the gameplay projection.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACE = preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")
const CONTENT = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const OCCUPANTS = preload("res://world/places/harbor_buildings/HarborBuildingOccupants.gd")
const BUILDING_CAMERA = preload("res://world/places/harbor_buildings/HarborBuildingCamera.gd")
var folder := ""
var selected := ""
var selected_archetype := ""
var selected_names := PackedStringArray()
var coverage: Array[Dictionary] = []

func _accessible_depth_pose(room: Node3D, actor: CharacterBody3D) -> Vector3:
	var height: float = room.floor_height(room.floor_index)
	var candidates: Array = room.floor_room.solid_bounds.duplicate()
	# Broad shallow faces cross the camera rays at the physical rear edge.
	# A deep sofa's bounding height belongs to its distant backrest; an actor
	# behind its low seat can correctly remain entirely visible from above.
	candidates.sort_custom(func(a: AABB,b: AABB): return a.size.y/(1.0+a.size.z) > b.size.y/(1.0+b.size.z))
	for bounds: AABB in candidates:
		# A side-on partition cannot meaningfully occlude the actor from the
		# aligned gameplay camera. Keep poses inside a broad projected face.
		if bounds.size.y < .75 or bounds.size.x < .7: continue
		var side_offset := minf(.45,bounds.size.x*.25)
		for offset in [0.0,side_offset,-side_offset]:
			var point := Vector3(bounds.get_center().x+float(offset),height+.04,bounds.position.z-.45)
			if absf(point.x) > room.definition.size.x*.5-.4 or absf(point.z) > room.definition.size.y*.5-.4 or not room.is_floor_clear(point): continue
			# A locked secret chamber is not a valid depth fixture. Reach this
			# pose from the public hall using real swept-body queries first.
			actor.position = Vector3(0,height+.04,1.45)
			if actor.test_move(actor.global_transform,Vector3(0,0,point.z-1.45)): continue
			actor.position.z = point.z
			if actor.test_move(actor.global_transform,Vector3(point.x,0,0)): continue
			return point
	return Vector3.INF

func run() -> void:
	create_timer(600).timeout.connect(func(): push_error("BUILDING_CONTRACT finite timeout"); quit(3))
	var rendered := DisplayServer.get_name() != "headless"
	folder = preload("res://tests/fixtures/NorthGatewayFixtures.gd").output_dir("harbor-building-contract")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--building="): selected = arg.trim_prefix("--building=")
		if arg.begins_with("--archetype="): selected_archetype = arg.trim_prefix("--archetype=")
		if arg.begins_with("--buildings="): selected_names = arg.trim_prefix("--buildings=").split(",")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-25,0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bac3c8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var visited := 0
	var floor_total := 0
	var reward_ids := {}
	for definition in CATALOG.definitions():
		if not selected.is_empty() and selected not in [str(definition.id),str(definition.source_id)]: continue
		if not selected_names.is_empty() and not (str(definition.id) in selected_names or str(definition.source_id) in selected_names): continue
		if not selected_archetype.is_empty() and definition.archetype != selected_archetype: continue
		visited += 1
		coverage.append({"id":definition.id,"archetype":definition.archetype,"size":[definition.size.x,definition.size.y],"floors":definition.floor_count})
		check(definition.size.x >= 4.0 and definition.size.y >= 4.0,definition.id+" usable real facade footprint")
		check(not CONTENT.all_rewards(definition).is_empty(),definition.id+" useful persistent exploration reward")
		for floor_index in int(definition.floor_count)+1:
			floor_total += 1
			var room = PLACE.new()
			room.definition = definition.duplicate(true)
			room.floor_index = floor_index
			stage.add_child(room)
			var floor_room = room.floor_room
			var altitude: float = room.floor_height(floor_index)
			var label: String = definition.id+"-"+str(floor_index)
			camera.size = room.camera_size
			var offset: Vector3 = BUILDING_CAMERA.offset(definition,floor_index)
			camera.position = room.camera_target+offset
			camera.look_at(room.camera_target)
			await physics_frame
			await physics_frame
			check(is_equal_approx(floor_room.position.y,altitude),label+" real storey altitude")
			check(room.reward_points.size() == CONTENT.floor_rewards(definition,floor_index).size(),label+" all authored rewards placed without blocked fallback loss")
			for reward in room.reward_points:
				check(not reward_ids.has(reward.id),label+" unique persistent reward "+str(reward.id))
				reward_ids[reward.id] = true
				var reward_local: Vector3 = floor_room.to_local(reward.position)
				check(floor_room.is_floor_clear(reward_local,.32),label+" reward full footprint clearance")
				check(absf(reward.position.y-altitude) < .2,label+" reward at occupied elevation")
			var stair: Vector3 = room.stair_point()
			var landing: Vector3 = room._landing(floor_index)
			for player in [true,false]:
				var actor = ACTOR.new()
				actor.is_player = player
				actor.controlled_automatically = true
				actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
				stage.add_child(actor)
				actor.set_physics_process(false)
				for frame in 3: await process_frame
				actor.process_mode = Node.PROCESS_MODE_DISABLED
				var who := label+("-Dante" if player else "-NPC")
				var poses: Array[Vector3] = [stair,landing,Vector3(0,altitude,1.45)]
				if floor_index == 0: poses.append_array([definition.spawn,definition.exit])
				for point in poses:
					actor.position = point+Vector3.UP*.04
					check(room.is_floor_clear(point),who+" floor clear "+str(point))
					check(not actor.test_move(actor.global_transform,Vector3.UP*.002),who+" capsule admission "+str(point))
					var hit := stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.1,actor.position-Vector3.UP*.3,1))
					check(not hit.is_empty(),who+" floor support "+str(point))
				actor.position = Vector3(0,altitude+.04,1.45)
				check(not actor.test_move(actor.global_transform,stair+Vector3.UP*.04-actor.position),who+" swept circulation to stairs")
				if floor_index == 0:
					actor.position = definition.spawn+Vector3.UP*.04
					check(not actor.test_move(actor.global_transform,Vector3(-definition.spawn.x,0,0)),who+" door landing to central hall")
					actor.position.x = 0.0
					check(not actor.test_move(actor.global_transform,Vector3(0,0,1.45-definition.spawn.z)),who+" central hall circulation")
				var exercised := 0
				for bounds: AABB in floor_room.solid_bounds:
					var center: Vector3 = bounds.get_center()
					for side in [Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT]:
						var half: float = bounds.size.x*.5 if side.x != 0 else bounds.size.z*.5
						var start: Vector3 = Vector3(center.x,.04,center.z)+side*(half+.65)
						if absf(start.x) > definition.size.x*.5-.4 or absf(start.z) > definition.size.y*.5-.4 or not floor_room.is_floor_clear(start): continue
						actor.position = start+Vector3.UP*altitude
						var sweep: Vector3 = -side*(half+1.3)
						var blocked: bool = actor.test_move(actor.global_transform,sweep)
						if not blocked:
							var ray_from: Vector3 = actor.global_position+Vector3.UP*.8
							var ray_hit := stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from,ray_from+sweep,1))
							print("BUILDING_SWEEP_DIAGNOSTIC ",who," bounds=",bounds," from=",actor.global_position," motion=",sweep," ray=",ray_hit)
						check(blocked,who+" swept body blocked by "+str(bounds))
						exercised += 1
						break
				check(exercised > 0,who+" reachable physical obstacles exercised")
				if rendered:
					actor.position = landing+Vector3.UP*.04
					actor.reset_physics_interpolation()
					check((await capture()).save_png(folder.path_join(who+"-natural.png")) == OK,who+" real photograph saved")
					mask_meshes(actor.visual,diagnostic)
					# An approachable solid supplies real native-depth occlusion;
					# the unobstructed hall proves the actor is not simply hidden.
					var depth_poses := {"front":Vector3(-.65,altitude+.04,1.45)}
					if not room.is_rooftop():
						var behind := _accessible_depth_pose(room,actor)
						check(behind.is_finite(),who+" approachable solid for depth control")
						if behind.is_finite(): depth_poses["behind"] = behind
					for pose in depth_poses:
						var point: Vector3 = depth_poses[pose]
						actor.position = point
						actor.reset_physics_interpolation()
						check(room.is_floor_clear(point),who+" depth pose on accessible floor "+pose)
						var actual := await capture()
						room.hide()
						var control := await capture()
						room.show()
						var count := mask_count(control)
						var ratio := float(mask_count(actual))/maxf(1,count)
						check(count > 80,who+" visible actor positive control "+pose)
						check(ratio < .88 if pose == "behind" else ratio > .90,who+" native depth "+pose+" ratio="+str(ratio))
						actual.save_png(folder.path_join(who+"-"+pose+".png"))
						records.append({"place":definition.id,"floor":floor_index,"actor":"Dante" if player else "NPC","pose":pose,"visible_ratio":ratio,"positive_control_pixels":count})
				actor.free()
			# Resident actors share the same collision world; no separate actor
			# viewport or sprite layer can conceal an invalid occupied position.
			var inhabitants: Node3D = OCCUPANTS.populate(floor_room,definition,floor_index)
			check(inhabitants.residents.size() == CONTENT.floor_spec(definition,floor_index).occupants.size(),label+" all authored resident stations admitted")
			await physics_frame
			for resident in inhabitants.get_children():
				if not resident is CharacterBody3D: continue
				resident.set_physics_process(false)
				check(not resident.test_move(resident.global_transform,Vector3.UP*.002),label+" resident full-body admission "+str(resident.name))
			if rendered:
				var visitor := ACTOR.new()
				visitor.is_player = true
				visitor.controlled_automatically = true
				visitor.position = room.spawn_position+Vector3.UP*.04
				stage.add_child(visitor)
				await physics_frame
				visitor.set_physics_process(false)
				check(not visitor.test_move(visitor.global_transform,Vector3.UP*.002),label+" player and active residents coexist physically")
				check((await capture()).save_png(folder.path_join(label+"-residents-active.png")) == OK,label+" resident activities and human scale photograph")
				visitor.free()
			room.set_active(false)
			check(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED,label+" inactive geometry and inhabitants suspended")
			room.free()
			await physics_frame
	check(visited > 0 and floor_total > 0,"non-empty real-building coverage")
	for definition in CATALOG.definitions():
		check(CATALOG.valid_floors({definition.id:int(definition.floor_count)}),definition.id+" rooftop save accepted")
		check(CATALOG.valid_floors(JSON.parse_string(JSON.stringify({definition.id:1}))),definition.id+" JSON floor number accepted")
		var maximum := maxi(3,int(definition.floor_count)) if definition.id in CATALOG.LEGACY_IDS.values() else int(definition.floor_count)
		check(not CATALOG.valid_floors({definition.id:maximum+1}),definition.id+" out-of-range floor rejected")
	for invalid in [null,[],{"harbor_customs_house":.5},{"unknown":0}]:
		check(not CATALOG.valid_floors(invalid),"malformed floor save rejected "+str(invalid))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"buildings":visited,"floors":floor_total,"rendered":rendered,"coverage":coverage,"records":records},"\t"))
	print("HARBOR_BUILDING_CONTRACT ",folder," buildings=",visited," floors=",floor_total," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
