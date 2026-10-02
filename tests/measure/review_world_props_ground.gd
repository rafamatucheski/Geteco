extends "res://tests/measure/review_mountain_shops.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var tag := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	folder = "res://evidence/world-props-ground-20261002/"+tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.locked = true
	var sites := {"resort":CATALOG._at(Vector2(7310,-2700),"mountain"),"ground":CATALOG._at(Vector2(7250,-2678),"mountain"),"village":CATALOG._at(Vector2(7650,-1553),"mountain"),"logging":CATALOG._at(Vector2(6440,580),"mountain"),"harbor":CATALOG._at(Vector2(5150,2400),"harbor")}
	if "--review-ground" in OS.get_cmdline_user_args(): sites["outfitters"] = CATALOG._at(Vector2(5980,715),"mountain")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--site="):
			var chosen := arg.trim_prefix("--site=")
			if sites.has(chosen): sites = {chosen:sites[chosen]}
	for label in sites:
		var point: Vector3 = sites[label]
		world.player.teleport(point+Vector3(0,.08,3))
		world.production._update_physical_residency(point)
		world.production._update_logical_region(point)
		world.production.region.set_focus(point)
		await frames(240)
		world.camera.size = 18 if label == "harbor" else 12
		world.camera.global_position = point+Vector3(8,15,11)
		world.camera.look_at(point)
		await frames(30)
		await shot(label)
		if label == "ground":
			var meshes: Array = []
			for mesh in world.find_children("*","MeshInstance3D",true,false):
				var box: AABB = mesh.global_transform*mesh.get_aabb()
				if box.grow(.2).has_point(point) or (box.position.x<point.x and box.end.x>point.x and box.position.z<point.z and box.end.z>point.z and box.position.y<.2):
					meshes.append({"path":str(mesh.get_path()),"visible":mesh.is_visible_in_tree(),"bounds":str(box),"material":str(mesh.material_override.resource_path if mesh.material_override else "mesh")})
			FileAccess.open(folder.path_join("ground-meshes.json"),FileAccess.WRITE).store_string(JSON.stringify(meshes,"\t"))
		if "--visual-only" not in OS.get_cmdline_user_args() and label != "outfitters": await measure(label)
		if label == "ground" and "--review-ground" in OS.get_cmdline_user_args():
			for index in 3:
				var offsets := [Vector3(-8,12,11),Vector3(0,18,1),Vector3(8,7,11)]
				world.camera.global_position = point+offsets[index]
				world.camera.look_at(point)
				await frames(20)
				await shot("ground-angle-"+str(index))
			var supports: Array = []
			for x in [-2.0,0.0,2.0]:
				var at := point+Vector3(x,0,3)
				var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP,1)
				query.exclude = [world.player.get_rid()]
				var hit := root.world_3d.direct_space_state.intersect_ray(query)
				supports.append({"point":str(at),"supported":not hit.is_empty(),"height":float(hit.position.y) if not hit.is_empty() else -999.0})
			FileAccess.open(folder.path_join("ground-support.json"),FileAccess.WRITE).store_string(JSON.stringify(supports,"\t"))
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"rows":rows},"\t"))
	quit()
