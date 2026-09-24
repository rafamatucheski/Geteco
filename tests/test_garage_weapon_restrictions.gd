extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("garage_weapons_%d" % OS.get_process_id()) + "/"
	root.get_node("CampaignState").reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready: await process_frame
	var player = current_scene.get_node("Player")
	check(player.use_meshy_dante and is_instance_valid(player.meshy_rig), "Gameplay loads the new Dante by default")
	player.set_physics_process(false)
	var manager = current_scene.get_node("Interiors")
	var garage = manager.garage_interior
	var door = current_scene.get_node("District/Garage/Entrance")
	check(garage.inline_mode and garage.exit_door==null and not door.show_entrance_marker and not door.handle_input_locally, "Garage uses a physical door without E or entry marker")
	player.global_position = door.global_position+Vector2(0,100)
	player.personal_loadout_enabled = false
	player.weapon_inventory["pistol"] = true
	player.weapon_ammo["pistol"] = {"clip": 12, "reserve": 24}
	player.equip_weapon("pistol")
	check(player.active_weapon_id == "pistol", "Exterior allows equipping weapons")
	player.money = 1000
	player.customize_weapon("pistol", "install")
	player.weapon_flashlight.toggle()
	check(player.weapon_flashlight.enabled, "Exterior allows the installed flashlight")
	player.global_position = garage.spawn_point.global_position
	for frame in 3: await physics_frame
	check(player.weapons_forbidden() and player.active_weapon_id == "fists", "Crossing the real threshold holsters the weapon immediately")
	check(not player.weapon_flashlight.enabled, "Garage entry extinguishes the flashlight immediately")
	player.weapon_flashlight.toggle()
	check(not player.weapon_flashlight.enabled, "Garage blocks flashlight activation")
	var ammo: Dictionary = player.weapon_ammo.duplicate(true)
	for id in ["pistol", "grenade", "rpg", "flamethrower", "knife", "axe", "fists"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		check(player.active_weapon_id == "fists", "Cannot draw " + id)
		# Exercise the attack boundary even with externally restored equipment.
		player.active_weapon_id = id
		player._shoot_towards(player.global_position + Vector2(100, 0))
		check(player.active_weapon_id == "fists" and player.weapon_ammo == ammo, "Attack blocked without ammo consumption: " + id)
	player._cycle_weapon(1)
	check(player.active_weapon_id == "fists", "Weapon cycling stays unarmed")
	check(not player._reload_allowed(), "Reloading is blocked")
	var maciota = garage.jager_npc
	var mechanic = preload("res://world/harbor/monaliza/WorkshopMechanicModel.gd").new()
	for actor in [maciota, mechanic]:
		check(not actor.has_method("take_damage") and not actor.has_method("get_run_over") and not actor.has_method("die"), "Essential character has no damage, run-over or death entry point: " + str(actor.get_script().resource_path))
		check(not actor.is_in_group("damageable"), "Essential character is not a damage target")
	mechanic.free()
	player.global_position = door.global_position + Vector2(0, 100)
	await physics_frame
	player.equip_weapon("pistol")
	check(not player.weapons_forbidden() and player.active_weapon_id == "pistol", "Exit restores weapon use without losing inventory")
	check(player.weapon_customization.pistol.installed, "Garage preserves the installed accessory")
	player.global_position = garage.spawn_point.global_position
	await physics_frame
	check(player.active_weapon_id == "fists" and player.weapons_forbidden(), "Restored interior position holsters the saved weapon")
	player.global_position = door.global_position + Vector2(0, 80)
	player.equip_weapon("pistol")
	check(player.active_weapon_id == "pistol" and not player.weapons_forbidden(), "Exterior respawn cannot retain a stale weapon lock")
	print("GARAGE WEAPON RESTRICTIONS: %d failures" % failures)
	quit(1 if failures else 0)
