extends SceneTree
var failures: Array[String] = []
var world: Node2D
var seq: Node
var max_step := 0.0
var contacts := 0
var max_gap := 0.0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ")+text)
	if not ok: failures.append(text)

func obstacle(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = at
	var mesh := Polygon2D.new()
	mesh.polygon = PackedVector2Array([-size*.5,Vector2(size.x,-size.y)*.5,size*.5,Vector2(-size.x,size.y)*.5])
	mesh.color = Color("637486")
	body.add_child(mesh)
	var shape := CollisionPolygon2D.new()
	shape.polygon = mesh.polygon
	body.add_child(shape)
	world.add_child(body)
	return body

func run() -> void:
	create_timer(90).timeout.connect(func(): print("FORMATION_TIMEOUT"); quit(2))
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("WantedManager").set_process(false)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	seq = preload("res://world/shared/emergency/MedicalRescueSequence.gd").new()
	world.add_child(seq)
	seq.set_physics_process(false)
	seq.ambulance = Node2D.new()
	world.add_child(seq.ambulance)
	seq.patient = preload("res://AnimatedPedestrian3D.gd").new()
	world.add_child(seq.patient)
	seq.patient.set_physics_process(false)
	seq.patient.position = Vector2(-1000,-1000)
	seq.stretcher = preload("res://world/shared/emergency/MedicalStretcher.gd").new()
	world.add_child(seq.stretcher)
	for i in 2:
		var medic := preload("res://Paramedic.tscn").instantiate()
		world.add_child(medic)
		medic.set_physics_process(false)
		medic.position = Vector2(25 if i==0 else -25,0)
		seq.crew.append(medic)
		medic.add_collision_exception_with(seq.stretcher)
		seq.stretcher.add_collision_exception_with(medic)
	seq.formation.configure(seq.stretcher,seq.crew)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE*2
	world.add_child(camera)
	camera.position = Vector2(90,0)
	var post := preload("res://geodata/roads/traffic/FixedTrafficSignal.gd").new()
	post.position = Vector2(25,22)
	world.add_child(post)
	await physics_frame
	await physics_frame
	var original_floor: PackedVector2Array = seq.stretcher.floor_polygon(0).duplicate()
	for query in 8: seq.formation.clear_motion(Vector3.ZERO,Vector3(-1,0,0))
	check(seq.stretcher.floor_polygon(0)==original_floor,"Repeated swept queries preserve the cot's physical footprint")
	if not failures.is_empty(): quit(1); return
	check(not seq.formation.clear_motion(Vector3.ZERO,Vector3(0,0,PI*.5)),"Rotating the leading medic into the pole is rejected even though the cot centre clears")
	check(seq.formation.clear_motion(Vector3.ZERO,Vector3(-30,0,0)),"Backing the complete team away from the pole is allowed")
	post.position = Vector2(19,12)
	await physics_frame
	await physics_frame
	check(seq.formation.clear_motion(Vector3.ZERO,Vector3(0,-20,0)),"A medic can leave a clear rounded-capsule corner near a pole")
	post.position = Vector2(80,0)
	await physics_frame
	await physics_frame
	check(not seq.formation.clear_motion(Vector3.ZERO,Vector3(160,0,0)),"Large displacement cannot tunnel through a pole")
	check(await travel(Vector2(160,0),PI*.5),"Team detours around the physical post and finishes the required turn")
	check(max_step <= 2.0,"No formation member jumps during turns or translations")
	check(max_gap < .4,"Both medics remain at their own handles throughout motion")
	check(contacts == 0,"Cot and both actual bodies stay outside all solids throughout the detour")
	# Change the next corridor after a path exists. Replanning must use live solids.
	seq.formation.reset()
	check(await travel(Vector2(260,0),0,true),"A corridor blocked during movement triggers a continuous alternative path")
	check(contacts == 0,"Dynamic detour never crosses the blocker")
	var person := obstacle(Vector2(325,0),Vector2(12,20))
	person.collision_layer = 4
	await physics_frame
	await physics_frame
	var from: Vector3 = seq.formation.pose()
	check(not seq.formation.clear_motion(from,Vector3(360,0,0)),"Planning sees the same pedestrian layer that physically stops the medics")
	check(await travel(Vector2(390,0),0),"Formation goes around a person instead of repeatedly proposing an impossible straight step")
	check(contacts == 0,"The pedestrian detour preserves every member's collision contract")
	post.queue_free()
	seq.ambulance = null
	seq.queue_free()
	await process_frame
	print("FORMATION_RESULT failures=",failures," max_step=",max_step," gap=",max_gap," contacts=",contacts)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func travel(goal: Vector2, heading: float, close_gate := false) -> bool:
	seq.phase = "test_navigation"
	seq._progress_pose = Vector3.INF
	seq._no_progress = 0
	for frame in 1500:
		await physics_frame
		if close_gate and frame == 12:
			obstacle(Vector2(210,0),Vector2(12,110))
			await physics_frame
		var actors: Array = seq.crew+[seq.stretcher]
		var before: Array[Vector2] = []
		for actor in actors: before.append(actor.global_position)
		var arrived: bool = seq._move_stretcher(goal,1.0/60,heading)
		if seq.phase != "test_navigation": return false
		for i in actors.size():
			max_step = maxf(max_step,before[i].distance_to(actors[i].global_position))
			var query := PhysicsShapeQueryParameters2D.new()
			var col: CollisionShape2D = actors[i].collision_shape if i<2 else actors[i].footprint
			query.shape = col.shape
			query.transform = col.global_transform
			query.collision_mask = actors[i].collision_mask
			query.exclude = [actors[i].get_rid()]
			for exception in actors[i].get_collision_exceptions():
				if is_instance_valid(exception): query.exclude.append(exception.get_rid())
			if not world.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): contacts += 1
		for i in 2: max_gap = maxf(max_gap,seq.crew[i].global_position.distance_to(seq.formation.handles(seq.formation.pose(),i)))
		if arrived: return true
		if frame%300==0: print("FORMATION_PROGRESS ",seq.formation.pose()," expanded=",seq.formation.expansions," searching=",seq.formation.searching)
	return false
