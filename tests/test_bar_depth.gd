extends "res://tests/test_vertice_depth.gd"
## Rendered native geometry and production Actor/BarPatronModel rigs.
## Diagnostic masks test actual depth against an unobstructed positive control.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const RESIDENTS := preload("res://world/places/OriginalResidents.gd")
const DEST := "res://artifacts/bars-20261027/depth"

func make_actor(stage: Node3D, player: bool, resident := {}) -> CharacterBody3D:
	var actor := ACTOR.new()
	actor.is_player=player
	actor.controlled_automatically=true
	actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	stage.add_child(actor)
	actor.set_physics_process(false)
	if not player:
		var original: Node=actor.visual.get_child(0)
		actor.visual.remove_child(original)
		original.queue_free()
		actor.visual.add_child(RESIDENTS.create_model(resident))
	return actor

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport=SubViewport.new()
	viewport.size=Vector2i(1280,960)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("40382f")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("eee1cc")
	settings.ambient_light_energy=.55
	env.environment=settings
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-60,-20,0)
	light.light_energy=.55
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=90
	stage.add_child(camera)
	camera.current=true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for id in ["harbor_bar","desert_bar"]:
		var room = CATALOG.create_place(id)
		stage.add_child(room)
		camera.size=room.camera_size
		camera.position=room.camera_target+Vector3(0,18,15)
		camera.look_at(room.camera_target)
		var crowd: Array[Node3D]=[]
		for i in room.definition.npcs.size():
			var resident: Dictionary=room.definition.npcs[i]
			var actor := make_actor(stage,false,resident)
			actor.position=resident.local_position+Vector3.UP*.04
			actor.visual.rotation.y=room.definition.bar_drinker_yaws[i]
			crowd.append(actor)
		var dante := make_actor(stage,true)
		dante.position=room.definition.spawn+Vector3.UP*.04
		crowd.append(dante)
		for frame in 30: await process_frame
		var natural := await capture()
		check(natural.save_png(DEST.path_join(id+"-natural.png"))==OK,id+" natural room with Dante and native patrons saved")
		for actor in crowd: actor.free()
		var setups: Array[Dictionary]
		if id=="harbor_bar":
			setups=[
				{"id":"pool","front":Vector3(3.5,.04,2.4),"behind":Vector3(3.5,.04,-2.35),"side":Vector3(1.8,.04,0)},
				{"id":"counter","front":Vector3(-3.7,.04,-2.55),"behind":Vector3(-3.7,.04,-4.65),"side":Vector3(.5,.04,-3.6)}]
		else:
			setups=[
				{"id":"pool","front":Vector3(1,.04,1.05),"behind":Vector3(1,.04,-2.05),"side":Vector3(-1.2,.04,-.5)},
				{"id":"counter","front":Vector3(-5.6,.04,1.55),"behind":Vector3(-5.6,.04,-4.65),"side":Vector3(-3.9,.04,-1.5)}]
		for player in [true,false]:
			var actor := make_actor(stage,player,room.definition.npcs[0])
			for frame in 12: await process_frame
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			mask_meshes(actor.visual,diagnostic)
			var who := "Dante" if player else "patron"
			for setup in setups:
				for pose in ["front","behind","side"]:
					actor.position=setup[pose]
					actor.reset_physics_interpolation()
					check(not actor.test_move(actor.global_transform,Vector3.UP*.001),id+" "+who+" "+setup.id+" "+pose+" whole capsule clear")
					room.show()
					var actual := await capture()
					room.hide()
					var control := await capture()
					room.show()
					var visible_pixels := mask_count(actual)
					var control_pixels := mask_count(control)
					var ratio := float(visible_pixels)/maxf(1,control_pixels)
					var key: String=id+"-"+who+"-"+setup.id+"-"+pose
					check(control_pixels>150,key+" positive visible control")
					if pose=="behind":
						check(ratio>.1 and ratio<.98,key+" real furniture occludes lower body while upper body visible ratio="+str(ratio))
					else:
						check(ratio>.80,key+" front/side actor visible ratio="+str(ratio))
					actual.save_png(DEST.path_join(key+".png"))
					control.save_png(DEST.path_join(key+"-control.png"))
					records.append({"room":id,"actor":who,"prop":setup.id,"pose":pose,"visible_pixels":visible_pixels,"control_pixels":control_pixels,"ratio":ratio})
			actor.free()
		room.free()
		await process_frame
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"viewport":"1280x960","records":records}
	FileAccess.open(DEST.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BAR_DEPTH checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
