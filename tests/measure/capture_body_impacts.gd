extends "res://tests/measure/measure_body_impact_sound.gd"
## Separate visual/audio diagnostic. PNG capture, mesh reads and audio recording
## deliberately invalidate these frame metrics for performance comparison.
const SHOT_TIMES := [.1, .25, .5, .9, 1.5, 2.2]
const CAPTURE_CYCLES := 2
var capture_jobs: Array[Dictionary] = []
var capture_frames: Array[Dictionary] = []
var capture_seen_victims: Dictionary = {}
var capture_seen_attempts := 0
var capture_busy := false
var capture_errors := 0
var pending_images: Array[Dictionary] = []

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if started == 0 or not is_instance_valid(world): return result
	var now := Time.get_ticks_usec()
	if attempts != capture_seen_attempts:
		capture_seen_attempts = attempts
		# The existing fixture has already requested a 9 m/s dismount. Only the
		# now-driverless car gets 24 m/s for the real sweep into the staged NPC.
		var car = world.driving.car
		car.speed = 24.0
		car.horizontal_velocity = -car.global_basis.z*24.0
		if attempts <= CAPTURE_CYCLES and world.driving.is_body_transition_active():
			_queue_sequence("bailout", attempts, world.player, now)
	if attempts <= CAPTURE_CYCLES and is_instance_valid(victim) and victim.has_meta("street_flying"):
		var id := victim.get_instance_id()
		if not capture_seen_victims.has(id):
			capture_seen_victims[id] = true
			_queue_sequence("pedestrian", attempts, victim, now)
	if not capture_busy and not capture_jobs.is_empty() and now >= int(capture_jobs[0].due):
		var job: Dictionary = capture_jobs.pop_front()
		capture_busy = true
		_capture_one.call_deferred(job)
	return result

func _queue_sequence(kind: String, cycle: int, subject: Node3D, event_time: int) -> void:
	for delay in SHOT_TIMES:
		capture_jobs.append({"kind":kind,"cycle":cycle,"delay":delay,
			"event_time":event_time,"due":event_time+int(delay*1000000.0),"subject":weakref(subject)})
	capture_jobs.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.due) < int(b.due))

func _capture_one(job: Dictionary) -> void:
	var subject := (job.subject as WeakRef).get_ref() as Node3D
	if not is_instance_valid(subject):
		capture_errors += 1
		capture_busy = false
		return
	# Follow just this shot's subject so the fast NPC stays large enough to
	# inspect. The live city, cars, shadows and geometry remain rendered.
	var focus := subject.global_position+Vector3.UP*.7
	world.camera.look_at_from_position(focus+Vector3(5.5,5,7),focus)
	world.camera.size = 9.0
	await RenderingServer.frame_post_draw
	if not is_instance_valid(subject):
		capture_errors += 1
		capture_busy = false
		return
	var captured_at := Time.get_ticks_usec()
	var output_dir := evidence_dir if not evidence_dir.is_empty() else "res://evidence"
	var file_name := "%s-%s-%d-%04dms.png" % [label,job.kind,job.cycle,int(round(float(job.delay)*1000))]
	# Save after the sequence: PNG compression was delaying later pose samples.
	var shot := root.get_texture().get_image()
	var record := {"file":file_name,"kind":job.kind,"cycle":job.cycle,
		"requested_seconds":job.delay,"actual_seconds":float(captured_at-int(job.event_time))/1000000.0,
		"subject_position":_point(subject.global_position),"subject_visual":_visual_state(subject),
		"camera_position":_point(world.camera.global_position),"camera_size":world.camera.size,
		"png_error":OK,"player_locked":world.player.input_locked,"player_dead":world.player.dead,
		"npc":_npc_geometry(victim)}
	capture_frames.append(record)
	pending_images.append({"image":shot,"path":output_dir.path_join(file_name),"record":record})
	print("BODY_CAPTURE ",file_name," actual_s=",record.actual_seconds)
	capture_busy = false

func _point(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _visual_state(subject: Node3D) -> Dictionary:
	var visual: Node3D = subject.get("visual")
	if not is_instance_valid(visual): return {}
	return {"position":_point(visual.global_position),"rotation":_point(visual.global_rotation),
		"scale":_point(visual.global_basis.get_scale())}

func _body_model(node: Node) -> Node3D:
	if node is Node3D and "forearms" in node and "head_node" in node and "feet" in node: return node
	for child in node.get_children():
		var found := _body_model(child)
		if found != null: return found
	return null

func _npc_geometry(npc: CharacterBody3D) -> Dictionary:
	if not is_instance_valid(npc): return {"missing":true}
	var model := _body_model(npc)
	var record := {"position":_point(npc.global_position),"dead":npc.get("dead"),
		"flying":npc.has_meta("street_flying"),"down":npc.has_meta("street_down"),
		"health":npc.get("health"),"visual":_visual_state(npc),"parts":{}}
	if model == null:
		record["missing_rig"] = true
		return record
	# Read actual transformed vertices, not the actor root or rotated AABB.
	# Hands share a rigid forearm mesh; below local y=-.25 is authored hand
	# geometry in CivilianMeshKit.forearm_mesh (palm, fingers and thumb).
	var parts := {"head":model.head_node,"left_foot":model.feet[0],"right_foot":model.feet[1],
		"left_hand":model.forearms[0],"right_hand":model.forearms[1]}
	for part in parts:
		record.parts[part] = _mesh_minimum(parts[part],str(part).ends_with("hand"),npc)
	return record

func _mesh_minimum(node: MeshInstance3D, hand_only: bool, npc: CharacterBody3D) -> Dictionary:
	if not is_instance_valid(node) or node.mesh == null: return {"missing":true}
	var minimum := Vector3.INF
	var maximum_y := -INF
	var count := 0
	for surface in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for local in vertices:
			if hand_only and local.y > -.25: continue
			var point := node.global_transform*local
			if point.y < minimum.y: minimum = point
			maximum_y = maxf(maximum_y,point.y)
			count += 1
	if count == 0: return {"missing_vertices":true}
	var record := {"mesh":str(node.get_path()),"vertices":count,"minimum_world":_point(minimum),
		"maximum_y":maximum_y,"hand_local_y_max":-.25 if hand_only else null}
	# A downward scene query provides local road/terrain height for the lowest
	# actual vertex. Keep collider and normal so a wall/roof isn't called floor.
	var query := PhysicsRayQueryParameters3D.create(minimum+Vector3.UP*2.0,minimum-Vector3.UP*6.0,1,[npc.get_rid()])
	var hit := npc.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		record["surface_world"] = _point(hit.position)
		record["surface_normal"] = _point(hit.normal)
		record["surface_collider"] = str(hit.collider.get_path()) if hit.collider is Node else str(hit.collider)
		record["clearance_y"] = minimum.y-float(hit.position.y)
	return record

func finish() -> void:
	while capture_busy: await process_frame
	for pending in pending_images:
		var error: int = pending.image.save_png(pending.path)
		pending.record.png_error = error
		if error != OK: capture_errors += 1
	pending_images.clear()
	var counts := {"bailout":0,"pedestrian":0}
	for frame in capture_frames: counts[frame.kind] += 1
	var complete: bool = capture_errors == 0 and int(counts.bailout) >= SHOT_TIMES.size() and int(counts.pedestrian) >= SHOT_TIMES.size()
	var output_dir := evidence_dir if not evidence_dir.is_empty() else "res://evidence"
	var report := {"complete":complete,"errors":capture_errors,"counts":counts,"frames":capture_frames,
		"dismount_speed_mps":9.0,"vehicle_hit_speed_fixture_mps":24.0,
		"notes":"Separate Main-scene visual/audio diagnostic; not a performance measurement. Camera follows each shot subject. NPC minima use actual mesh vertices; hand subset uses forearm-mesh local y <= -0.25. Surface rays and photos must be inspected together; actor root height alone is not clipping validation."}
	var file := FileAccess.open(output_dir.path_join(label+"-sequence.json"),FileAccess.WRITE)
	if file == null:
		push_error("Could not save body capture sequence evidence")
	else:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	if not complete: push_error("Body capture sequence did not cover both full six-frame sequences")
	print("BODY_CAPTURE_SEQUENCE complete=",complete," counts=",counts," errors=",capture_errors)
	await super.finish()
