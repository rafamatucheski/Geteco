extends "res://tests/test_vertice_depth.gd"
## Harbor refresh: actual meshes, native solid inventory, swept Actor bodies,
## and separate rendered depth controls. --physics-only allows headless logic.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const DEST := "res://artifacts/ammunation-refresh-20261019/depth"
var physics_only := false

func run() -> void:
	physics_only = "--physics-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not physics_only:
		push_error("Ammunation depth requires rendering; use --physics-only for physics")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var room = PLACES.create_place("harbor_ammunation")
	stage.add_child(room)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = room.camera_size
	stage.add_child(camera)
	camera.position = Vector3(0,18.7,15)
	camera.look_at(Vector3(0,.7,0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("aab5b8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .75
	stage.add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48,-30,0)
	sunlight.light_energy = 1.0
	stage.add_child(sunlight)
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for frame in 3: await physics_frame
	_inventory(room)
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		for frame in 20: await process_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var who := "player" if is_player else "npc"
		_physics(room,actor,who)
		if not physics_only:
			actor.position = Vector3(-1.4,.04,-.7)
			actor.reset_physics_interpolation()
			var natural := await capture()
			check(natural.save_png(DEST.path_join(who+"-natural.png")) == OK, who+" natural capture")
			mask_meshes(actor.visual,diagnostic)
			await _depth(room,actor,who)
		actor.free()
	room.set_active(false)
	check(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED,"inactive room stops visibility and processing")
	room.set_active(true)
	check(room.visible and room.process_mode == Node.PROCESS_MODE_INHERIT,"room reactivation restores presentation")
	FileAccess.open(DEST.path_join("physics-results.json" if physics_only else "results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"physics_only":physics_only},"\t"))
	print("AMMUNATION_REFRESH checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _inventory(room: Node3D) -> void:
	var count := 0
	for mesh in room.model.find_children("*","MeshInstance3D",true,false):
		var parent: Node = mesh
		var merchant := false
		while parent != room.model:
			if parent.name == "VanceMilitaryGunsmith": merchant = true
			parent = parent.get_parent()
		if merchant: continue
		var bounds: AABB = (room.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if bounds.end.y < .06 or bounds.position.y > 2.1: continue
		var covered := false
		var footprint := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
		for solid: AABB in room.solid_bounds:
			if Rect2(solid.position.x,solid.position.z,solid.size.x,solid.size.z).grow(.025).encloses(footprint):
				covered = true
				break
		count += 1
		check(covered,"solid coverage "+str(mesh.get_path())+" "+str(footprint))
	check(count > 70,"complete furniture inventory includes small display pieces")

func _physics(room: Node3D,actor: CharacterBody3D,who: String) -> void:
	for point: Vector3 in [room.definition.spawn,Vector3(0,0,-.9),Vector3(-3.4,0,0),Vector3(3.5,0,0),Vector3(-1,0,-3.45),Vector3(5.85,0,-2)]:
		actor.position = room.to_global(point+Vector3.UP*.04)
		check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" full-body clearance "+str(point))
	for setup in [
		{"id":"counter front","start":Vector3(0,.04,-.8),"delta":Vector3(0,0,-2)},
		{"id":"counter corner","start":Vector3(3.3,.04,-1.0),"delta":Vector3(-2,0,-2)},
		{"id":"armor display","start":Vector3(-3.5,.04,.5),"delta":Vector3(-3,0,0)},
		{"id":"grenade display","start":Vector3(3.5,.04,.5),"delta":Vector3(3,0,0)},
		{"id":"stock cases","start":Vector3(4,.04,3),"delta":Vector3(3,0,0)},
		{"id":"east wall large step","start":Vector3(4,.04,-1.45),"delta":Vector3(8,0,0)},
		{"id":"rear cabinet","start":Vector3(2.25,.04,-3.3),"delta":Vector3(0,0,-2)}]:
		actor.position = room.to_global(setup.start)
		check(actor.test_move(actor.global_transform,setup.delta),who+" swept block "+setup.id)
	# Continuous body sweeps along valid customer, service and staff corridors.
	var route := [Vector3(0,.04,2.65),Vector3(0,.04,-.9),Vector3(3.5,.04,-.9),Vector3(3.5,.04,-3.4),Vector3(1,.04,-3.4)]
	for i in range(route.size()-1):
		actor.position = room.to_global(route[i])
		check(not actor.test_move(actor.global_transform,route[i+1]-route[i]),who+" circulation segment "+str(i))
	check(room.is_floor_clear(room.to_local(room.interaction_points.service)),who+" service remains reachable")
	# Real native floor: body settles using its collider instead of point probes.
	actor.position = room.spawn_position+Vector3.UP*.15
	for frame in 30:
		actor.velocity = Vector3(0,-3,0)
		actor.move_and_slide()
	check(actor.is_on_floor() and absf(actor.position.y)<.08,who+" actual floor support at spawn")

func _depth(room: Node3D,actor: CharacterBody3D,who: String) -> void:
	for setup in [
		{"id":"counter-front","point":Vector3(-1,.04,-.7),"behind":false},
		{"id":"counter-behind","point":Vector3(-1,.04,-3.2),"behind":true},
		{"id":"counter-side","point":Vector3(3.4,.04,-2.2),"behind":false},
		{"id":"display-front","point":Vector3(-5.5,.04,4.3),"behind":false},
		{"id":"display-behind","point":Vector3(-5.5,.04,-1.5),"behind":true},
		{"id":"display-side","point":Vector3(-4,.04,.5),"behind":false}]:
		actor.position = room.to_global(setup.point)
		check(room.is_floor_clear(setup.point),who+" "+setup.id+" authored pose outside furniture")
		actor.reset_physics_interpolation()
		room.show()
		var actual := await capture()
		room.hide()
		var control := await capture()
		room.show()
		var pixels := mask_count(actual)
		var control_pixels := mask_count(control)
		var ratio := float(pixels)/maxf(1,control_pixels)
		check(control_pixels>150,who+" "+setup.id+" positive visible control")
		if setup.behind:
			check(ratio>.08 and ratio<.95,who+" "+setup.id+" furniture occludes lower body and preserves upper body: "+str(ratio))
		else:
			check(ratio>.90,who+" "+setup.id+" actor visible in front/beside: "+str(ratio))
		actual.save_png(DEST.path_join(who+"-"+setup.id+".png"))
		control.save_png(DEST.path_join(who+"-"+setup.id+"-control.png"))
		records.append({"actor":who,"pose":setup.id,"pixels":pixels,"control_pixels":control_pixels,"ratio":ratio})
