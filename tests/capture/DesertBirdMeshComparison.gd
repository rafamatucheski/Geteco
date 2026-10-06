extends RefCounted
## Finite image comparison, never a performance sample. Production is untouched.
const CANDIDATE := preload("res://tests/capture/DesertGliderMeshCandidate.gd")

static func capture_existing(tree: SceneTree, main: Node3D, folder: String) -> Dictionary:
	var result: Dictionary={"ok":false,"diagnostic_pose_not_natural_flight":false,"not_a_performance_benchmark":true}
	var birds := main.find_child("DistantThermalGliders",true,false) as MultiMeshInstance3D
	var camera := tree.root.get_camera_3d()
	if not is_instance_valid(birds) or birds.multimesh==null or not is_instance_valid(camera):
		result.reason="Missing resident gliders or active camera"
		return result
	if DisplayServer.get_name()=="headless":
		result.reason="Rendered comparison requires a display"
		return result
	for name in ["old.png","candidate.png","restored.png","comparison.json"]:
		if FileAccess.file_exists(folder.path_join(name)):
			result.reason="Refusing to overwrite existing comparison evidence"
			return result
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:
		result.reason="Cannot create comparison directory"
		return result
	var owner := birds.get_parent()
	var was_physics := owner.is_physics_processing()
	var was_paused := tree.paused
	var batch := birds.multimesh
	var original: Mesh=batch.mesh
	var poses: Array[Transform3D]=[]
	for i in batch.instance_count: poses.append(batch.get_instance_transform(i))
	var camera_transform := camera.global_transform
	var camera_size := camera.size
	var camera_projection := camera.projection
	var camera_processing := camera.is_processing()
	var camera_physics := camera.is_physics_processing()
	var visible_instances := batch.visible_instance_count
	owner.set_physics_process(false)
	# CameraRig deliberately runs PROCESS_MODE_ALWAYS, even on a paused tree.
	camera.set_process(false)
	camera.set_physics_process(false)
	tree.paused=true
	# Let any prior interpolation finish at the frozen physical transforms.
	for i in batch.instance_count: batch.reset_instance_physics_interpolation(i)
	var initial_visibility := _visible_instances(birds,camera)
	result.original_visibility=initial_visibility
	result.instance_count=batch.instance_count
	result.original_triangles=_triangles(original)
	result.camera_transform=str(camera_transform)
	result.camera_size=camera_size
	result.original_transforms=[]
	for pose in poses: result.original_transforms.append(str(pose))
	if initial_visibility.unobstructed_indices.is_empty() and batch.instance_count>0 and birds.is_visible_in_tree():
		var anchor: Node3D=main.player
		if main.driving.occupied and is_instance_valid(main.driving.car): anchor=main.driving.car
		var original_world := birds.global_transform*poses[0].origin
		var projected_anchor := camera.unproject_position(anchor.global_position)
		var screen := camera.get_viewport().get_visible_rect()
		for offset: Vector2 in [Vector2(.12,-.15),Vector2(-.12,-.22),Vector2(.18,-.30)]:
			var pixel: Vector2=projected_anchor+Vector2(offset)*screen.size
			pixel=pixel.clamp(screen.position+Vector2.ONE*16,screen.end-Vector2.ONE*16)
			var ray_origin := camera.project_ray_origin(pixel)
			var direction := camera.project_ray_normal(pixel)
			if absf(direction.y)<.00001: continue
			var along := (original_world.y-ray_origin.y)/direction.y
			if along<camera.near: continue
			var point := ray_origin+direction*along
			var pose := poses[0]
			pose.origin=birds.to_local(point)
			batch.set_instance_transform(0,pose)
			batch.reset_instance_physics_interpolation(0)
			var visibility := _visible_instances(birds,camera)
			if not visibility.unobstructed_indices.is_empty():
				result.diagnostic_pose_not_natural_flight=true
				result.diagnostic_original_position=str(original_world)
				result.diagnostic_position=str(point)
				result.diagnostic_altitude_preserved=is_equal_approx(point.y,original_world.y)
				break
	var comparison_visibility := _visible_instances(birds,camera)
	result.comparison_visibility=comparison_visibility
	var candidate := CANDIDATE.build()
	candidate.surface_set_material(0,original.surface_get_material(0))
	result.candidate_triangles=_triangles(candidate)
	result.material_preserved=candidate.surface_get_material(0)==original.surface_get_material(0)
	result.surface_count_preserved=candidate.get_surface_count()==original.get_surface_count()
	var captured := false
	if not comparison_visibility.unobstructed_indices.is_empty():
		var old_error: int=await _capture(tree,folder.path_join("old.png"))
		batch.mesh=candidate
		var candidate_error: int=await _capture(tree,folder.path_join("candidate.png"))
		batch.mesh=original
		var restored_error: int=await _capture(tree,folder.path_join("restored.png"))
		captured=old_error==OK and candidate_error==OK and restored_error==OK
		result.image_write_errors=[old_error,candidate_error,restored_error]
	else:
		result.reason="No unoccluded glider center could be placed in frame at its original altitude"
	# restored.png restores only the mesh at the common comparison pose. Now
	# restore any diagnostic instance placement and every changed runtime state.
	batch.mesh=original
	for i in poses.size():
		batch.set_instance_transform(i,poses[i])
		batch.reset_instance_physics_interpolation(i)
	owner.set_physics_process(was_physics)
	camera.set_process(camera_processing)
	camera.set_physics_process(camera_physics)
	tree.paused=was_paused
	var restored := batch.mesh==original and batch.instance_count==poses.size() and batch.visible_instance_count==visible_instances
	for i in poses.size(): restored=restored and batch.get_instance_transform(i).is_equal_approx(poses[i])
	result.runtime_restored=restored and owner.is_physics_processing()==was_physics and tree.paused==was_paused
	result.camera_unchanged=camera.global_transform.is_equal_approx(camera_transform) and camera.size==camera_size and camera.projection==camera_projection and camera.is_processing()==camera_processing and camera.is_physics_processing()==camera_physics
	result.ok=captured and bool(result.runtime_restored) and bool(result.camera_unchanged)
	result.visibility_method="Center inside camera frustum plus unobstructed layer1 physics ray; images still require human silhouette/occlusion review"
	result.restored_image_scope="Original mesh at the same comparison pose; all original flight transforms restored immediately afterward"
	var file := FileAccess.open(folder.path_join("comparison.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t"))
	else: result.ok=false; result.reason="Cannot write comparison report"
	return result

static func _capture(tree: SceneTree, path: String) -> int:
	for i in 2: await tree.process_frame
	await RenderingServer.frame_post_draw
	return tree.root.get_texture().get_image().save_png(path)

static func _visible_instances(birds: MultiMeshInstance3D, camera: Camera3D) -> Dictionary:
	var in_frame: Array[int]=[]
	var unobstructed: Array[int]=[]
	if not birds.is_visible_in_tree(): return {"frustum_indices":in_frame,"unobstructed_indices":unobstructed,"count_in_frame":0}
	var count := birds.multimesh.instance_count
	if birds.multimesh.visible_instance_count>=0: count=mini(count,birds.multimesh.visible_instance_count)
	for i in count:
		var point := birds.global_transform*birds.multimesh.get_instance_transform(i).origin
		if not camera.is_position_in_frustum(point): continue
		in_frame.append(i)
		var pixel := camera.unproject_position(point)
		var origin := camera.project_ray_origin(pixel)
		var query := PhysicsRayQueryParameters3D.create(origin,point,1)
		var hit := birds.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): unobstructed.append(i)
	return {"frustum_indices":in_frame,"unobstructed_indices":unobstructed,"count_in_frame":in_frame.size()}

static func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		count+=int((indices.size() if not indices.is_empty() else vertices.size())/3)
	return count
