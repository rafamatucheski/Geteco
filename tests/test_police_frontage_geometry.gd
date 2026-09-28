extends "res://tests/test_vertice_depth.gd"
const DEST := "res://evidence/police-frontage-20260928/geometry"

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport = SubViewport.new()
	viewport.size = Vector2i(640,480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100,.2,100)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(66,-.1,120)
	stage.add_child(floor_body)
	var zone := preload("res://world/harbor_route_detail/HarborRouteDetail3D.gd")._build_delegacia_zone()
	stage.add_child(zone)
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var shell := Node3D.new()
	stage.add_child(shell)
	for building in region.buildings:
		if building.id == "Police": region._building(shell,building)
	region.free()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	stage.add_child(camera)
	camera.current = true
	var mask := StandardMaterial3D.new()
	mask.albedo_color = Color(1,0,1)
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.speed = 3.5
		stage.add_child(actor)
		var who := "player" if player else "npc"
		actor.teleport(Vector3(66,.03,131.5))
		for tick in 5: await physics_frame
		actor.automatic_direction = Vector3.FORWARD
		for tick in 65: await physics_frame
		check(actor.position.z < 128.0 and absf(actor.position.y-.1)<.06, who+" climbs real ramp to sidewalk "+str(actor.position))
		actor.automatic_direction = Vector3.BACK
		for tick in 75: await physics_frame
		check(actor.position.z > 130.8 and absf(actor.position.y)<.06, who+" returns to road at ground level")
		actor.automatic_direction = Vector3.ZERO
		actor.teleport(Vector3(60,.14,126.8))
		actor._steering = null
		for tick in 5: await physics_frame
		actor.automatic_direction = Vector3.LEFT
		var stayed_out := true
		for tick in 60:
			await physics_frame
			stayed_out = stayed_out and (absf(actor.position.x-58)>.27 or absf(actor.position.z-126.8)>1.0) and actor.position.y<.18
		check(stayed_out, who+" cannot walk through or onto civic bench")
		actor.automatic_direction = Vector3.ZERO
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual,mask)
		for item in [
			{"id":"bench","camera":Vector3(66,3,126.8),"target":Vector3(58,.8,126.8),"front":Vector3(60,.1,126.8),"behind":Vector3(56.8,.1,126.8)},
			{"id":"facade","camera":Vector3(70,3,135),"target":Vector3(70,1,125),"front":Vector3(70,.1,127),"behind":Vector3(70,.1,124)}]:
			camera.position = item.camera
			camera.look_at(item.target)
			for pose in ["front","behind"]:
				actor.position = item[pose]
				zone.show(); shell.show()
				var actual := await capture()
				zone.hide(); shell.hide()
				var control := await capture()
				var pixels := mask_count(control)
				var ratio := float(mask_count(actual))/maxf(pixels,1)
				check(pixels>150,who+" "+item.id+" "+pose+" positive depth control")
				check(ratio>.9 if pose=="front" else ratio<.9,who+" "+item.id+" "+pose+" depth ratio="+str(ratio))
				actual.save_png(DEST+"/"+who+"-"+item.id+"-"+pose+".png")
			zone.show(); shell.show()
		actor.free()
	FileAccess.open(DEST+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("POLICE_FRONTAGE_GEOMETRY checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	quit(0 if failures.is_empty() else 1)
