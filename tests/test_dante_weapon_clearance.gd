extends SceneTree

var failures: Array[String] = []
var player
var samples := 0
var output := "D:/geteco/artifacts/dante-run-weapons-0913"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	for id in WeaponCatalog.ORDER:
		if id in ["fists", "knuckles"]: continue
		if OS.get_cmdline_user_args().has("--diagnostic") and id not in ["axe", "shotgun", "ak47", "m4a1", "flamethrower"]: continue
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
		for mode in ["idle", "walk", "run", "aim_run", "fire_run", "reload_run"]:
			if mode == "reload_run" and int(WeaponCatalog.get_weapon(id).get("magazine_size", -1)) <= 0: continue
			var moving: bool = mode != "idle"
			var running: bool = mode in ["run", "aim_run", "fire_run", "reload_run"]
			for frame in 60:
				player._update_locomotion(1.0/60.0, moving, running)
				player.combat_pose.update(player, 1.0/60.0, mode == "aim_run", running, 0.0)
			if mode == "fire_run": player.combat_pose.on_attack(id)
			if mode == "reload_run":
				player.weapon_ammo[id] = {"clip": 0, "reserve": 100}
				player._reload_active_weapon()
			var hits := {}
			for frame in 32:
				player.walk_clock = frame * TAU / 32.0
				if mode == "reload_run": player._process(player._reload_duration / 32.0)
				player._update_locomotion(1.0/60.0, moving, running)
				player.combat_pose.update(player, 1.0/60.0, mode == "aim_run", running, player._gait_arm_swing())
				for part in points:
					if not part.node.is_visible_in_tree(): continue
					for v in part.vertices:
						var hit := _inside_body(part.node.to_global(v))
						if hit != "":
							if hits.is_empty() and OS.get_cmdline_user_args().has("--diagnostic"):
								print("FIRST ", id, " ", mode, " frame=", frame, " point=", player.torso_node.to_local(part.node.to_global(v)), " hand=", player.weapon_mount_node.global_position, " reload=", player.get_reload_progress())
							hits[str(part.node.name) + "/" + hit] = true
				samples += 1
			player._cancel_reload()
			if not hits.is_empty():
				failures.append(str(id) + " " + mode + " " + str(hits.keys()))
				print("CLIP ", failures[-1])
		if OS.get_cmdline_user_args().has("--capture"):
			await _capture(id)
	print("WEAPON_CLEARANCE poses=", samples, " failures=", failures.size())
	FileAccess.open(output + "/clearance.json", FileAccess.WRITE).store_string(JSON.stringify(failures, "\t"))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _inside_body(point: Vector3) -> String:
	var p: Vector3 = player.torso_node.to_local(point)
	if p.y > -0.18 and p.y < 0.22 and absf(p.x) < 0.155 and p.z > -0.098 and p.z < 0.072:
		return "torso"
	var h: Vector3 = player.head_node.to_local(point) - Vector3(0, 0.09, 0)
	if (h / Vector3(0.095, 0.15, 0.10)).length_squared() < 1.0: return "head"
	for leg in [player.left_upper_leg, player.right_upper_leg, player.left_lower_leg, player.right_lower_leg]:
		var q: Vector3 = leg.to_local(point)
		if q.y < -0.025 and q.y > -0.29 and Vector2(q.x, q.z).length() < 0.054: return "leg"
	return ""

func _capture(id: String) -> void:
	var viewport: SubViewport = player.viewport_3d
	viewport.size = Vector2i(320, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := viewport.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.85
	cam.position = Vector3(0, 1.15, 3)
	cam.look_at(Vector3(0, 0.75, 0))
	var atlas := Image.create(1280, 1080, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("28303a"))
	for row in 3:
		player.model_root.rotation.y = [-PI/2, PI*0.75, -0.5][row]
		for col in 4:
			player.walk_clock = col * TAU / 4 + 0.3
			for frame in 30:
				player._update_locomotion(1.0/60.0, true, true)
				player.combat_pose.update(player, 1.0/60.0, false, true, player._gait_arm_swing())
			await process_frame
			await RenderingServer.frame_post_draw
			atlas.blend_rect(viewport.get_texture().get_image(), Rect2i(0,0,320,360), Vector2i(col*320,row*360))
	atlas.save_png(output + "/" + id + ".png")
	player.model_root.rotation = Vector3.ZERO
