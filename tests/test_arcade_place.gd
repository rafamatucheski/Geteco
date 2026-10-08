extends "res://tests/test_vertice_depth.gd"
## Native room contracts: actual Actor capsules, complete authored solids,
## valid walking paths, and rendered depth with unobstructed positive controls.
const ARCADE := preload("res://world/places/arcade/ArcadePlace.gd")
const RESIDENTS := preload("res://world/places/OriginalResidents.gd")
const EXPECTED_SOLIDS := ["PinballCabinet","BlocksCabinet","RacerCabinet","FighterCabinet",
	"LiaCabinet","IvoCabinet","LoungeBench","LowTable","TokenExchanger",
	"BackWall","SideWall-1","SideWall1","SouthWall-1","SouthWall1","EntryJamb-1","EntryJamb1"]
var folder := ""
var room
var stage: Node3D

func run() -> void:
	var physics_only := "--arcade-physics-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not physics_only:
		push_error("ARCADE_PLACE depth requires rendered Godot; use --arcade-physics-only only for physical diagnosis")
		quit(2); return
	create_timer(100).timeout.connect(func(): push_error("ARCADE_PLACE timeout"); quit(3))
	folder = "res://evidence/arcade-place-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK,"evidence directory available")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	room = ARCADE.new()
	room.definition = ARCADE.definition_data()
	stage.add_child(room)
	for frame in 3: await physics_frame
	_inventory()
	await _physical()
	await _residents()
	if not physics_only: await _depth()
	check(room.get_tree().get_nodes_in_group("arcade_facade").is_empty(),"room fixture does not create a duplicate exterior")
	room.set_active(false)
	check(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED,"inactive room suspends rendering and child effects")
	for light in room.model.find_children("*","Light3D",true,false):
		check(not light.is_visible_in_tree() and not light.can_process(),"inactive ancestor disables local light "+str(light.name))
	room.set_active(true)
	check(room.visible and room.process_mode == Node.PROCESS_MODE_INHERIT,"room supports reactivation")
	for light in room.model.find_children("*","Light3D",true,false):
		check(light.is_visible_in_tree(),"reactivation restores local light "+str(light.name))
	var report := FileAccess.open(folder.path_join("results.json"),FileAccess.WRITE)
	check(report != null,"evidence report writable")
	if report:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,
			"depth":"not executed" if physics_only else "rendered",
			"renderer":RenderingServer.get_current_rendering_method(),
			"scope":"Native room, actual player/visitor sweeps, resident rig, final camera depth. Main session transition/save and rendered performance are separate checks."},"\t"))
	print("ARCADE_PLACE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"folder":folder,"physics_only":physics_only}))
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _inventory() -> void:
	check(room.model.cabinet_bounds.size() == 6,"four playable and two resident cabinets")
	var physical := {}
	for body in room.solid_bodies: physical[str(body.get_meta("interior_solid_id",""))] = body.get_meta("bounds")
	for id in EXPECTED_SOLIDS: check(physical.has(id),"authored physical inventory: "+id)
	for mesh in room.model.find_children("*","MeshInstance3D",true,false):
		var id := str(mesh.get_meta("interior_solid_id",""))
		if id.is_empty(): continue
		var bounds: AABB = (room.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if bounds.position.y > 2.1: continue
		check(physical.has(id) and physical[id].grow(.003).encloses(bounds),"visible full volume covered: "+str(mesh.name))
	var lights: Array[Node] = room.model.find_children("*","Light3D",true,false)
	check(lights.size()==2,"two fixed wall fixtures support the night aisle")
	for light in lights:
		check(light is OmniLight3D and not light.shadow_enabled and light.omni_range<=10.0,"bounded local illumination without shadow passes "+str(light.name))
	check(room.model.find_children("*","SubViewport",true,false).is_empty(),"cabinet art adds no secondary viewport")
	check(room.model.find_children("*","Label3D",true,false).is_empty(),"interior has no decorative explanation labels")
	check(room.definition.reward.id == "fagulha_first_aid" and room.reward_points.size()==1,"place owns one persistent useful pickup")

func _physical() -> void:
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.collision_mask = 1
		for frame in 3: await physics_frame
		var who := "Dante" if is_player else "visitor"
		for key in ["spawn","exit"]:
			var at: Vector3 = room.to_global(room.definition[key])+Vector3.UP*.04
			check(_clear(actor,at),who+" whole capsule fits "+key)
			check(_supported(at),who+" floor supports "+key)
		for key in room.interaction_points:
			var at: Vector3 = room.interaction_points[key]+Vector3.UP*.04
			check(_clear(actor,at),who+" whole capsule fits interaction "+str(key))
			check(_supported(at),who+" interaction is on supported floor "+str(key))
		for reward in room.reward_points:
			check(_clear(actor,reward.position+Vector3.UP*.04),who+" reward accessible on open floor")
		var spine := Vector3(0,.04,-1.10)
		check(_walks(actor,Vector3(0,.04,3.5),spine),who+" front entrance reaches central aisle")
		for key in ARCADE.STATIONS:
			var at: Vector3 = ARCADE.STATIONS[key]+Vector3.UP*.04
			var turning := Vector3(at.x,.04,spine.z)
			check(_walks(actor,spine,turning) and _walks(actor,turning,at),who+" continuous corridor to "+str(key))
		check(_walks(actor,Vector3(0,.04,3.5),Vector3(-4.1,.04,3.5)),who+" reward corridor open")
		var swept: Array[String] = []
		for body in room.solid_bodies:
			var id := str(body.get_meta("interior_solid_id",""))
			if id=="Floor": continue
			var bounds: AABB = body.get_meta("bounds")
			var center := bounds.get_center()
			var face_checks := 0
			for direction: Vector3 in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				var extent := bounds.size.x*.5 if absf(direction.x)>.5 else bounds.size.z*.5
				var start := Vector3(center.x,.04,center.z)+direction*(extent+.62)
				if absf(start.x)>5.56 or absf(start.z)>4.56 or not _clear(actor,start): continue
				var from := actor.global_transform
				from.origin = start
				check(actor.test_move(from,-direction*(extent*2+1.24)),who+" long sweep blocks "+id+" face "+str(direction))
				face_checks += 1
			# Diagonal approach to a real corner also must hit, without tunneling.
			var corner := Vector3(bounds.end.x+.40,.04,bounds.end.z+.40)
			if absf(corner.x)<5.56 and absf(corner.z)<4.56 and _clear(actor,corner):
				var from := actor.global_transform
				from.origin = corner
				check(actor.test_move(from,Vector3(-1.2,0,-1.2)),who+" corner sweep blocks "+id)
				face_checks += 1
			if face_checks>0: swept.append(id)
		for id in ["PinballCabinet","BlocksCabinet","RacerCabinet","FighterCabinet","LiaCabinet","IvoCabinet","LoungeBench","LowTable","TokenExchanger"]:
			check(id in swept,who+" reached and swept furniture "+id)
		actor.free()

func _residents() -> void:
	var residents: Array[CharacterBody3D] = []
	for definition in room.definition.npcs:
		var actor := ACTOR.new()
		actor.controlled_automatically = true
		actor.position = definition.local_position+Vector3.UP*.04
		actor.set_meta("interior_npc_id",definition.id)
		stage.add_child(actor)
		actor.set_physics_process(false)
		var old := actor.visual.get_child(0)
		actor.visual.remove_child(old)
		old.queue_free()
		var model := RESIDENTS.create_model(definition)
		actor.visual.add_child(model)
		residents.append(actor)
	room.on_session_entered({"room_npcs":residents})
	for frame in 3: await physics_frame
	for actor in residents:
		var model: Node3D = actor.visual.get_child(0)
		check(_clear(actor,actor.position),"resident admission clear "+str(actor.get_meta("interior_npc_id")))
		check(model.get_meta("work_activity","")=="arcade","resident uses dedicated playing pose")
		var hands: Array = model.hand_provider.call()
		check(hands.size()==2 and hands[0] is Vector3 and hands[1] is Vector3,"resident reaches two controls")
		if hands[0] is Vector3:
			check(hands[0].x>actor.position.x+.35,"resident faces occupied machine")
		actor.set_meta("workplace_threatened",true)
		check(model.hand_provider.call()==[null,null],"playing pose yields during real workplace reaction")
		actor.set_meta("workplace_threatened",false)
	for actor in residents: actor.free()
	await physics_frame
	check(stage.find_children("*","CharacterBody3D",true,false).is_empty(),"resident/visitor removal leaves no actor in fixture")

func _depth() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("272631")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4c7b1")
	settings.ambient_light_energy = .65
	environment.environment = settings
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = room.camera_size
	stage.add_child(camera)
	camera.position = room.camera_target+Vector3(0,18,15)
	camera.look_at(room.camera_target)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.position = Vector3(0,.04,1)
		var who := "dante" if is_player else "visitor"
		for frame in 5: await process_frame
		var natural := await capture()
		check(natural.save_png(folder.path_join(who+"-natural.png"))==OK,who+" natural evidence saved")
		mask_meshes(actor.visual,diagnostic)
		for setup in [
			{"id":"entrance","at":Vector3(0,.04,3.5),"occluded":false},
			{"id":"cabinet-front","at":Vector3(-1.45,.04,-2.1),"occluded":false},
			{"id":"cabinet-side","at":Vector3(-2.85,.04,-3.1),"occluded":false},
			{"id":"table-front","at":Vector3(-4.2,.04,3.15),"occluded":false},
			{"id":"table-side","at":Vector3(-3.55,.04,2.30),"occluded":false},
			{"id":"table-behind","at":Vector3(-4.2,.04,1.47),"occluded":true},
		]:
			actor.position = setup.at
			actor.reset_physics_interpolation()
			check(_clear(actor,actor.position),who+" depth probe is physically clear "+setup.id)
			room.show()
			var rendered := await capture()
			room.hide()
			var control := await capture()
			room.show()
			var positive := mask_count(control)
			var visible := mask_count(rendered)
			var ratio := float(visible)/maxf(positive,1)
			check(positive>45,who+" "+setup.id+" visible positive control")
			if setup.occluded:
				check(ratio>.15 and ratio<.97,who+" table occludes lower body while keeping upper body visible "+str(ratio))
			else:
				check(ratio>.85,who+" remains visible "+setup.id+" "+str(ratio))
			rendered.save_png(folder.path_join(who+"-"+setup.id+".png"))
			control.save_png(folder.path_join(who+"-"+setup.id+"-control.png"))
			records.append({"actor":who,"pose":setup.id,"visible":visible,"control":positive,"ratio":ratio})
		actor.free()

func _clear(actor: CharacterBody3D, at: Vector3) -> bool:
	var from := actor.global_transform
	from.origin = at
	return not actor.test_move(from,Vector3.UP*.001)

func _walks(actor: CharacterBody3D, from_point: Vector3, to_point: Vector3) -> bool:
	var from := actor.global_transform
	from.origin = from_point
	return _clear(actor,from_point) and _clear(actor,to_point) and not actor.test_move(from,to_point-from_point)

func _supported(at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.12,at-Vector3.UP*.35,1)
	var hit := stage.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y>.8 and absf(hit.position.y-at.y)<.25
