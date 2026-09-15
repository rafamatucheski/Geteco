extends SceneTree

var OUT := "D:/geteco/artifacts/meshy-dante-0914"
var weapons := ["pistol", "ak47"]
const MELEE := ["knife", "bat", "axe", "knuckles", "grenade"]
var _torso_indices: Array[int] = []
var _sleeve_indices: Array[int] = []
var _motion_filter := PackedStringArray()
var failures: Array[String] = []
var max_contact_error := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)

func run() -> void:
	if "--arsenal" in OS.get_cmdline_user_args():
		OUT = "D:/geteco/artifacts/arsenal-quality-0914"
		weapons = ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife", "bat", "axe", "knuckles"]
	DirAccess.make_dir_recursive_absolute(OUT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("weapons="): _motion_filter = arg.trim_prefix("weapons=").split(",")
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://characters/Player.gd").new()
	player.use_meshy_dante = true
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	check(is_instance_valid(player.meshy_rig), "Meshy model loads")
	if not is_instance_valid(player.meshy_rig):
		quit(1)
		return
	player.viewport_3d.size = Vector2i(512, 512)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	cam.position = Vector3(0, 1.1, -3)
	cam.look_at(Vector3(0, 0.7, 0))
	var atlas := Image.create(2048, 512 * weapons.size(), false, Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	var index := 0
	for weapon in weapons:
		player.weapon_inventory[weapon] = true
		player.weapon_ammo[weapon] = {"clip": 10, "reserve": 30}
		player.equip_weapon(weapon)
		for state in ["carry", "aim", "run", "reload"]:
			player._cancel_reload()
			if state == "reload" and weapon not in MELEE:
				player._reload_weapon = weapon
				player._reload_duration = 2.0
				player._reload_elapsed = 0.9
			for frame in 90:
				if weapon in MELEE and state == "reload" and frame % 45 == 0: player.combat_pose.on_attack(weapon)
				var moving: bool = state == "run"
				player.velocity = Vector2(0, -90) if moving else Vector2.ZERO
				# Sample a complete clip cycle without faking CharacterBody travel.
				if moving: player.walk_clock = fposmod(player.walk_clock + TAU / 40.0, TAU)
				player._update_locomotion(1.0 / 60.0, moving, moving)
				player.meshy_rig.prepare_pose(1.0 / 60.0, moving, moving)
				player.combat_pose.update(player, 1.0 / 60.0, state == "aim", moving, player._gait_arm_swing())
				player.meshy_rig.update_pose(1.0 / 60.0, moving, moving)
				if frame > 45:
					for side in ["Right", "Left"]:
						if state != "aim" and weapon not in MELEE and weapon != "rpg":
							var skel: Skeleton3D = player.meshy_rig.skeleton
							var shoulder: Vector3 = skel.get_bone_global_pose(skel.find_bone(side + "Arm")).origin
							var elbow: Vector3 = skel.get_bone_global_pose(skel.find_bone(side + "ForeArm")).origin
							check(elbow.y < shoulder.y - 0.025, weapon + " " + state + " elbow stays below shoulder")
						var arm: Node3D = player.right_lower_arm if side == "Right" else player.left_lower_arm
						var error: float = player.meshy_rig.palm_position(side).distance_to(arm.get_node("Palm").global_position)
						max_contact_error = maxf(error, max_contact_error)
						check(error < 0.005, weapon + " " + state + " " + side + " palm reaches target")
						var bone: int = player.meshy_rig.skeleton.find_bone(side + "Hand")
						var roll := 0.358 if side == "Right" else -0.392
						var thumb_axis := Vector3(sin(roll), 0, cos(roll))
						var hand_world: Basis = player.meshy_rig.skeleton.global_basis * player.meshy_rig.skeleton.get_bone_global_pose(bone).basis
						var palm: Node3D = arm.get_node("Palm")
						if not player.meshy_rig._is_gripping(side):
							var wrist: Basis = player.meshy_rig.skeleton.get_bone_pose(bone).basis
							check(wrist.is_equal_approx(player.meshy_rig.skeleton.get_bone_rest(bone).basis), weapon + " reload keeps free wrist neutral")
						else:
							check((hand_world * thumb_axis).normalized().dot(palm.global_basis.y.normalized()) > 0.99, weapon + " thumb faces up relative to grip")
					for bone in player.meshy_rig.skeleton.get_bone_count():
						check(player.meshy_rig.skeleton.get_bone_global_pose(bone).is_finite(), "Bone poses finite")
			player.model_root.rotation.y = -0.45
			if "--bone-debug" in OS.get_cmdline_user_args() and weapon in ["bat","rpg"]:
				for side in ["Left","Right"]:
					var points := []
					for suffix in ["Arm","ForeArm","Hand"]:
						var skel: Skeleton3D = player.meshy_rig.skeleton
						points.append(player.model_root.to_local(skel.to_global(skel.get_bone_global_pose(skel.find_bone(side+suffix)).origin)))
					print("ARM_DEBUG ",weapon," ",state," ",side," ",points)
			if DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 512, 512), Vector2i(index % 4, index / 4) * 512)
				if "--review-angles" in OS.get_cmdline_user_args() and state == "aim":
					var views := Image.create(1536,512,false,Image.FORMAT_RGBA8)
					var angles := [-0.45,-PI/2,-2.7]
					for a in angles.size():
						player.model_root.rotation.y = angles[a]
						await process_frame
						await RenderingServer.frame_post_draw
						views.blit_rect(player.viewport_3d.get_texture().get_image(),Rect2i(0,0,512,512),Vector2i(a*512,0))
					views.save_png(OUT+"/angles-"+weapon+".png")
					player.model_root.rotation.y = -0.45
			index += 1
		player._cancel_reload()
		player.combat_pose.on_attack(weapon)
		if weapon not in MELEE: check(player.combat_pose.recoil > 0, weapon + " recoil is driven by combat")
	if "--capture-motion" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await capture_motion(player)
	if DisplayServer.get_name() != "headless": await capture_hands(player)
	# Desde 14/09 todos os trajes vestem o modelo importado (MeshyDanteAppearance).
	player.apply_outfit("dante_ski")
	check(is_instance_valid(player.meshy_rig) and bool(player.meshy_rig.material.get_shader_parameter("recolor")), "Other outfits dress the Meshy rig")
	player.apply_outfit("dante_classic")
	check(is_instance_valid(player.meshy_rig), "Classic outfit restores Meshy")
	await process_frame
	check(player.model_root.find_children("MeshyDanteRig", "", false, false).size() == 1, "Rebuild leaves one Meshy rig")
	DirAccess.make_dir_recursive_absolute(OUT)
	if DisplayServer.get_name() != "headless":
		atlas.save_png(OUT + "/weapon-review.png")
		for i in weapons.size():
			atlas.get_region(Rect2i(0,i*512,2048,512)).save_png(OUT + "/pose-"+weapons[i]+".png")
	print("MESHY_DANTE_RESULT failures=", failures.size(), " max_palm_error=", max_contact_error)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture_motion(player: Node2D) -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "/motion")
	var frame_index := 0
	for weapon in weapons:
		player.equip_weapon(weapon)
		if not _motion_filter.is_empty() and weapon not in _motion_filter: continue
		frame_index = weapons.find(weapon) * 150
		player.model_root.rotation.y = -0.6
		player.viewport_3d.get_camera_3d().size = 2.05 if weapon == "axe" else (1.85 if weapon == "bat" else 1.7)
		for frame in 150:
			var stage := frame / 30
			var moving := stage == 1 or stage == 3
			var running := stage == 3
			var aiming := stage == 2
			player._cancel_reload()
			if stage == 4 and weapon not in MELEE:
				player._reload_weapon = weapon
				player._reload_duration = 1.0
				player._reload_elapsed = float(frame % 30) / 30.0
			if (stage == 2 or (stage == 4 and weapon in MELEE)) and frame % (30 if weapon in MELEE else 20) == 0: player.combat_pose.on_attack(weapon)
			player.velocity = Vector2(0, -90 if running else -27.6) if moving else Vector2.ZERO
			if moving: player.walk_clock = fposmod(player.walk_clock + TAU / (19.0 if running else 29.0), TAU)
			player._update_locomotion(1.0 / 30.0, moving, running)
			player.meshy_rig.prepare_pose(1.0 / 30.0, moving, running)
			player.combat_pose.update(player, 1.0 / 30.0, aiming, running, player._gait_arm_swing())
			player.meshy_rig.update_pose(1.0 / 30.0, moving, running)
			for side in ["Left","Right"]:
				var arm: Node3D = player.left_lower_arm if side == "Left" else player.right_lower_arm
				check(player.meshy_rig.palm_position(side).distance_to(arm.get_node("Palm").global_position) < 0.005, weapon + " moving palm contact")
			await process_frame
			await RenderingServer.frame_post_draw
			dump_clearance(player, frame_index)
			player.viewport_3d.get_texture().get_image().save_png(OUT + "/motion/%04d.png" % frame_index)
			frame_index += 1
	player._cancel_reload()

func dump_clearance(player: Node2D, frame: int) -> void:
	var mesh: MeshInstance3D = player.meshy_rig._skin_mesh
	var arrays := mesh.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vertices: PackedVector3Array = mesh.bake_mesh_from_current_skeleton_pose().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var torso: Array = []
	var sleeves: Array = []
	# Skin weights and bind-space classification never change during playback.
	# Cache only the indices; every frame still samples newly baked geometry.
	if _torso_indices.is_empty():
		var names: Array[String] = []
		for i in mesh.skin.get_bind_count():
			var bind_name := String(mesh.skin.get_bind_name(i))
			if bind_name.is_empty(): bind_name = player.meshy_rig.skeleton.get_bone_name(mesh.skin.get_bind_bone(i))
			names.append(bind_name)
		for i in vertices.size():
			var body_weight := 0.0
			var sleeve_weight := 0.0
			for slot in 4:
				var bind: int = joints[i * 4 + slot]
				var weight: float = weights[i * 4 + slot]
				if names[bind] in ["Spine02", "Spine01", "Spine"]: body_weight += weight
				if names[bind] in ["LeftForeArm", "RightForeArm"]: sleeve_weight += weight
				if names[bind] in ["LeftArm", "RightArm"]:
					var local: Vector3 = mesh.skin.get_bind_pose(bind) * original[i]
					if local.y > 0.10: sleeve_weight += weight
			if body_weight > 0.85: _torso_indices.append(i)
			if sleeve_weight > 0.85: _sleeve_indices.append(i)
		var sources := []
		for i in _sleeve_indices:
			var influences := {}
			for slot in 4:
				if weights[i*4+slot] > 0.001: influences[names[joints[i*4+slot]]] = weights[i*4+slot]
			sources.append({"vertex":i,"rest":[original[i].x,original[i].y,original[i].z],"weights":influences})
		FileAccess.open(OUT+"/sleeve-sources.json",FileAccess.WRITE).store_string(JSON.stringify(sources))
	for i in _torso_indices: torso.append([vertices[i].x, vertices[i].y, vertices[i].z])
	for i in _sleeve_indices: sleeves.append([vertices[i].x, vertices[i].y, vertices[i].z])
	var file := FileAccess.open(OUT + "/motion/clearance-%04d.json" % frame, FileAccess.WRITE)
	file.store_string(JSON.stringify({"torso": torso, "sleeves": sleeves, "weapon": player.active_weapon_id}))

func capture_hands(player: Node2D, weapon: String = "pistol") -> void:
	player.equip_weapon(weapon)
	for i in 90:
		player._update_locomotion(1.0 / 60.0, false, false)
		player.meshy_rig.prepare_pose(1.0 / 60.0, false, false)
		player.combat_pose.update(player, 1.0 / 60.0, true, false, 0.0)
		player.meshy_rig.update_pose(1.0 / 60.0, false, false)
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.size = 0.45
	var focus: Vector3 = player.weapon_mount_node.global_position
	var atlas := Image.create(1536, 512, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	var index := 0
	for offset in [Vector3(.5, .15, -.6), Vector3(-.5, .15, -.6), Vector3(.5, .15, .6)]:
		cam.global_position = focus + offset
		cam.look_at(focus)
		await process_frame
		await RenderingServer.frame_post_draw
		atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 512, 512), Vector2i(index * 512, 0))
		index += 1
	atlas.save_png(OUT + "/"+weapon+"-hands.png")
