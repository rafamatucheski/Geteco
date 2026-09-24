extends SceneTree

var failures := 0
var player: CharacterBody2D
var room: Node2D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func walk_to(point: Vector2) -> bool:
	for i in 160:
		var motion := point-player.global_position
		if motion.length() < 1.0: return true
		var hit := player.move_and_collide(motion.limit_length(5.0))
		if hit != null:
			print("Blocked by ",hit.get_collider().get_path())
			return false
		await physics_frame
	return false

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var saves := root.get_node("SaveManager")
	var directory := "user://cave-reward-validation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	saves._save_dir = directory
	saves._save_directory_ready = false
	seed(428)
	var mountain: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	mountain.position = Vector2(4300,-4960)
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready or not mountain.interior_manager.region_ready: await process_frame
	player = mountain.player_instance
	player.set_physics_process(false)
	player.collision_layer = 4
	var exterior: Node2D = mountain.find_child("WaterfallCaveExterior",true,false)
	var manager: Node = mountain.interior_manager
	room = manager.mystery_cave_interior
	player.global_position = exterior.entrance.global_position+Vector2(0,28)
	for i in 5: await physics_frame
	check(await walk_to(room.spawn_point.global_position),"Entrance crosses the physical waterfall opening")
	await create_timer(0.3).timeout
	check(room.contains_actor(player),"Waterfall entrance reaches the correct cave")
	exterior._visibility_clock = 0.0
	exterior._process(0.2)
	check(exterior.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED and not exterior.model.is_processing(),"Waterfall rendering and spray simulation stop while the player is indoors")
	var reward: Area2D = room.get_node("SecretRPG")
	check(reward.model.visible and not reward.collected,"Secret RPG is visible before collection")
	var weapon: Node3D = reward.model.get_node("FloorWeapon")
	check(reward.model.has_node("FloorHalo"), "Secret weapon has a visible collection circle")
	check(reward.position.distance_to(room.project_floor(Vector2(reward.model.position.x, reward.model.position.z))) < 0.01, "Visible reward and contact area share the same clear floor position")
	var long_tube := false
	for part in weapon.get_children():
		# WeaponFinish3D batches static cylinders into ArrayMesh geometry.
		if part is MeshInstance3D and part.mesh != null and part.mesh.get_aabb().size.z > 0.7: long_tube = true
	check(long_tube and weapon.has_node("LoadedRocket"),"Pickup displays the long launcher tube and rocket instead of the generic pistol model")
	print("CAVE_DISTANCE entrance=", reward.global_position.distance_to(player.global_position))
	check(not reward.can_collect(player),"Reward cannot be collected from the cave entrance")
	check(await walk_to(room.to_global(room.project_floor(Vector2(0,2.4)))),"Entrance path is clear")
	check(await walk_to(room.to_global(room.project_floor(Vector2(0,2.0)))),"Player can approach the reward without crossing rocks or furniture")
	print("CAVE_DISTANCE approach=", reward.global_position.distance_to(player.global_position), " collected=", reward.collected)
	check(reward.can_collect(player),"Open case can be interacted with from its clear front")
	check(not reward.collected,"Approaching without touching the pickup does not collect it remotely")
	player.is_dead = true
	check(not reward.request_pickup(player),"Dead player cannot take the secret")
	player.is_dead = false
	player.is_in_dialogue = true
	check(not reward.request_pickup(player),"Reading evidence does not also collect the weapon")
	player.is_in_dialogue = false
	var before_ammo: Dictionary = player.weapon_ammo.get("rpg",{"clip":0,"reserve":0}).duplicate()
	check(await walk_to(reward.global_position), "Player walks over the reward on clear floor")
	for frame in 3: await physics_frame
	check(reward.collected and not reward.model.visible,"Walking over the weapon collects it without pressing Interact")
	var ammo: Dictionary = player.weapon_ammo["rpg"]
	var total: int = int(ammo.clip)+int(ammo.reserve)
	check(total == int(before_ammo.clip)+int(before_ammo.reserve)+4,"Secret grants exactly four rockets")
	check(int(ammo.clip) > 0 and player.can_carry_weapon("rpg"),"RPG is usable with a loaded rocket")
	check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Collection keeps the occupied cave rendering movement and animations")
	player.equip_weapon("rpg")
	check(player.active_weapon_id == "rpg" and not player.is_control_disabled, "Collected RPG equips without locking controls")
	player.set_physics_process(true)
	var walk_start := player.global_position
	Input.action_press("move_down")
	await create_timer(0.12).timeout
	Input.action_release("move_down")
	check(player.global_position.distance_to(walk_start) > 1.0, "Real player movement continues after equipping the RPG")
	player.set_physics_process(false)
	player.equip_weapon("fists")
	check(player.active_weapon_id == "fists", "Weapon switching remains available after the pickup")
	check(not reward.request_pickup(player),"Second interaction cannot duplicate the reward")
	check(saves.save_game("cave_reward_qa").success,"Reward state saves to an isolated file")
	var loaded: Dictionary = saves.load_game("cave_reward_qa")
	check(loaded.success and reward.pickup_id in loaded.data.player.world_pickups_collected,"Save file preserves the unique cave discovery")
	player.restore(loaded.data.player)
	var revisit := preload("res://world/mountain_pass/MountainMysteryCaveInterior.gd").new()
	revisit.inline_mode = true
	revisit.position = room.position+Vector2(5000,0)
	mountain.add_child(revisit)
	var restored_reward: Area2D = revisit.get_node("SecretRPG")
	restored_reward._process(0.1)
	check(restored_reward.collected and not restored_reward.model.visible,"Rebuilt cave hides the reward after restoring the save")
	check(int(player.weapon_ammo.rpg.clip)+int(player.weapon_ammo.rpg.reserve) == total,"Reload does not add ammunition")
	revisit.queue_free()
	check(await walk_to(room.to_global(room.project_floor(Vector2(0,2.4)))),"Return route from the case stays clear")
	for i in 5: await physics_frame
	check(await walk_to(exterior.entrance.global_position+Vector2(0,28)),"Cave exit works on foot after collection")
	await create_timer(0.3).timeout
	check(not player.has_meta("mountain_interior"),"Exit restores the exterior state")
	mountain.queue_free()
	await process_frame
	print("CAVE REWARD failures=",failures)
	quit(0 if failures == 0 else 1)
