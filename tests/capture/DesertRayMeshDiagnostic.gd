extends RefCounted
## Offline-at-capture CPU mesh interrogation. Never use in a runtime/frame benchmark.
const DISTANCE := 180.0

static func capture_existing(main: Node3D,folder: String) -> Dictionary:
	var camera := main.get_viewport().get_camera_3d()
	if camera==null: return {"error":"Missing camera"}
	var nodes: Array[Node]=[main]
	var visuals: Array[Node3D]=[]
	while not nodes.is_empty():
		var node: Node=nodes.pop_back()
		for child in node.get_children(): nodes.append(child)
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			var spatial := node as GeometryInstance3D
			if spatial.is_visible_in_tree() and (spatial.layers&camera.cull_mask)!=0: visuals.append(spatial)
	var cache: Dictionary={}
	var rays: Array[Dictionary]=[]
	for pixel in [Vector2(200,580),Vector2(350,440),Vector2(130,428),Vector2(100,680),Vector2(270,520),Vector2(615,410),Vector2(815,401)]:
		var from := camera.project_ray_origin(pixel)
		var direction := camera.project_ray_normal(pixel).normalized()
		var to := from+direction*DISTANCE
		var query := PhysicsRayQueryParameters3D.create(from,to,7)
		var physical: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
		var physical_report: Dictionary={}
		if not physical.is_empty():
			var collider: Object=physical.collider
			physical_report={"path":str(collider.get_path()) if collider is Node else str(collider),"point":_v3(physical.position),"normal":_v3(physical.normal),"distance":from.distance_to(physical.position)}
		var candidates: Array[Dictionary]=[]
		for visual in visuals:
			if visual is MeshInstance3D:
				if visual.mesh!=null: _candidate(candidates,visual,visual.mesh,visual.global_transform,from,to,-1)
			else:
				var batch: MultiMesh=(visual as MultiMeshInstance3D).multimesh
				if batch==null or batch.mesh==null: continue
				var inverse := visual.global_transform.affine_inverse()
				if _entry(batch.get_aabb(),inverse*from,inverse*to)<0: continue
				var count := batch.instance_count if batch.visible_instance_count<0 else batch.visible_instance_count
				for i in count: _candidate(candidates,visual,batch.mesh,visual.global_transform*batch.get_instance_transform(i),from,to,i)
		candidates.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.entry)<float(b.entry))
		var hits: Array[Dictionary]=[]
		var checked := 0
		for candidate in candidates:
			var mesh: Mesh=candidate.mesh
			var key := mesh.get_instance_id()
			if not cache.has(key):
				var surfaces: Array[Dictionary]=[]
				for surface in mesh.get_surface_count():
					if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
					var arrays := mesh.surface_get_arrays(surface)
					if arrays.is_empty(): continue
					surfaces.append({"surface":surface,"vertices":arrays[Mesh.ARRAY_VERTEX],"indices":arrays[Mesh.ARRAY_INDEX]})
				cache[key]=surfaces
			var pose: Transform3D=candidate.pose
			var inverse := pose.affine_inverse()
			var local_from := inverse*from
			var local_to := inverse*to
			var nearest := INF
			var nearest_point := Vector3.ZERO
			var nearest_surface := -1
			var nearest_normal := Vector3.ZERO
			var nearest_triangle := PackedVector3Array()
			for surface in cache[key]:
				var vertices: PackedVector3Array=surface.vertices
				var indices: PackedInt32Array=surface.indices if surface.indices!=null else PackedInt32Array()
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for i in range(0,count-2,3):
					var a: Vector3=vertices[indices[i] if not indices.is_empty() else i]
					var b: Vector3=vertices[indices[i+1] if not indices.is_empty() else i+1]
					var c: Vector3=vertices[indices[i+2] if not indices.is_empty() else i+2]
					var hit: Variant=Geometry3D.segment_intersects_triangle(local_from,local_to,a,b,c)
					checked+=1
					if hit==null: continue
					var position: Vector3=pose*hit
					var distance := from.distance_to(position)
					if distance<nearest:
						nearest=distance
						nearest_point=position
						nearest_surface=int(surface.surface)
						nearest_normal=(pose.basis.inverse().transposed()*(c-a).cross(b-a)).normalized()
						nearest_triangle=PackedVector3Array([pose*a,pose*b,pose*c])
			if nearest_surface>=0:
				var node: GeometryInstance3D=candidate.node
				var material: Material=node.material_override
				if material==null and node is MeshInstance3D: material=node.get_surface_override_material(nearest_surface)
				if material==null: material=mesh.surface_get_material(nearest_surface)
				var triangle_world: Array=[]
				var triangle_screen: Array=[]
				for vertex in nearest_triangle:
					triangle_world.append(_v3(vertex))
					var screen := camera.unproject_position(vertex)
					triangle_screen.append([screen.x,screen.y])
				hits.append({"path":str(node.get_path()),"mesh_type":mesh.get_class(),"mesh_resource":mesh.resource_path,"instance":candidate.instance,"surface":nearest_surface,"point":_v3(nearest_point),"distance":nearest,"view_depth":-camera.global_basis.z.dot(nearest_point-camera.global_position),"clockwise_normal":_v3(nearest_normal),"normal_dot_ray":nearest_normal.dot(direction),"back_facing":nearest_normal.dot(direction)>0,"triangle_world":triangle_world,"triangle_projected":triangle_screen,"material_type":material.get_class() if material!=null else "none","shader":material.shader.resource_path if material is ShaderMaterial and material.shader!=null else "","cast_shadow":node.cast_shadow})
		hits.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance)<float(b.distance))
		var boxes: Array[Dictionary]=[]
		for candidate in candidates: boxes.append({"path":str(candidate.node.get_path()),"instance":candidate.instance,"aabb_entry_distance":float(candidate.entry)*DISTANCE})
		rays.append({"pixel":[pixel.x,pixel.y],"from":_v3(from),"direction":_v3(direction),"physics":physical_report,"aabb_candidates":boxes,"visual_hits_front_to_back":hits,"triangles_checked":checked})
	var report := {"id":"desert_visual_ray_mesh_diagnostic","camera":str(camera.get_path()),"visible_mesh_nodes":visuals.size(),"rays":rays,"scope":"CPU source triangles over180m, including MultiMesh transforms. Shader displacement, particle quads, skinning, alpha cutout and backface culling are not simulated; compare nearest hits against the real capture before identifying the visible source. Not FPS or collision approval."}
	FileAccess.open(folder.path_join("ray-mesh-diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

static func _candidate(out: Array[Dictionary],node: Node3D,mesh: Mesh,pose: Transform3D,from: Vector3,to: Vector3,instance: int) -> void:
	var inverse := pose.affine_inverse()
	var entry := _entry(mesh.get_aabb(),inverse*from,inverse*to)
	if entry>=0: out.append({"node":node,"mesh":mesh,"pose":pose,"entry":entry,"instance":instance})

static func _entry(box: AABB,from: Vector3,to: Vector3) -> float:
	var direction := to-from
	var low := 0.0
	var high := 1.0
	for axis in 3:
		if absf(direction[axis])<.000001:
			if from[axis]<box.position[axis] or from[axis]>box.end[axis]: return -1
		else:
			var a := (box.position[axis]-from[axis])/direction[axis]
			var b := (box.end[axis]-from[axis])/direction[axis]
			low=maxf(low,minf(a,b))
			high=minf(high,maxf(a,b))
			if low>high: return -1
	return low

static func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
