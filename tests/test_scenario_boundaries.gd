extends SceneTree
## Real streamed surface collision. This is not a session or FPS benchmark.
const NATIVE := preload("res://world/regions/NativeRegion.gd")
const DESERT := preload("res://world/desert/DesertRegion.gd")
const BOUNDARY := preload("res://world/regions/ScenarioBoundary3D.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("BOUNDARY ", "PASS " if ok else "FAIL ", label)

func run() -> void:
	var mountain := NATIVE.new()
	mountain.region_id = "mountain"
	mountain.initial_prewarm_only = true
	root.add_child(mountain)
	mountain.set_process(false)
	var desert := DESERT.new()
	desert.initial_prewarm_only = true
	root.add_child(desert)
	desert.set_process(false)
	# Samples cover the snow/sand side, all sand perimeter directions and seams.
	for z in [-400.0, -576.0, -600.0, -960.0, -1440.0, -1900.0]:
		var point := Vector3(464, 0, z)
		mountain.prepare_collision_at(point)
		desert.prepare_collision_at(Vector3(432, 0, z))
	for point in [Vector3(-1494,0,-900), Vector3(-500,0,-1944), Vector3(342.5,0,-1944), Vector3(200,2.4,-379), Vector3(342.5,2.4,-379), Vector3(600,0,-135)]:
		desert.prepare_collision_at(point)
	mountain.prepare_collision_at(Vector3(600,0,-135))
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	for z in [-400.0, -576.0, -600.0, -960.0, -1440.0, -1900.0]:
		var height: float = maxf(mountain.terrain.surface_height_at(Vector2(460,z)),mountain.terrain.surface_height_at(Vector2(474,z))) + 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(474,height,z),Vector3(444,height,z),1))
		check(not hit.is_empty() and hit.collider.is_in_group(BOUNDARY.GROUP), "snow side sealed by boundary at z=%s" % z)
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(430,.8,z),Vector3(446,.8,z),1))
		check(not hit.is_empty(), "sand east sealed at z=%s" % z)
	for pair in [[Vector3(-1490,.8,-900),Vector3(-1505,.8,-900)], [Vector3(-500,.8,-1940),Vector3(-500,.8,-1960)], [Vector3(200,3.2,-382),Vector3(200,3.2,-365)], [Vector3(342.5,3,-1945),Vector3(342.5,3,-1960)]]:
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0],pair[1],1)).is_empty(), "sand perimeter sealed %s" % pair[0])
	var bridge := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(342.5,3.2,-382),Vector3(342.5,3.2,-365),1))
	check(bridge.is_empty(), "authored city/desert bridge stays open")
	# Capsule sweeps cross an entire cell edge in one call, including the jump
	# height above the old terminal guardrail. Real collision must stop them.
	for pair in [[Vector3(370,0,-600),Vector3(85,0,0)], [Vector3(370,0,-576),Vector3(85,0,0)], [Vector3(342.5,3,-1945),Vector3(0,0,-20)]]:
		if pair[0].x == 370:
			pair[0].y = desert._ground_height(Vector2(pair[0].x,pair[0].z))+1.1
			desert.prepare_collision_at(pair[0])
		var actor := CharacterBody3D.new()
		actor.collision_layer = 2
		actor.collision_mask = 1
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.7
		collision.shape = capsule
		actor.add_child(collision)
		root.add_child(actor)
		actor.global_position = pair[0]
		await physics_frame
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = actor.global_transform
		query.collision_mask = 1
		check(space.intersect_shape(query).is_empty(), "capsule starts outside existing solids")
		var contact := actor.move_and_collide(pair[1])
		# Existing solid outcrops may stop the capsule before the continuous ridge.
		# The directed rays above independently verify the ridge fills the gaps.
		print("BOUNDARY_CONTACT ", contact.get_collider().get_parent().name if contact != null else "none", " ", actor.global_position)
		check(contact != null and actor.global_position.x < 440 and actor.global_position.z > -1950, "capsule stays inside supported sand perimeter %s" % pair[0])
		check(actor.global_position.distance_to(pair[0]) < pair[1].length() and actor.global_position.y >= pair[0].y-.1, "no teleport, fall or traversal through boundary")
		actor.free()
	for body in get_nodes_in_group(BOUNDARY.GROUP):
		var visible_mesh: MeshInstance3D = body.get_parent()
		var shape: ConcavePolygonShape3D = body.get_child(0).shape
		# A colisão sai das arrays exatas da CPU; a leitura da GPU vem quantizada (~0,05 mm).
		var collision_faces := shape.get_faces()
		var visible_faces := visible_mesh.mesh.get_faces()
		var matches := collision_faces.size() == visible_faces.size()
		for k in collision_faces.size() if matches else 0:
			if collision_faces[k].distance_to(visible_faces[k]) > .001:
				matches = false
				break
		check(matches, "collision matches visible ridge")
	if "--capture" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 75
		camera.position = Vector3(480,50,-550)
		camera.look_at(Vector3(450,3,-600))
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55,-30,0)
		root.add_child(light)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var folder := "res://evidence/scenario-boundaries-%d" % OS.get_process_id()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder.path_join("snow-sand.png")))
		print("BOUNDARY_CAPTURE ", ProjectSettings.globalize_path(folder))
	print("BOUNDARY checks=%d failures=%d" % [checks,failures])
	mountain.free()
	desert.free()
	quit(0 if failures == 0 else 1)
