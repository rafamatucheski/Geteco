extends RefCounted
## Visual A/B/A only: original physics, sun, camera and materials are preserved.
const CANDIDATE_PATH := "D:/geteco/artifacts/desert-20261006/DesertTerrainMesh-refined-candidate.gd"

static func capture_existing(tree: SceneTree,main: Node3D,folder: String) -> Dictionary:
	var terrain: Node=main.find_child("DesertCanyonTerrain",true,false)
	var camera: Camera3D=main.get_viewport().get_camera_3d()
	if terrain==null or camera==null: return {"error":"Missing terrain/camera"}
	var candidate := GDScript.new()
	candidate.source_code=FileAccess.get_file_as_string(CANDIDATE_PATH)
	var compile_error := candidate.reload()
	if compile_error!=OK: return {"error":"Candidate compile error %d"%compile_error}
	var originals: Dictionary={}
	var replacements: Dictionary={}
	var materials: Dictionary={}
	var baseline_vertices := 0
	for child: Node in terrain.get_children():
		if not child is MeshInstance3D: continue
		var mesh_node := child as MeshInstance3D
		var parts := str(mesh_node.name).split("_")
		if parts.size()!=3: return {"error":"Unexpected terrain mesh name: "+str(mesh_node.name)}
		originals[mesh_node]=mesh_node.mesh
		materials[mesh_node]=mesh_node.material_override
		baseline_vertices+=mesh_node.mesh.surface_get_array_len(0)
	if originals.is_empty(): return {"error":"No terrain meshes"}
	var old_pose := camera.global_transform
	var old_size := camera.size
	var old_processing := camera.is_processing()
	var old_physics := camera.is_physics_processing()
	var was_paused := tree.paused
	var camera_focus: Vector3=main.camera.focus
	var states: Array[Dictionary]=[]
	var geometry_original := _geometry_hash(originals)
	var collision_original := _collision_signature(main)
	tree.paused=true
	camera.set_process(false)
	camera.set_physics_process(false)
	states.append(await _photo(tree,camera,folder,"mesh-refinement-original"))
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var build_start := Time.get_ticks_usec()
	for value: Variant in originals.keys():
		var mesh_node := value as MeshInstance3D
		var parts := str(mesh_node.name).split("_")
		var key := Vector2i(int(parts[1]),int(parts[2]))
		var replacement: ArrayMesh=candidate.call("mesh_for",key)
		replacements[mesh_node]=replacement
	var build_ms := float(Time.get_ticks_usec()-build_start)/1000.0
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for value: Variant in originals.keys():
		var mesh_node := value as MeshInstance3D
		mesh_node.mesh=replacements[mesh_node]
	states.append(await _photo(tree,camera,folder,"mesh-refinement-local-1m"))
	var collision_candidate := _collision_signature(main)
	var geometry_candidate := _geometry_hash(replacements)
	for value: Variant in originals.keys():
		var mesh_node := value as MeshInstance3D
		mesh_node.mesh=originals[mesh_node]
	states.append(await _photo(tree,camera,folder,"mesh-refinement-restored"))
	var collision_restored := _collision_signature(main)
	var restored := camera.global_transform.is_equal_approx(old_pose) and is_equal_approx(camera.size,old_size)
	for value: Variant in originals.keys():
		var mesh_node := value as MeshInstance3D
		restored=restored and mesh_node.mesh==originals[mesh_node] and mesh_node.material_override==materials[mesh_node]
	var stats: Dictionary=candidate.call("diagnostics")
	camera.set_process(old_processing)
	camera.set_physics_process(old_physics)
	tree.paused=was_paused
	var report := {"id":"local_terrain_refinement_visual_ABA","candidate_path":CANDIDATE_PATH,"candidate_source_sha256":candidate.source_code.sha256_text(),"baseline_triangles":baseline_vertices/3,"baseline_vertex_normal_payload_bytes":baseline_vertices*24,"candidate":stats,"candidate_build_ms_paused":build_ms,"static_memory_before_bytes":memory_before,"static_memory_after_bytes":memory_after,"static_memory_delta_bytes":memory_after-memory_before,"memory_delta_scope":"Godot MEMORY_STATIC process delta during paused candidate preparation; includes candidate caches/mesh allocations, excludes GPU and is not a full standalone runtime footprint.","mesh_geometry_original_sha256":geometry_original,"mesh_geometry_candidate_sha256":geometry_candidate,"mesh_geometry_restored_sha256":_geometry_hash(originals),"collision_before":collision_original,"collision_during":collision_candidate,"collision_after":collision_restored,"collision_unchanged":collision_original==collision_candidate and collision_original==collision_restored,"camera_focus":[camera_focus.x,camera_focus.y,camera_focus.z],"captures":states,"restored":restored,"scope":"Visual mesh replacement only at identical frozen final CameraRig pose. Original materials, sun, shadows, collider faces and physics height queries unchanged. Candidate supports matching collision/height API, but this experiment does not validate driving, physical integration, temporal stability or FPS."}
	FileAccess.open(folder.path_join("terrain-mesh-refinement.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

static func _geometry_hash(meshes: Dictionary) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for value: Variant in meshes.keys():
		var node := value as MeshInstance3D
		var mesh: Mesh=meshes[node]
		digest.update(str(node.get_path()).to_utf8_buffer())
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			digest.update(vertices.to_byte_array())
	return digest.finish().hex_encode()

static func _collision_signature(main: Node) -> Dictionary:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var count := 0
	var vertices := 0
	for value: Node in main.find_children("*","CollisionShape3D",true,false):
		var shape_node := value as CollisionShape3D
		if str(shape_node.get_parent().name)!="CanyonGroundCollider": continue
		var shape := shape_node.shape as ConcavePolygonShape3D
		if shape==null: continue
		var faces := shape.get_faces()
		digest.update(str(shape_node.get_path()).to_utf8_buffer())
		digest.update(str(shape.get_instance_id()).to_utf8_buffer())
		digest.update(str(shape_node.global_transform).to_utf8_buffer())
		digest.update(faces.to_byte_array())
		count+=1
		vertices+=faces.size()
	return {"shapes":count,"vertices":vertices,"sha256":digest.finish().hex_encode()}

static func _photo(tree: SceneTree,camera: Camera3D,folder: String,id: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join(id+".png"))
	return {"id":id,"position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"rotation_degrees":[camera.global_rotation_degrees.x,camera.global_rotation_degrees.y,camera.global_rotation_degrees.z],"projection":camera.projection,"size":camera.size,"near":camera.near,"far":camera.far}
