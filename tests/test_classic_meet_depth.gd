extends "res://tests/test_vertice_depth.gd"
## Real rigs against a parked exhibition car, with positive depth controls.
var folder := ""

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder=arg.trim_prefix("--out=")
	if DisplayServer.get_name()=="headless" or folder.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,480)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene:=Node3D.new()
	scene.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(scene)
	var sunlight:=DirectionalLight3D.new()
	sunlight.rotation_degrees=Vector3(-48,-30,0)
	scene.add_child(sunlight)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8
	scene.add_child(camera)
	camera.current=true
	var diagnostic:=StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var fixtures: Array[Dictionary] = []
	for model in preload("res://gameplay/classic_meet/ClassicMeetController.gd").MODELS:
		var car=preload("res://gameplay/classic_meet/ClassicMeetCar.gd").new()
		car.model_id=model
		car.hood_open=model=="roadster"
		scene.add_child(car)
		car.hide()
		fixtures.append({"id":model,"node":car,"camera":Vector3(0,4,10),"target":Vector3(0,.8,0),"front":Vector3(0,.05,3.1),"behind":Vector3(0,.05,-3.1),"side":Vector3(2.8,.05,0)})
	var site=preload("res://world/places/classic_meet/ClassicMeetSite.gd").new()
	scene.add_child(site)
	site.position=Vector3.ZERO
	site.hide()
	for spec in [{"id":"tire-display","x":-7.9},{"id":"tool-chest","x":7.45}]:
		# O controle da vitrine de pneus fica ao lado das duas prateleiras e livre do poste do varal de luzes.
		var side_x: float = -5.1 if spec.id=="tire-display" else spec.x-1.7
		fixtures.append({"id":spec.id,"node":site,"camera":Vector3(spec.x,3,-5),"target":Vector3(spec.x,.8,4.85),"front":Vector3(spec.x,.05,3.4),"behind":Vector3(spec.x,.05,5.6),"side":Vector3(side_x,.05,4.85)})
	fixtures.append({"id":"store-wall","node":site,"camera":Vector3(0,8,-10),"target":Vector3(0,1.8,10),"size":32.0,"front":Vector3(0,.05,3.6),"behind":Vector3(0,.05,15),"side":Vector3(11,.05,10)})
	for player in [true,false]:
		var actor:=ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		scene.add_child(actor)
		actor.set_physics_process(false)
		for frame in 30: await process_frame
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual,diagnostic)
		var who:="player" if player else "npc"
		for fixture in fixtures:
			camera.size=fixture.get("size",8.0)
			camera.position=fixture.camera
			camera.look_at(fixture.target)
			for pose in ["front","behind","side"]:
				actor.position=fixture[pose]
				actor.reset_physics_interpolation()
				fixture.node.show()
				var actual:=await capture()
				var visible_pixels:=mask_count(actual)
				fixture.node.hide()
				var control:=await capture()
				var total_pixels:=mask_count(control)
				var ratio:=float(visible_pixels)/maxf(total_pixels,1)
				var id: String=who+"-"+str(fixture.id)+"-"+str(pose)
				check(total_pixels>100,id+" unobstructed actor exists")
				check(ratio<.9 if pose=="behind" else ratio>.9,id+" depth ratio "+str(ratio))
				actual.save_png(folder.path_join(id+".png"))
				control.save_png(folder.path_join(id+"-control.png"))
				records.append({"id":id,"visible":visible_pixels,"control":total_pixels,"ratio":ratio})
		actor.free()
	FileAccess.open(folder.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records}))
	print("CLASSIC_MEET_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
