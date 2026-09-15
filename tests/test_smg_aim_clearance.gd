extends SceneTree

var failures: Array[String] = []
var pose
var player
var samples := 0
var output := "D:/geteco/artifacts/smg-aim-fix"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	pose = player.combat_pose
	for id in ["smg"]:
		if id in ["fists", "knuckles"]: continue
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		var points: Array[Dictionary] = []
		for node in player.current_gun_mesh.find_children("*", "MeshInstance3D", true, false):
			if node.mesh == null or "Muzzle" in node.name or "Trail" in node.name: continue
			var vertices := PackedVector3Array()
			for surface in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				vertices.append_array(vs)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				for i in range(0, indices.size(), 3):
					vertices.append((vs[indices[i]] + vs[indices[i+1]] + vs[indices[i+2]]) / 3.0)
			points.append({"node": node, "vertices": vertices})
		for mode in ["aim", "aim_walk", "aim_run", "fire_run"]:
			if mode == "reload_run" and int(WeaponCatalog.get_weapon(id).get("magazine_size", -1)) <= 0: continue
			var moving: bool = mode != "aim"
			var running: bool = mode in ["run", "aim_run", "fire_run", "reload_run"]
			for frame in 60:
				player._update_locomotion(1.0/60.0, moving, running)
				pose.update(player, 1.0/60.0, true, running, 0.0)
			if mode == "fire_run": pose.on_attack(id)
			if mode == "reload_run":
				player.weapon_ammo[id] = {"clip": 0, "reserve": 100}
				player._reload_active_weapon()
			var hits := {}
			for frame in 32:
				player.walk_clock = frame * TAU / 32.0
				if mode == "reload_run": player._process(player._reload_duration / 32.0)
				player._update_locomotion(1.0/60.0, moving, running)
				pose.update(player, 1.0/60.0, true, running, player._gait_arm_swing())
				for part in points:
					if not part.node.is_visible_in_tree(): continue
					for v in part.vertices:
						var hit := _inside_body(part.node.to_global(v))
						if hit == "arm" and part.node.position.is_equal_approx(Vector3(0, -0.05, 0.03)):
							hit = "" # The handle is enclosed by the firing hand at the wrist.
						if hit != "":
							if hits.is_empty():
								print("FIRST ", id, " ", mode, " frame=", frame, " mesh=", part.node.position, " point=", player.torso_node.to_local(part.node.to_global(v)), " hand=", player.weapon_mount_node.global_position, " reload=", player.get_reload_progress())
							hits[str(part.node.name) + "/" + hit] = true
				samples += 1
			player._cancel_reload()
			if not hits.is_empty():
				failures.append(str(id) + " " + mode + " " + str(hits.keys()))
				print("CLIP ", failures[-1])
	print("WEAPON_CLEARANCE poses=", samples, " failures=", failures.size())
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output + "/clearance.json", FileAccess.WRITE).store_string(JSON.stringify(failures, "\t"))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _inside_body(point: Vector3) -> String:
	var p: Vector3 = player.torso_node.to_local(point)
	if p.y > -0.18 and p.y < 0.22 and absf(p.x) < 0.155 and p.z > -0.098 and p.z < 0.072:
		return "torso"
	for arm in [player.left_upper_arm, player.right_upper_arm, player.left_lower_arm, player.right_lower_arm]:
		var q: Vector3 = arm.to_local(point)
		if q.y < -0.03 and q.y > -0.16 and Vector2(q.x, q.z).length() < 0.04: return "arm"
	var h: Vector3 = player.head_node.to_local(point) - Vector3(0, 0.09, 0)
	if (h / Vector3(0.095, 0.15, 0.10)).length_squared() < 1.0: return "head"
	for leg in [player.left_upper_leg, player.right_upper_leg, player.left_lower_leg, player.right_lower_leg]:
		var q: Vector3 = leg.to_local(point)
		if q.y < -0.025 and q.y > -0.29 and Vector2(q.x, q.z).length() < 0.054: return "leg"
	return ""



