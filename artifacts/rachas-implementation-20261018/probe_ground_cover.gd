extends "res://artifacts/rachas-implementation-20261018/measure_design.gd"
## Finite visual diagnosis: original range vs. no range on the exact same
## resident batches and camera. This is not a performance measurement.

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("drag-cover-probe")
	var at: Vector3=LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary=FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode=true
	var session=world.session
	var race=session.desert.drag
	race.open_meet.enabled=false
	session.weather.set_process(false)
	session.weather.time_of_day=.9
	session.weather._update()
	var region=world.production.regions.desert
	for i in 2400:
		await process_frame
		if region.is_streaming_idle(): break
	var camera:=Camera3D.new()
	camera.fov=57
	camera.far=2200
	camera.near=.2
	world.add_child(camera)
	camera.make_current()
	var batches: Array[MultiMeshInstance3D]=[]
	for chunk in region.chunks.values():
		for child in chunk.get_children():
			if child is MultiMeshInstance3D and str(child.name).begins_with("DesertGroundCover_"): batches.append(child)
	var report: Dictionary={"batches":[],"positions":[]}
	for node in batches:
		var box: AABB=node.get_aabb()
		report.batches.append({"name":str(node.get_path()),"end":node.visibility_range_end,"center":_array3(node.global_transform*box.get_center()),"size":_array3(box.size),"instances":node.multimesh.instance_count})
	for x in [-900.0,-630.0,-280.0]:
		var frame: Dictionary=race.camera_frame(Vector3(x,0,-1318),Vector3(x,0,-1322))
		camera.global_position=frame.position
		camera.look_at(frame.target,Vector3.UP)
		report.positions.append({"x":x,"camera":_array3(camera.global_position)})
		for i in 5: await process_frame
		await capture("original_%d"%int(x))
		for node in batches:
			node.set_meta("probe_original_end",node.visibility_range_end)
			node.visibility_range_end=0
		for i in 5: await process_frame
		await capture("unlimited_%d"%int(x))
		for node in batches: node.visibility_range_end=float(node.get_meta("probe_original_end"))
	var file:=FileAccess.open(output.path_join("batches.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DRAG_COVER_PROBE_DONE ",output)
	world.free()
	quit()

func _array3(p: Vector3) -> Array: return [p.x,p.y,p.z]
