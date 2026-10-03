extends "res://tests/test_vertice_depth.gd"
const ZOO=preload("res://world/mountain_detail/zoo/MountainZoo.gd")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	viewport=SubViewport.new(); viewport.size=Vector2i(640,480)
	viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage:=Node3D.new(); stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var zoo:=ZOO.new(); stage.add_child(zoo); zoo.set_process(false)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6; stage.add_child(camera); camera.make_current()
	var material:=StandardMaterial3D.new(); material.albedo_color=Color(1,0,1)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var results: Array[Dictionary]=[]
	for player in [true,false]:
		var actor:=ACTOR.new(); actor.is_player=player
		stage.add_child(actor); actor.set_physics_process(false)
		mask_meshes(actor.visual,material)
		for setup in [
			{"id":"bench","at":Vector3(-21.8,0,1.2),"front":Vector3(-21.8,.08,2),"behind":Vector3(-21.8,.08,.4),"side":Vector3(-20.3,.08,1.2)},
			{"id":"fence","at":Vector3(10.5,0,-2.3),"front":Vector3(10.5,.08,-1.5),"behind":Vector3(10.5,.08,-3.1),"side":Vector3(1.6,.08,-2.3)}]:
			for pose in ["front","behind","side"]:
				actor.position=setup[pose]
				camera.position=actor.position+Vector3(0,25.3,25.3)
				camera.look_at(actor.position+Vector3.UP*.8)
				zoo.show()
				var rendered:=await capture()
				var visible_pixels:=mask_count(rendered)
				zoo.hide()
				var control:=await capture()
				var control_pixels:=mask_count(control)
				var ratio:=float(visible_pixels)/maxf(control_pixels,1)
				check(control_pixels>100,"Positive actor visibility control")
				check(ratio>.08,"Actor remains readable beside zoo structures")
				if pose=="behind": check(ratio<.98,"Fence/bench occludes behind actor")
				else: check(ratio>.9,"Front and side actor stay unobstructed")
				results.append({"player":player,"object":setup.id,"pose":pose,"ratio":ratio})
				zoo.show()
		actor.free()
	FileAccess.open("res://artifacts/mountain-zoo/depth.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"results":results},"\t"))
	print("ZOO_DEPTH ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
