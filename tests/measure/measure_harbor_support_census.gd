extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Read-only geometry diagnostic before warm-up; production motion is unchanged.
## Subsequent FPS is a separate warmed run, not the cost of these ray queries.
const MAX_SUPPORT_HITS := 32
const SUPPORT_ABOVE := 0.6
const SUPPORT_BELOW := 1.5
const COPLANAR_TOLERANCE := 0.03
var _support_shapes: Dictionary = {}

func settle_load() -> bool:
	if not await super.settle_load(): return false
	await physics_frame
	_capture_support_census()
	return true

func _capture_support_census() -> void:
	var began := Time.get_ticks_usec()
	var bodies: Array[CharacterBody3D] = []
	var seen: Dictionary = {}
	var candidates: Array = [world.player]
	candidates.append_array(world.people)
	candidates.append_array(get_nodes_in_group("police_witness"))
	candidates.append_array(get_nodes_in_group("drivable"))
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is CharacterBody3D: continue
		if not candidate.is_inside_tree() or candidate.is_queued_for_deletion(): continue
		var id: int = candidate.get_instance_id()
		if seen.has(id): continue
		seen[id] = true
		bodies.append(candidate)
	var rows: Array[Dictionary] = []
	var coplanar_origins := 0
	var truncated_origins := 0
	for body in bodies:
		var row := _sample_support(body)
		rows.append(row)
		if not row.coplanar_pairs.is_empty(): coplanar_origins += 1
		if row.truncated: truncated_origins += 1
	var report := {
		"label":label, "scenario":scenario, "engine_usec":began,
		"capture_usec":Time.get_ticks_usec()-began, "origins":rows,
		"shape_resources":_support_shapes.values(),
		"coplanar_origins":coplanar_origins, "truncated_origins":truncated_origins,
		"ray_above_m":SUPPORT_ABOVE, "ray_below_m":SUPPORT_BELOW,
		"coplanar_tolerance_m":COPLANAR_TOLERANCE, "max_hits_per_origin":MAX_SUPPORT_HITS,
		"scope":"Read-only central vertical rays at current production actor/vehicle origins after settling, before FPS warm-up. Each hit excludes the whole collider RID for the next ray, so this inventories distinct bodies, not multiple shapes or triangles inside one body. Shape ownership and concave face counts are inspected only in this census and cached per resource. Horizontal near-coplanar hits are candidates, not proof of duplicate contact or solver cost. No body movement, process changes, source variants, or measured-loop queries. Rays miss footprint surfaces away from the center; bodies without hits may be supported outside this ray. Subsequent FPS does not measure census cost."
	}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-support-census.json"),FileAccess.WRITE)
	if file == null:
		push_error("HARBOR_SUPPORT_CENSUS_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	print("HARBOR_SUPPORT_CENSUS ",JSON.stringify({"origins":rows.size(),"coplanar_origins":coplanar_origins,"truncated_origins":truncated_origins,"capture_usec":report.capture_usec}))

func _sample_support(body: CharacterBody3D) -> Dictionary:
	var origin := body.global_position
	var query := PhysicsRayQueryParameters3D.create(origin+Vector3.UP*SUPPORT_ABOVE,origin-Vector3.UP*SUPPORT_BELOW,body.collision_mask)
	var excluded: Array[RID] = [body.get_rid()]
	query.exclude = excluded
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space := body.get_world_3d().direct_space_state
	var hits: Array[Dictionary] = []
	for _index in MAX_SUPPORT_HITS:
		var hit := space.intersect_ray(query)
		if hit.is_empty(): break
		var collider := hit.collider as CollisionObject3D
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var row := {"position":str(point),"height":point.y,"height_from_origin":point.y-origin.y,
			"normal":str(normal),"horizontal":normal.dot(Vector3.UP)>.99,
			"shape_index":int(hit.shape),"collider_id":str(hit.collider_id)}
		if collider != null:
			row.merge({"path":str(collider.get_path()),"class":collider.get_class(),
				"script":collider.get_script().resource_path if collider.get_script()!=null else "",
				"collision_layer":collider.collision_layer,"collision_mask":collider.collision_mask,
				"shape":_describe_support_shape(collider,int(hit.shape))})
		hits.append(row)
		excluded.append(hit.rid)
		query.exclude = excluded
	var truncated := hits.size() == MAX_SUPPORT_HITS and not space.intersect_ray(query).is_empty()
	var pairs: Array[Dictionary] = []
	for i in hits.size():
		if not hits[i].horizontal: continue
		for j in range(i+1,hits.size()):
			if hits[j].horizontal and absf(float(hits[i].height)-float(hits[j].height))<=COPLANAR_TOLERANCE:
				pairs.append({"first":i,"second":j,"height_difference":absf(float(hits[i].height)-float(hits[j].height))})
	return {"path":str(body.get_path()),"origin":str(origin),"collision_mask":body.collision_mask,
		"on_floor":body.is_on_floor(),"floor_normal":str(body.get_floor_normal()),
		"velocity":str(body.velocity),"physics_processing":body.is_physics_processing(),
		"hits":hits,"coplanar_pairs":pairs,"truncated":truncated}

func _describe_support_shape(body: CollisionObject3D, shape_index: int) -> Dictionary:
	var owner_id := body.shape_find_owner(shape_index)
	var owner := body.shape_owner_get_owner(owner_id)
	var row := {"owner_id":owner_id,"owner_path":str(owner.get_path()) if owner is Node else "",
		"owner_transform":str(body.shape_owner_get_transform(owner_id)),
		"disabled":body.is_shape_owner_disabled(owner_id)}
	for local_index in body.shape_owner_get_shape_count(owner_id):
		if body.shape_owner_get_shape_index(owner_id,local_index)!=shape_index: continue
		var shape := body.shape_owner_get_shape(owner_id,local_index)
		var key := str(shape.get_instance_id())
		row["resource_id"] = key
		if not _support_shapes.has(key):
			var resource_row := {"id":key,"class":shape.get_class(),"resource_path":shape.resource_path}
			if shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = shape.get_faces()
				resource_row["face_vertices"] = faces.size()
				resource_row["triangles"] = faces.size()/3
			elif shape is BoxShape3D: resource_row["size"] = str(shape.size)
			elif shape is ConvexPolygonShape3D: resource_row["points"] = shape.points.size()
			_support_shapes[key] = resource_row
		break
	return row
