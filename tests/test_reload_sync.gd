extends SceneTree

var failures: Array[String] = []
var shots := [0]

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player._respawn_grace_active = true
	player.weapon_fired.connect(func(): shots[0] += 1)
	await process_frame
	var capture := "capture" in OS.get_cmdline_user_args()
	if capture:
		player.viewport_3d.size = Vector2i(384,384)
		var view := player.viewport_3d.get_camera_3d()
		view.position = Vector3(1.6,1.7,2.5)
		view.look_at(Vector3(0,0.9,0),Vector3.UP)
		view.fov = 28.0
		player.model_root.rotation.y = PI
	for id in ["pistol","magnum","shotgun","ak47"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		player.weapon_ammo[id] = {"clip":1,"reserve":3}
		for frame in 60: player.combat_pose.update(player,1.0/60.0,true,false,0)
		var initial_left: Vector3 = player.left_lower_arm.get_node("Palm").global_position
		player._reload_active_weapon()
		var started := Time.get_ticks_msec()
		var duration: float = player._reload_duration
		var next_capture := 0.08
		var capture_index := 0
		var furthest := 0.0
		var finite := true
		var contact := true
		while player.is_reloading():
			await process_frame
			if not player.is_reloading(): break
			player.combat_pose.update(player,1.0/60.0,true,false,0)
			player._shoot_towards(player.global_position+Vector2(300,0))
			finite = finite and player.weapon_mount_node.global_transform.is_finite()
			var palm: Vector3 = player.right_lower_arm.get_node("Palm").global_position
			contact = contact and palm.distance_to(player.current_gun_mesh.to_global(player.combat_pose.GRIPS[id])) < 0.001
			furthest = maxf(furthest,initial_left.distance_to(player.left_lower_arm.get_node("Palm").global_position))
			if capture and player.get_reload_progress() >= next_capture and capture_index < 5:
				await RenderingServer.frame_post_draw
				player.viewport_3d.get_texture().get_image().save_png("D:/geteco/artifacts/reload-sync-0910/%s_%d.png" % [id,capture_index])
				capture_index += 1
				next_capture += 0.20
		# The final loop iteration may see completion; do not fire on that frame.
		var elapsed := (Time.get_ticks_msec()-started)/1000.0
		print("RELOAD_TIMING ",id," expected=",duration," observed=",elapsed)
		check(absf(elapsed-duration)<0.22,id+" finishes at the selected recording duration")
		check(finite and contact,id+" animated grip stays attached and finite")
		check(furthest>0.07,id+" support hand visibly moves during reload")
		check(player.weapon_ammo[id] == {"clip":4,"reserve":0},id+" clip and reserve committed once at the end")
	check(shots[0] == 0,"no projectile while reloading even with a loaded round")

	player.equip_weapon("pistol")
	for flag in ["is_control_disabled","is_in_dialogue","is_dead","is_arrested","is_recovering"]:
		player.weapon_ammo.pistol = {"clip":1,"reserve":11}
		player._reload_active_weapon()
		player.set(flag,true)
		await process_frame
		await process_frame
		check(not player.is_reloading() and not player._reload_audio.playing,"cancel on "+flag)
		check(player.weapon_ammo.pistol == {"clip":1,"reserve":11},"cancellation preserves ammo: "+flag)
		player.set(flag,false)
	player._reload_active_weapon()
	player.hide()
	player.show()
	await create_timer(2.0).timeout
	check(not player.is_reloading() and player.weapon_ammo.pistol == {"clip":1,"reserve":11},"boarding cancellation cannot complete later")

	player._reload_active_weapon()
	await create_timer(0.25).timeout
	paused = true
	await create_timer(0.10,true).timeout
	var frozen: float = player.get_reload_progress()
	await create_timer(0.25,true).timeout
	check(absf(player.get_reload_progress()-frozen)<0.02 and player.is_reloading(),"pause freezes reload sound and pose together")
	paused = false
	var bus := AudioServer.get_bus_index("SFX")
	var was_muted := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus,true)
	await player.reload_finished
	check(player.weapon_ammo.pistol == {"clip":12,"reserve":0},"muted audio still completes reload")
	AudioServer.set_bus_mute(bus,was_muted)
	player._shoot_towards(player.global_position+Vector2(300,0))
	check(shots[0] == 1 and player.weapon_ammo.pistol.clip == 11,"firing unlocks after completion")
	print("RELOAD_SYNC failures=",failures)
	scene.queue_free()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
