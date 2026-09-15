extends SceneTree

## Explicit post-arrival QA checkpoint, NOT an intro/story-flow test. Uses the
## production Player, capsule, controller, weapons and vehicle interaction.
const GAME := preload("res://world/harbor/HarborGame.tscn")
var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DANTE_CONTRACT: " + message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)

func _run() -> void:
	seed(9007)
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(8)
	player = world.get_node("Player")
	check(world.gameplay_ready and world.campaign_controller.phase == "complete", "Explicit completed-arrival fixture resumes without CGI or unlocking hacks")
	check(player.is_physics_processing() and not player.is_control_disabled and not player.is_in_dialogue,
		"Production controller is unlocked by ordinary checkpoint resume")
	var capsule := player.get_node("Collision") as CollisionShape2D
	check(capsule.shape is CapsuleShape2D and not capsule.disabled, "Original production capsule stays active")
	var original_mask := player.collision_mask
	for property in ["model_root", "torso_node", "head_node", "left_upper_arm", "left_lower_arm", "right_upper_arm", "right_lower_arm", "left_upper_leg", "left_lower_leg", "right_upper_leg", "right_lower_leg", "weapon_mount_node"]:
		var node: Node3D = player.get(property)
		check(is_instance_valid(node) and node.is_inside_tree() and node.transform.origin.is_finite(), "Live rig node: " + property)
	check(is_instance_valid(player.mat_black_jacket), "Production jacket material exists")
	if not failures.is_empty():
		await _finish()
		return
	check(player.weapon_mount_node.get_parent() == player.right_lower_arm, "Weapon socket belongs to right forearm")
	check(player.mat_black_jacket.albedo_texture != null, "Canonical overshirt has its authored texture")
	var meshes: Array[Node] = player.model_root.find_children("*", "MeshInstance3D", true, false)
	print("DANTE_MEASURED meshes=%d (measurement only, not a quality threshold)" % meshes.size())
	var start := _clear_walk_start(capsule)
	check(start != Vector2.INF, "Physical walk/run test corridor is clear")
	if start == Vector2.INF:
		await _finish()
		return
	# Only fixture placement; all subsequent gait displacement is native input.
	player.global_position = start
	player.get_node("Camera").reset_smoothing()
	await frames(2)
	var gait_walk: Dictionary = await _gait(false)
	var gait_run: Dictionary = await _gait(true)
	check(absf(gait_walk.distance - player.speed * 30.0 / Engine.physics_ticks_per_second) < 2.0 and gait_walk.leg_range > 0.15, "Native walking moves body and articulates legs")
	check(gait_run.distance > gait_walk.distance * 1.25 and gait_run.leg_range > 0.25, "Native sprint is faster and animates a distinct leg cycle")
	check(player.collision_mask == original_mask and not capsule.disabled, "Gait never bypassed production collisions")
	for id in ["pistol", "shotgun", "smg"]:
		check(player.add_weapon_loot(StringName(id), 24), "Production loot API grants fixture weapon " + id)
		player.equip_weapon(id)
		await frames(2)
		check(player.active_weapon_id == id and player.current_gun_mesh.get_parent() == player.weapon_mount_node,
			"Equipped production mesh attaches to socket: " + id)
		check(player.muzzle_flash_3d.get_parent() == player.current_gun_mesh, "Muzzle belongs to equipped mesh: " + id)
	player.equip_weapon("pistol")
	player._trigger_muzzle_flash_3d()
	check(player.muzzle_flash_3d.visible and player.muzzle_light_3d.visible, "Weapon flash and light activate together")
	await create_timer(0.25).timeout
	check(not player.muzzle_flash_3d.visible and not player.muzzle_light_3d.visible, "Weapon flash finishes instead of remaining on")
	var health_before: int = player.health
	var armor_before: int = player.armor
	var jacket_before: Color = player.mat_black_jacket.albedo_color
	player.take_damage(20)
	check(player.health == health_before - maxi(0, 20 - armor_before), "Production damage respects armor and health")
	check(player.mat_black_jacket.albedo_color.r > player.mat_black_jacket.albedo_color.g, "Damage flash appears on actual jacket material")
	await create_timer(0.35).timeout
	check(player.mat_black_jacket.albedo_color.is_equal_approx(jacket_before), "Damage flash restores the original outfit material")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	# A second explicit fixture placement near the existing parked car, away
	# from building interactions. Boarding itself MUST use the real E binding.
	player.global_position = car.global_position + Vector2(0, 60)
	await frames(3)
	await key(KEY_E)
	check(car.is_driven_by_player and not player.visible, "Native E boards the existing production car")
	check(player.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden Dante suspends its 3D viewport")
	await key(KEY_E)
	check(not car.is_driven_by_player and player.visible and player.is_physics_processing(), "Native E exits and restores walking control")
	check(player.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not capsule.disabled,
		"Visible Dante resumes viewport and original capsule")
	check(player.collision_mask == original_mask, "Vehicle sequence preserves Player collision mask")
	if OS.get_cmdline_user_args().has("--capture"):
		check(DisplayServer.get_name() != "headless", "Capture requires a real renderer")
		if DisplayServer.get_name() != "headless":
			# Review-only close-up after functional assertions; not a new game zoom.
			var camera: Camera2D = player.get_node("Camera")
			camera.zoom_close = 4.0
			camera.zoom_far = 4.0
			camera.zoom = Vector2(4, 4)
			camera.reset_smoothing()
			await frames(12)
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			check(picture.save_png("D:/geteco/harbor-stage3-dante.png") == OK, "Actual rendered capture saved in authorized workspace")
	print("DANTE_GAIT walk=%.1f sprint=%.1f leg_walk=%.3f leg_run=%.3f" % [gait_walk.distance,gait_run.distance,gait_walk.leg_range,gait_run.leg_range])
	await _finish()

func _clear_walk_start(capsule: CollisionShape2D) -> Vector2:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = capsule.shape
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	for candidate in [Vector2(1700, 2050), Vector2(1600, 2100), Vector2(1750, 2000)]:
		var clear := true
		for offset in range(0, 161, 15):
			query.transform = Transform2D(0.0, candidate + Vector2(offset, 0)) * capsule.transform
			if not player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				clear = false
				break
		if clear:
			return candidate
	return Vector2.INF

func _gait(sprinting: bool) -> Dictionary:
	var before := player.global_position
	var smallest := INF
	var largest := -INF
	Input.action_press("move_right")
	if sprinting:
		Input.action_press("sprint")
	for frame in 30:
		await physics_frame
		var angle: float = player.left_upper_leg.rotation.x
		smallest = minf(smallest, angle)
		largest = maxf(largest, angle)
	Input.action_release("move_right")
	Input.action_release("sprint")
	return {"distance": before.distance_to(player.global_position), "leg_range": largest - smallest}

func _finish() -> void:
	for action in ["move_right", "sprint", "interact"]:
		Input.action_release(action)
	world.queue_free()
	await process_frame
	await process_frame
	print("HARBOR DANTE CONTRACT: %d failure(s)" % failures.size())
	quit(1 if failures.size() else 0)
