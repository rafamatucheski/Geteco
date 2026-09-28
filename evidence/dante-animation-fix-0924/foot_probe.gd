extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var actor = load("res://scripts/Actor.gd").new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	for mode in ["idle", "walk", "run"]:
		var low := INF
		var high := -INF
		for frame in 30:
			if mode == "idle": actor._apply_pose(actor._idle_pose)
			else: actor._pose_cycle("Walking" if mode == "walk" else "Running", frame / 30.0, actor.WALK_START if mode == "walk" else 0.0)
			var mesh: MeshInstance3D = actor._combat_skin
			var skin: Skin = mesh.skin
			var matrices: Array[Transform3D] = []
			for index in skin.get_bind_count():
				var bone := skin.get_bind_bone(index)
				if bone < 0: bone = actor.skeleton.find_bone(skin.get_bind_name(index))
				matrices.append(actor.skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(index))
			var sole := INF
			for surface in mesh.mesh.get_surface_count():
				var a: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
				var count := weights.size() / vertices.size()
				for vertex in vertices.size():
					var point := Vector3.ZERO
					for influence in count:
						var index := vertex * count + influence
						point += (matrices[bones[index]] * vertices[vertex]) * weights[index]
					sole = minf(sole, actor.skeleton.to_global(point).y)
			low = minf(low, sole); high = maxf(high, sole)
		print("SOLE ",mode," min=",low," max=",high)
	quit()
