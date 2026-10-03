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
	var car=preload("res://gameplay/classic_meet/ClassicMeetCar.gd").new()
	car.model_id="parati"
	scene.add_child(car)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8
	scene.add_child(camera)
	camera.position=Vector3(0,4,10)
	camera.look_at(Vector3(0,.8,0))
	camera.current=true
	var diagnostic:=StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
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
		for setup in [{"id":"front","point":Vector3(0,.05,3.1)},{"id":"behind","point":Vector3(0,.05,-3.1)},{"id":"side","point":Vector3(2.8,.05,0)}]:
			actor.position=setup.point
			actor.reset_physics_interpolation()
			car.show()
			var actual:=await capture()
			var visible_pixels:=mask_count(actual)
			car.hide()
			var control:=await capture()
			var total_pixels:=mask_count(control)
			var ratio:=float(visible_pixels)/maxf(total_pixels,1)
			var id:=who+"-"+str(setup.id)
			check(total_pixels>100,id+" unobstructed actor exists")
			check(ratio<.9 if setup.id=="behind" else ratio>.9,id+" depth ratio "+str(ratio))
			actual.save_png(folder.path_join(id+".png"))
			control.save_png(folder.path_join(id+"-control.png"))
			records.append({"id":id,"visible":visible_pixels,"control":total_pixels,"ratio":ratio})
		car.show()
		actor.free()
	FileAccess.open(folder.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records}))
	print("CLASSIC_MEET_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
