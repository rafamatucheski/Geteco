extends SceneTree
## Collision regression for the 96 m asphalt/ground seams of the drag strip.
## Uses the production road builder and an actual Vehicle body. Driving inputs
## are held constant here to isolate support; Main tests cover the powertrain.
const SUPPORT := preload("res://world/desert/DragTrackSupport.gd")
const ROAD := preload("res://world/desert/DesertRoadGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CELL := 96.0
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var region: Node3D
var road := ROAD.new()
var chunks: Dictionary = {}
var support: StaticBody3D
var car: CharacterBody3D

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("TRACK_SUPPORT timeout"); quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("TRACK_SUPPORT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _build_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Desert_%d_%d" % [key.x,key.y]
	region.add_child(chunk)
	var rect := Rect2(Vector2(key)*CELL,Vector2.ONE*CELL)
	var corners := PackedVector3Array()
	for point: Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		corners.append(Vector3(point.x,LAYOUT.surface_height(point),point.y))
	var ground := G.quad(chunk,"DesertGround",corners,G.material(Color("b9a079")),true)
	ground.get_child(0).set_meta("vehicle_surface","dirt")
	road.build_chunk(chunk,rect)
	chunks[key] = chunk
	return chunk

func _ray(at: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x,1.5,at.y),Vector3(at.x,-.4,at.y),1,exclude)
	return scene.get_world_3d().direct_space_state.intersect_ray(query)

func _all_hits(at: Vector2) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var excluded: Array[RID] = []
	for attempt in 8:
		var hit := _ray(at,excluded)
		if hit.is_empty(): break
		hits.append(hit)
		excluded.append(hit.rid)
	return hits

func _single_track_support(at: Vector2) -> bool:
	var hits := _all_hits(at)
	return hits.size()==1 and hits[0].collider==support and absf(hits[0].position.y)<.001 and hits[0].normal.y>.99 and str(support.get_meta("vehicle_surface",""))=="hard"

func _run() -> void:
	check(BRIDGE.enabled(),"production UnifiedBridge collision datum is enabled")
	if not BRIDGE.enabled():
		print("TRACK_SUPPORT requires the production datum; legacy raised asphalt is not covered")
		quit(2)
		return
	scene = Node3D.new()
	root.add_child(scene)
	region = Node3D.new()
	scene.add_child(region)
	road.configure(LAYOUT.roads())
	for x in range(-10,2): _build_chunk(Vector2i(x,-14))
	_build_chunk(Vector2i(-5,-15)) # Return road, outside the racing strip.
	var visuals: Array[Dictionary] = []
	for chunk: Node3D in chunks.values():
		for node in chunk.get_children():
			if node is MeshInstance3D:
				visuals.append({"node":node,"mesh":node.mesh,"faces":node.mesh.get_faces(),"material":node.material_override})
	await physics_frame
	await physics_frame
	check(_all_hits(Vector2(-850,-1318)).size()>=2,"fixture exposes the original overlapping road and ground support")
	var outside_samples: Array[Vector2] = [Vector2(-936.05,-1320),Vector2(90.05,-1320),Vector2(-500,-1325.05),Vector2(-500,-1314.95),Vector2(-450,-1350)]
	var outside_before: Array[Array] = []
	for point in outside_samples: outside_before.append(_all_hits(point))
	support = SUPPORT.install(region)
	for chunk: Node3D in chunks.values(): SUPPORT.replace_chunk_collision(region,chunk)
	await physics_frame
	await physics_frame
	var coverage_ok := true
	var bad_points: Array[Vector2] = []
	# Sample interiors, every former seam, the diagonal of the large support,
	# and 5 cm inside each cut boundary. Expectations come from the authored road.
	var xs: Array[float] = [-935.95,-925.0,-500.0,89.95]
	for x in range(-864,1,96):
		xs.append(float(x)-.05)
		xs.append(float(x))
		xs.append(float(x)+.05)
	for z in [-1324.95,-1322.0,-1320.0,-1318.0,-1315.05]:
		for x in xs:
			var point := Vector2(x,z)
			if not _single_track_support(point):
				coverage_ok = false
				if bad_points.size()<8: bad_points.append(point)
	check(coverage_ok,"exact cut leaves one hard support throughout the straight, including former seams: %s" % str(bad_points))
	var outside_ok := true
	for index in outside_samples.size():
		var before: Array = outside_before[index]
		var after := _all_hits(outside_samples[index])
		if before.is_empty() or before.size()!=after.size(): outside_ok = false
		for old_hit: Dictionary in before:
			var retained := false
			for new_hit: Dictionary in after:
				if new_hit.collider==old_hit.collider and new_hit.position.distance_to(old_hit.position)<.001: retained = true
			if not retained: outside_ok = false
		for new_hit: Dictionary in after:
			if new_hit.collider==support: outside_ok = false
	check(outside_ok,"all four cut edges and the return road retain their original physical support")
	var visuals_ok := true
	for row in visuals:
		var mesh: MeshInstance3D = row.node
		if mesh.mesh!=row.mesh or mesh.mesh.get_faces()!=row.faces or mesh.material_override!=row.material: visuals_ok = false
	check(visuals_ok,"replacing support preserves every rendered mesh, vertex and material")
	# A physical barrier remains outside the floor filter and still blocks a car.
	var obstacle_chunk: Node3D = chunks[Vector2i(-10,-14)]
	G.box(obstacle_chunk,"SpectatorBarrier",Vector3(-900,.5,-1330),Vector3(7.6,1,.4),Color.GRAY,true)
	SUPPORT.replace_chunk_collision(region,obstacle_chunk)
	car = VEHICLE.new()
	car.set("archetype","jessica_jetta_gli")
	car.position = Vector3(-925,.08,-1318)
	car.rotation.y = -PI*.5
	scene.add_child(car)
	# The race also takes ownership of motion; preserve the real hull, masks,
	# safe margin and Godot collision response instead of moving its transform.
	car.set_physics_process(false)
	car.set_process(false)
	await physics_frame
	await physics_frame
	for z in [-1318.0,-1322.0]:
		for sign_x in [1.0,-1.0]:
			var start := Vector3(-930 if sign_x>0 else 84,.08,z)
			var finish := Vector3(84 if sign_x>0 else -930,.08,z)
			var result := await _traverse(start,finish,60.0)
			check(result.ok,"physical vehicle covers the full straight z=%s direction=%s: %s" % [str(z),str(sign_x),JSON.stringify(result)])
	# Real low-speed crossings at the finite support perimeter catch lips/holes
	# that a vertical ray alone cannot reveal. No teleport occurs inside a pass.
	var edges: Array[Array] = [
		[Vector3(-943,.08,-1318),Vector3(-929,.08,-1318)],
		[Vector3(83,.08,-1318),Vector3(97,.08,-1318)],
		[Vector3(-510,.08,-1331),Vector3(-510,.08,-1319)],
		[Vector3(-510,.08,-1321),Vector3(-510,.08,-1309)],
	]
	for index in edges.size():
		var result := await _traverse(edges[index][0],edges[index][1],8.0)
		check(result.ok,"physical vehicle crosses finite support edge %d without a lip or hole: %s" % [index,JSON.stringify(result)])
	car.position = Vector3(-900,.02,-1333)
	car.rotation.y = 0
	car.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	check(car.test_move(car.global_transform,Vector3(0,0,3)),"spectator barrier still blocks the real vehicle after floor replacement")
	var key := Vector2i(-5,-14)
	var old_chunk: Node3D = chunks[key]
	var support_id := support.get_instance_id()
	old_chunk.queue_free()
	chunks.erase(key)
	await physics_frame
	await physics_frame
	check(_single_track_support(Vector2(-450,-1318)),"unloading one chunk does not remove the regional track support")
	var rebuilt := _build_chunk(key)
	SUPPORT.replace_chunk_collision(region,rebuilt)
	await physics_frame
	await physics_frame
	var outside_rebuilt := _ray(Vector2(-450,-1314.95))
	check(support.get_instance_id()==support_id and _single_track_support(Vector2(-450,-1318)) and not outside_rebuilt.is_empty() and outside_rebuilt.collider!=support,"rebuilt chunk restores its shoulder without duplicating the track support")
	# Reapply the clip as can happen during a rebuild; it must not consume the
	# surviving shoulder or introduce a second floor on the track.
	SUPPORT.replace_chunk_collision(region,rebuilt)
	await physics_frame
	await physics_frame
	check(_single_track_support(Vector2(-450,-1322)) and not _ray(Vector2(-450,-1325.05)).is_empty(),"reapplying the cut preserves support inside and outside")
	print("TRACK_SUPPORT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _traverse(start: Vector3, finish: Vector3, speed: float) -> Dictionary:
	var direction := (finish-start).normalized()
	direction.y = 0
	car.position = start
	car.rotation.y = atan2(-direction.x,-direction.z)
	car.velocity = Vector3.ZERO
	var delta := 1.0/float(Engine.physics_ticks_per_second)
	for settle in 24:
		await physics_frame
		car.velocity = Vector3(0,0.0 if car.is_on_floor() else car.velocity.y-18.0*delta,0)
		car.move_and_slide()
	var settled_position := car.global_position
	var settled_floor := car.is_on_floor()
	print("TRACK_SUPPORT_SETTLED ",JSON.stringify({"start":str(start),"position":str(settled_position),"on_floor":settled_floor,"vertical_velocity":car.velocity.y}))
	var span := start.distance_to(finish)
	var minimum_speed := INF
	var max_height := 0.0
	var maximum_state: Dictionary = {}
	var bad_contact := ""
	var travelled := 0.0
	var steps := ceili(span/(speed*delta))+2
	for step in steps:
		await physics_frame
		var before := car.global_position
		var floor_before := car.is_on_floor()
		var vertical_before := car.velocity.y
		# Production Vehicle uses floor snap and no downward impulse while
		# grounded; the regression must use that same motion contract.
		car.velocity = direction*speed+Vector3(0,0.0 if car.is_on_floor() else car.velocity.y-18.0*delta,0)
		car.move_and_slide()
		var actual_speed := (car.global_position-before).dot(direction)/delta
		minimum_speed = minf(minimum_speed,actual_speed)
		if absf(car.global_position.y)>max_height:
			max_height = absf(car.global_position.y)
			maximum_state = {"position":str(car.global_position),"before":str(before),"floor_before":floor_before,"floor_after":car.is_on_floor(),"vertical_before":vertical_before,"vertical_after":car.velocity.y,"step":step}
		for index in car.get_slide_collision_count():
			var collision := car.get_slide_collision(index)
			for contact in collision.get_collision_count():
				if absf(collision.get_normal(contact).dot(direction))>.2 and bad_contact.is_empty():
					bad_contact = "%s normal=%s at=%s" % [str(collision.get_collider(contact)),str(collision.get_normal(contact)),str(collision.get_position(contact))]
		travelled = (car.global_position-start).dot(direction)
		if travelled>=span or actual_speed<speed*.9 or max_height>.05: break
	return {"ok":travelled>=span and minimum_speed>=speed*.98 and max_height<.02 and bad_contact.is_empty(),"travelled":travelled,"minimum_speed":minimum_speed,"maximum_height":max_height,"maximum_state":maximum_state,"settled_position":str(settled_position),"settled_floor":settled_floor,"final_position":str(car.global_position),"contact":bad_contact}
