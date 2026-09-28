extends "res://tests/test_vertice_depth.gd"
## Depth of the new props, inheriting the validated capture/mask helpers.
const DETAIL := preload("res://gameplay/urban_v1/VerticeSiteDressing.gd")
const DETAIL_OUTPUT := "res://evidence/vertice-detail-20260928/depth"

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DETAIL_OUTPUT))
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,480)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene:=Node3D.new()
	viewport.add_child(scene)
	var world_environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("abb8b8")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.7
	world_environment.environment=settings
	scene.add_child(world_environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	scene.add_child(sun)
	var dressing:=DETAIL.new()
	scene.add_child(dressing)
	dressing.set_cutaway(true)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8
	camera.far=90
	scene.add_child(camera)
	camera.current=true
	var mask:=StandardMaterial3D.new()
	mask.albedo_color=Color(1,0,1)
	mask.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var setups: Array[Dictionary]=[
		{"id":"cargo","camera":Vector3(-23,4,28),"target":Vector3(-23,1.2,44),"front":Vector3(-23,.04,41.8),"behind":Vector3(-23,.04,46),"side":Vector3(-26,.04,44)},
		{"id":"rest_table","camera":Vector3(27.5,4,62),"target":Vector3(27.5,1,71),"front":Vector3(27.5,.04,68.9),"behind":Vector3(27.5,.04,73.1),"side":Vector3(25.6,.04,71)}]
	for player in [true,false]:
		var actor:=ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		scene.add_child(actor)
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		var who:="player" if player else "npc"
		actor.position=setups[0].front
		camera.position=setups[0].camera
		camera.look_at(setups[0].target)
		var natural:=await capture()
		check(natural.save_png(DETAIL_OUTPUT+"/"+who+"-natural.png")==OK,who+" natural render saved")
		mask_meshes(actor.visual,mask)
		for setup in setups:
			camera.position=setup.camera
			camera.look_at(setup.target)
			for pose in ["front","behind","side"]:
				actor.position=setup[pose]
				dressing.show()
				var rendered:=await capture()
				var pixels:=mask_count(rendered)
				var id: String=who+"-"+setup.id+"-"+pose
				check(rendered.save_png(DETAIL_OUTPUT+"/"+id+".png")==OK,id+" saved")
				dressing.hide()
				var control:=await capture()
				var control_pixels:=mask_count(control)
				check(control.save_png(DETAIL_OUTPUT+"/"+id+"-control.png")==OK,id+" positive control saved")
				check(control_pixels>150,id+" positive control contains actual actor")
				var ratio:=float(pixels)/maxf(float(control_pixels),1)
				if pose!="behind": check(ratio>.9,id+" is visible in front/beside: "+str(ratio))
				elif setup.id=="cargo": check(ratio<.15,id+" is occluded by loaded pallet: "+str(ratio))
				else: check(ratio>.05 and ratio<.9,id+" table preserves upper body and hides lower part: "+str(ratio))
				records.append({"actor":who,"prop":setup.id,"pose":pose,"visible_pixels":pixels,"control_pixels":control_pixels,"visible_ratio":ratio})
				dressing.show()
		actor.free()
	var report:=FileAccess.open(DETAIL_OUTPUT+"/results.json",FileAccess.WRITE)
	check(report!=null,"Report saved")
	if report: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"))
	print("VERTICE_SITE_DEPTH checks=",checks," failures=",failures)
	scene.free()
	viewport.free()
	for frame in 2: await process_frame
	quit(0 if failures.is_empty() else 1)
