extends SceneTree
const ACTOR = preload("res://scripts/Actor.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
var checks := 0
var failures := 0
var bench_count := 0
var long_cast_anomalies := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func run() -> void:
	for path in ["world/mountain_detail/OriginalVillageArchitecture.gd", "world/regions/OriginalCemetery3D.gd", "world/urban_detail/HarborTerminalModel3D.gd", "gameplay/urban_v1/TruckersVillageVisuals.gd", "gameplay/urban_v1/PortDepotBuilding.gd", "ski_lodge", "lumberjack_shelter"]:
		if "--only-village" in OS.get_cmdline_user_args() and not path.contains("OriginalVillage"): continue
		var scene: Node3D = load("res://"+path).new() if path.ends_with(".gd") else PLACES.create_place(path)
		root.add_child(scene)
		await physics_frame
		await physics_frame
		var benches: Array = []
		for mesh in scene.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("bench_envelope"): benches.append(mesh)
		check(not benches.is_empty(), path+" discovers upgraded benches")
		for bench in benches:
			bench_count += 1
			var box: AABB = bench.mesh.get_aabb()
			for player in [true, false]:
				var actor = ACTOR.new()
				actor.is_player = player
				actor.input_locked = true
				root.add_child(actor)
				actor.collision_layer = 0
				actor.set_physics_process(false)
				await physics_frame
				var approaches := 0
				for local_direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					var axis: Vector3 = bench.global_basis * local_direction
					var direction := axis.normalized()
					var extent: float = (box.size.x if local_direction.x != 0 else box.size.z)*.5*axis.length()
					var start: Vector3 = bench.to_global(Vector3.ZERO)+direction*(extent+.5)
					var query := PhysicsRayQueryParameters3D.create(start+Vector3.UP, start-Vector3.UP*2, 1)
					var ground: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
					if not ground.is_empty(): start.y = ground.position.y
					start.y += .08
					actor.teleport(start)
					if actor.move_and_collide(Vector3.UP*.001,true) != null: continue
					var hit = actor.move_and_collide(-direction*(extent*2+1.0),true)
					check(hit != null and hit.get_travel().length() < .40, path+" swept "+("player" if player else "npc")+" stopped by bench "+str(bench.position)+str(direction))
					approaches += 1
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var corner: Vector3 = bench.to_global(Vector3(sx*box.size.x*.5, 0, sz*box.size.z*.5))
						var outward: Vector3 = (bench.global_basis*Vector3(sx,0,sz)).normalized()
						var start: Vector3 = corner+outward*.5
						var query := PhysicsRayQueryParameters3D.create(start+Vector3.UP,start-Vector3.UP*2,1)
						var ground: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
						if not ground.is_empty(): start.y = ground.position.y
						start.y += .08
						actor.teleport(start)
						if actor.move_and_collide(Vector3.UP*.001,true) != null: continue
						var hit = actor.move_and_collide(-outward*3.0,true)
						var gameplay_blocked := false
						if hit == null:
							long_cast_anomalies += 1
							for step in 60:
								var moved = actor.move_and_collide(-outward*.05)
								if moved != null:
									print("BENCH_REAL_STEPS_BLOCK distance=",actor.global_position.distance_to(start)," collider=",moved.get_collider().get_path())
									# The start is exactly .5m outside the authored corner.
									# Actual movement must stop before reaching that corner.
									gameplay_blocked = actor.global_position.distance_to(start) < .5 and bench.is_ancestor_of(moved.get_collider())
									break
						check(gameplay_blocked if hit == null else hit.get_travel().length() < .40,path+" diagonal corner blocks "+("player" if player else "npc")+" bench="+str(bench.position)+" start="+str(start))
				check(approaches >= 1, path+" has accessible bench edge")
				actor.queue_free()
				await physics_frame
		scene.queue_free()
		await physics_frame
	print("BENCH_NATIVE benches=%d checks=%d failures=%d long_cast_anomalies=%d" % [bench_count,checks,failures,long_cast_anomalies])
	quit(0 if failures == 0 else 1)
