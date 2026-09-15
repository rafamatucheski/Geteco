extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func silhouette(rig: Node3D, project: Callable) -> Rect2:
	var result := Rect2()
	var first := true
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible: continue
		for corner in 8:
			var pixel: Vector2 = project.call(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
			if first:
				result = Rect2(pixel, Vector2.ZERO)
				first = false
			else: result = result.expand(pixel)
	return result

func run() -> void:
	root.get_node("SaveManager").clear_pending_save()
	seed(914)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for angle in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var station = load("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
		station.position = Vector2(600, 400)
		station.rotation = angle
		world.add_child(station)
		for identity in range(-1, 5):
			var actor: CharacterBody2D
			if identity == -1:
				actor = load("res://Player.gd").new()
				var camera := Camera2D.new()
				camera.name = "Camera"
				actor.add_child(camera)
				var collision := CollisionShape2D.new()
				collision.name = "Collision"
				collision.shape = CapsuleShape2D.new()
				collision.shape.radius = 4
				collision.shape.height = 10
				actor.add_child(collision)
			else:
				actor = load("res://world/harbor/urban_transit/UrbanPassenger.gd").new()
				actor.body_type_override = identity
				actor.archetype_override = 1
				actor.appearance_seed = identity
			actor.position = Vector2(-1000, -1000)
			world.add_child(actor)
			actor.set_physics_process(false)
			for i in 3: await process_frame
			var personal: SubViewport = actor.get("viewport_3d") if actor.get("viewport_3d") != null else actor.get("viewport")
			var camera := personal.get_camera_3d()
			var display: Sprite2D = actor.sprite_3d_display
			var original_scale := display.scale
			var original_position := display.position
			var original_size := personal.size
			var rig: Node3D = actor.model_root
			var original_parent := rig.get_parent()
			for direction in [0.0, PI * 0.5, PI, -PI * 0.5]:
				rig.rotation.y = direction
				var native := silhouette(rig, func(v): return camera.unproject_position(v) * original_scale)
				actor.global_position = station.ramp_approach()
				station._actor_entered(actor)
				var presentation = station.presentations[actor]
				var projected := silhouette(rig, func(v): return presentation.project_world(v))
				var ratio := projected.size / native.size
				check(absf(ratio.x - 1.0) < 0.10 and absf(ratio.y - 1.0) < 0.10, "silhouette identity=%d angle=%.2f facing=%.2f ratio=%s" % [identity, angle, direction, ratio])
				check(display.scale == original_scale and display.position == original_position and personal.size == original_size, "street calibration preserved")
				check(not display.visible and rig.get_parent() == presentation.anchor, "original rig shares station depth")
				check(presentation.collider.scale == presentation.old_collision_scale, "station never shrinks physical body")
				var expected_foot: Vector2 = actor.global_position + presentation.street_foot_offset
				check(presentation.project_world(presentation.anchor.global_position).distance_to(expected_foot) < 0.1, "foot does not jump on admission")
				for turned in [0.0, PI * 0.5, PI, -PI * 0.5]:
					rig.rotation.y = turned
					var turned_native := silhouette(rig, func(v): return camera.unproject_position(presentation.anchor.to_local(v)) * original_scale)
					var turned_stage := silhouette(rig, func(v): return presentation.project_world(v))
					var turned_ratio := turned_stage.size / turned_native.size
					check(absf(turned_ratio.x-1.0)<0.10 and absf(turned_ratio.y-1.0)<0.10, "turn retains proportions identity=%d ratio=%s" % [identity,turned_ratio])
				station._actor_exited(actor)
				check(rig.get_parent() == original_parent and display.visible and display.scale == original_scale, "exit restores original presentation")
				check(not actor.has_meta("interior_actor_presentation"), "exit clears adapter")
			# Use real swept bodies on the public ramp, platform and closed gate.
			actor.global_position = station.ramp_approach()
			for i in 2: await physics_frame
			for local_point in [Vector2(185,8), Vector2(160,8), Vector2(125,8)]:
				var destination: Vector2 = station.to_global(local_point)
				var contact := actor.move_and_collide(destination - actor.global_position)
				check(contact == null and actor.global_position.distance_to(destination) < 0.1, "player/NPC can use ramp and platform identity=%d angle=%.2f" % [identity,angle])
			var gate_hit := actor.move_and_collide(station.to_global(Vector2(125,65)) - actor.global_position)
			check(gate_hit != null, "closed boarding gate blocks actual body")
			actor.global_position = station.to_global(Vector2(125,8))
			for local_point in [Vector2(160,8), Vector2(185,8), Vector2(207,8), Vector2(265,8)]:
				var destination: Vector2 = station.to_global(local_point)
				check(actor.move_and_collide(destination - actor.global_position) == null, "exit ramp remains traversable")
			for i in 3: await physics_frame
			check(not actor.has_meta("interior_actor_presentation"), "real area exit releases actor")
			actor.free()
		station.free()
	print("URBAN_STATION_ACTOR_CONTINUITY failures=", failures)
	quit(0 if failures.is_empty() else 1)
