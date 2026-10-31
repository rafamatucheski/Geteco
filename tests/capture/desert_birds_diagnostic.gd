extends "res://tests/desert_canyon_drive.gd"
## Experimento de identificação em pose fixa, explicitamente não um teste de direção/desempenho.
## capture_existing() também pode ser aguardado no fim de uma rodada real no cânion, preservando a fase do bando.

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): failures.append("100s diagnostic watchdog"); _finish(3))
	_run.call_deferred()

func _run() -> void:
	if not _check(DisplayServer.get_name()!="headless" and "--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered isolated .NET required"):
		_finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-birds-diagnostic")
	var point := Vector3(-1048,HM.surface_height(Vector2(-1048,-1809))+.32,-1809)
	var arrival := Vector3(-936.994,HM.surface_height(Vector2(-936.994,-1826.799))+.32,-1826.799)
	var snapshot := FIXTURE.full_snapshot(arrival,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":_v3(arrival)}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not _check(not path.is_empty(),"isolated checkpoint validates"): _finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path,"real Main isolated save ready"):
		_finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not _check(world.dispatch.router._native!=null,"native backend active"): _finish(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	for i in 20: await physics_frame
	var spawn := _diagnostic_spawn_point(point,1.35)
	car=world.production.spawn_vehicle("desert_bison",spawn,1.35)
	if not _check(is_instance_valid(car),"ordinary Bison spawn admitted"): _finish(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.35+Vector3.UP*.08)
	if not await _board(): _finish(1); return
	# Explicit fixture placement reproduces the prior fixed-pose screenshot, never traversal evidence.
	car.set_physics_process(false)
	car.global_position=point
	world.camera.initialized=false
	await create_timer(1.5).timeout
	var result := await capture_existing(self,world,output)
	reports.append(result)
	_check(not result.has("error"),"three-instance bird source found and captured")
	_finish(0 if failures.is_empty() else 1)

static func capture_existing(tree: SceneTree,main: Node3D,destination: String) -> Dictionary:
	var birds := main.find_child("DistantThermalGliders",true,false) as MultiMeshInstance3D
	var camera := main.get_viewport().get_camera_3d()
	if birds==null or camera==null: return {"error":"DistantThermalGliders or active camera missing"}
	var was_paused := tree.paused
	var was_visible := birds.visible
	tree.paused=true
	# Esperas só de render mantêm transformações, câmera comum e clima congelados no conjunto A/B/A.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var rows: Array[Dictionary]=[]
	var arrays := birds.multimesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in birds.multimesh.instance_count:
		var pose := birds.global_transform*birds.multimesh.get_instance_transform(i)
		var at: Vector3=pose.origin
		var projected := camera.unproject_position(at)
		var screen_bounds := Rect2(projected,Vector2.ZERO)
		for vertex in vertices: screen_bounds=screen_bounds.expand(camera.unproject_position(pose*vertex))
		var ground := HM.surface_height(Vector2(at.x,at.z))+L.surface_height(Vector2(at.x,at.z))
		rows.append({"instance":i,"world":[at.x,at.y,at.z],"screen":[projected.x,projected.y],"screen_bounds":[screen_bounds.position.x,screen_bounds.position.y,screen_bounds.size.x,screen_bounds.size.y],"behind_camera":camera.is_position_behind(at),"ground_height":ground,"height_above_terrain":at.y-ground})
	var before := tree.root.get_texture().get_image()
	before.save_png(destination.path_join("birds-normal.png"))
	birds.visible=false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var hidden := tree.root.get_texture().get_image()
	hidden.save_png(destination.path_join("birds-hidden-only.png"))
	birds.visible=was_visible
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var restored := tree.root.get_texture().get_image()
	restored.save_png(destination.path_join("birds-restored.png"))
	for row in rows:
		var bounds: Array=row.screen_bounds
		var rectangle := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).grow(3)
		row["changed_pixels_when_hidden"]=_changed(before,hidden,rectangle)
		row["changed_pixels_after_restore"]=_changed(before,restored,rectangle)
	var result := {"id":"birds_visibility_diagnostic","path":str(birds.get_path()),"instances":rows,"mesh_triangles":vertices.size()/3,"original_visibility":was_visible,"camera_world":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"camera_size":camera.size,"camera_projection":camera.projection,"only_geometry_visibility_changed":"DistantThermalGliders","paused_for_comparison":true,"restored_visibility":birds.visible==was_visible,"scope":"A/B/A source identification only. Zero changed pixels may mean the birds are offscreen or terrain-occluded; not proof that prior wedges had another source. No frame-time, driving or lighting-stability claim."}
	tree.paused=was_paused
	FileAccess.open(destination.path_join("birds-diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	return result

static func _changed(a: Image,b: Image,region: Rect2) -> int:
	var changed := 0
	for y in range(maxi(0,floori(region.position.y)),mini(a.get_height(),ceili(region.end.y))):
		for x in range(maxi(0,floori(region.position.x)),mini(a.get_width(),ceili(region.end.x))):
			var first := a.get_pixel(x,y)
			var second := b.get_pixel(x,y)
			if maxf(absf(first.r-second.r),maxf(absf(first.g-second.g),absf(first.b-second.b)))>.03: changed+=1
	return changed

func _finish(code: int) -> void:
	_release()
	if not output.is_empty():
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scenarios":reports,"scope":"Diagnostic fixed placement and frozen A/B/A bird visibility; not gameplay, lighting or performance approval"},"\t"))
	print("DESERT_BIRDS_DIAGNOSTIC_DONE ",output," code=",code)
	quit(code)
