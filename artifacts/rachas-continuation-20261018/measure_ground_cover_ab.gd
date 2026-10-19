extends "res://artifacts/rachas-implementation-20261018/measure_design.gd"
## Diagnostic only. Four 30 s board windows retain all geometry and actors.
## Every production material/range reference is restored before teardown.
const COVER := preload("res://world/desert/DesertGroundCover.gd")
var saved_cover: Array[Dictionary] = []
var fixed_camera: Camera3D
var camera_was_processing := false
var camera_transform := Transform3D.IDENTITY
var failed := false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir(_output_prefix())
	var at: Vector3=LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary=FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",data)
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.session.state.region_id!="desert": quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode=true
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,720)
	var session=world.session
	var race=session.desert.drag
	var car=world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not is_instance_valid(car): quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not world.driving.interact(): quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not world.driving.occupied or car.input_locked: quit(1); return
	session.weather.set_process(false)
	session.weather.time_of_day=.9
	session.weather._update()
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await hold(12)
	race.open_meet.enabled=false
	await hold(2)
	if not race.perform("board"): quit(1); return
	await hold(3)
	fixed_camera=root.get_camera_3d()
	if fixed_camera==null: quit(1); return
	camera_was_processing=fixed_camera.is_processing()
	fixed_camera.set_process(false)
	camera_transform=fixed_camera.global_transform
	_save_cover()
	if failed:
		_restore(); world.free(); quit(1); return
	if saved_cover.is_empty():
		push_error("DRAG_COVER_AB found no affected batches")
		_restore(); world.free(); quit(1); return
	results.environment={"scene":"Main.tscn","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"hour":.9,"native":true,"no_save":true,"user_args":OS.get_cmdline_user_args(),"affected_batches":saved_cover.size(),"scope":_scope_note()}
	print("DRAG_COVER_AB_READY ",output)
	for variant in _variant_names():
		_apply_variant(variant)
		await hold(5)
		var before:=_snapshot()
		begin_sample()
		await hold(30)
		end_sample(variant)
		results[variant]["before"]=before
		results[variant]["after"]=_snapshot()
		# Readback and file IO are deliberately outside the timed windows.
		await capture(variant)
		if not fixed_camera.global_transform.is_equal_approx(camera_transform):
			failed=true
			push_error("DRAG_COVER_AB camera changed")
	_restore()
	var restored:=true
	for item in saved_cover:
		var node: MultiMeshInstance3D=item.node
		if not is_instance_valid(node) or node.material_override!=item.material or not is_equal_approx(node.visibility_range_end,item.range): restored=false
	results.restoration={"exact_references_and_ranges":restored,"camera_processing":fixed_camera.is_processing()==camera_was_processing}
	var file:=FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("DRAG_COVER_AB_DONE ",output," restored=",restored)
	world.free()
	quit(1 if failed or not restored else 0)

func _output_prefix() -> String: return "drag-cover-ab"
func _scope_note() -> String: return "same board, fixed production camera; no geometry/population changes; diagnostic old range is not a proposed product change"
func _variant_names() -> Array[String]: return ["current","opaque_expanded","opaque_original","current_restored"]

func _save_cover() -> void:
	for node: MultiMeshInstance3D in world.find_children("DesertGroundCover_*","MultiMeshInstance3D",true,false):
		var material:=node.material_override as StandardMaterial3D
		if material==null or material.distance_fade_mode==BaseMaterial3D.DISTANCE_FADE_DISABLED: continue
		var kind:=COVER.KINDS.find(str(node.name).split("_")[-1])
		if kind<0: continue
		var mesh:=node.multimesh.mesh
		var vertices:=0
		for surface in mesh.get_surface_count(): vertices+=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
		saved_cover.append({"node":node,"material":node.material_override,"range":node.visibility_range_end,"old_range":COVER.VISIBILITY[kind],"vertices":vertices*node.multimesh.instance_count})

func _apply_variant(variant: String) -> void:
	for item in saved_cover:
		var node: MultiMeshInstance3D=item.node
		node.material_override=item.material if variant.begins_with("current") else COVER.material()
		node.visibility_range_end=item.old_range if variant=="opaque_original" else item.range

func _restore() -> void:
	for item in saved_cover:
		var node: MultiMeshInstance3D=item.node
		if not is_instance_valid(node): continue
		node.material_override=item.material
		node.visibility_range_end=item.range
	if is_instance_valid(fixed_camera): fixed_camera.set_process(camera_was_processing)

func _snapshot() -> Dictionary:
	var distance_batches:=0
	var distance_vertices:=0
	var frustum_batches:=0
	var frustum_vertices:=0
	var planes:=fixed_camera.get_frustum()
	for item in saved_cover:
		var node: MultiMeshInstance3D=item.node
		var bounds: AABB=node.global_transform*node.get_aabb()
		var center:=bounds.get_center()
		if center.distance_to(fixed_camera.global_position)>node.visibility_range_end: continue
		distance_batches+=1
		distance_vertices+=item.vertices
		var outside:=false
		for plane: Plane in planes:
			var projected_radius:=plane.normal.abs().dot(bounds.size*.5)
			if plane.distance_to(center)>projected_radius:
				outside=true
				break
		if not outside:
			frustum_batches+=1
			frustum_vertices+=item.vertices
	return {"camera":str(fixed_camera.global_transform),"projection":fixed_camera.projection,"size":fixed_camera.size,"fov":fixed_camera.fov,"far":fixed_camera.far,"distance_candidate_batches":distance_batches,"distance_candidate_vertices":distance_vertices,"aabb_frustum_candidate_batches":frustum_batches,"aabb_frustum_candidate_vertices":frustum_vertices,"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"light_budget":preload("res://gameplay/lights/LightBudget.gd").counts()}
