extends "res://tests/test_vertice_depth.gd"
## Real Actor player/NPC rigs, full-volume swept collision and native depth with visible controls.
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")
const NATIVE_PLACE := preload("res://world/places/NativePlace.gd")
var dest := "D:/geteco/artifacts/desert-20261006/depth"
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Desert depth requires rendered Godot .NET")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(dest)
	viewport=SubViewport.new()
	viewport.size=Vector2i(960,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("575247")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e0d1b5")
	env.environment.ambient_light_energy=.75
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-20,0)
	sun.light_energy=.7
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current=true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for definition in DESERT_LAYOUT.place_definitions():
		var room := NATIVE_PLACE.new()
		room.definition=definition
		stage.add_child(room)
		camera.size=definition.camera_size
		camera.position=definition.camera_target+Vector3(0,18,15)
		camera.look_at(definition.camera_target)
		await physics_frame
		await physics_frame
		var bank: bool=definition.id=="desert_bank"
		var front := Vector3(-1.5,.04,-1.35) if bank else Vector3(8.4,.04,1.65)
		var behind := Vector3(-1.5,.04,-3.45) if bank else Vector3(8.4,.04,-1.2)
		var side := Vector3(7.9,.04,-2.6) if bank else Vector3(5.9,.04,0)
		# The original workshop side probe falls under the projected roof truss.
		# Keep that real overhead occlusion as its own case; measure unobstructed
		# furniture-side visibility beside the front corner instead.
		var visible_side := side if bank else Vector3(5.9,.04,1.35)
		for is_player in [true,false]:
			var actor := ACTOR.new()
			actor.is_player=is_player
			actor.controlled_automatically=true
			actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			stage.add_child(actor)
			actor.set_physics_process(false)
			for frame in 12: await process_frame
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			var who := "player" if is_player else "npc"
			var prefix: String=definition.id+"-"+who
			actor.position=definition.spawn+Vector3.UP*.04
			check(not actor.test_move(actor.global_transform,Vector3(0,0,-2)),prefix+" valid entry corridor remains open")
			actor.position=front
			check(actor.test_move(actor.global_transform,Vector3(0,0,-3.5)),prefix+" swept body cannot pass through counter")
			actor.position=side
			check(actor.test_move(actor.global_transform,Vector3(-3,0,0) if bank else Vector3(4,0,0)),prefix+" side approach blocks furniture corners")
			actor.position=Vector3(0,.04,5)
			check(actor.test_move(actor.global_transform,Vector3(40,0,0)),prefix+" large movement cannot tunnel through solid wall")
			actor.position=behind
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),prefix+" authored resident fits behind furniture")
			actor.position=front
			actor.reset_physics_interpolation()
			var natural := await capture()
			check(natural.save_png(dest.path_join(prefix+"-natural.png"))==OK,prefix+" natural screenshot")
			mask_meshes(actor.visual,diagnostic)
			var poses: Array[Dictionary]=[{"id":"front","position":front},{"id":"behind","position":behind},{"id":"side","position":visible_side}]
			if not bank: poses.append({"id":"under_truss","position":side})
			for pose in poses:
				actor.position=pose.position
				actor.reset_physics_interpolation()
				room.show()
				var actual := await capture()
				room.hide()
				var control := await capture()
				room.show()
				var visible_pixels := mask_count(actual)
				var control_pixels := mask_count(control)
				var ratio := float(visible_pixels)/maxf(1.0,float(control_pixels))
				var label: String=prefix+"-"+pose.id
				check(control_pixels>100,label+" unobstructed control contains real actor")
				if pose.id=="under_truss": check(ratio>.05 and ratio<.95,label+" overhead truss has real partial depth while actor remains readable ratio="+str(ratio))
				elif pose.id=="behind": check(ratio>.05 and ratio<.98,label+" furniture hides lower body while upper body remains visible ratio="+str(ratio))
				else: check(ratio>.85,label+" actor remains visible in front/beside ratio="+str(ratio))
				actual.save_png(dest.path_join(label+".png"))
				control.save_png(dest.path_join(label+"-control.png"))
				records.append({"room":definition.id,"actor":who,"pose":pose.id,"ratio":ratio,"visible_pixels":visible_pixels,"control_pixels":control_pixels})
			actor.free()
		room.free()
	FileAccess.open(dest.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("DESERT_WORLD_DEPTH checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
