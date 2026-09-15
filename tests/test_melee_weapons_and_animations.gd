extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)

func _run() -> void:
	print("--- TEST MELEE WEAPONS AND ANIMATIONS ---")

	# 1. WeaponCatalog damage differentiation
	var fists_data = WeaponCatalog.get_weapon("fists")
	var knuckles_data = WeaponCatalog.get_weapon("knuckles")
	var knife_data = WeaponCatalog.get_weapon("knife")
	var bat_data = WeaponCatalog.get_weapon("bat")
	var axe_data = WeaponCatalog.get_weapon("axe")

	check(not knuckles_data.is_empty(), "knuckles exists in WeaponCatalog")
	check(not bat_data.is_empty(), "bat exists in WeaponCatalog")
	check(not knife_data.is_empty(), "knife exists in WeaponCatalog")
	check(not axe_data.is_empty(), "axe exists in WeaponCatalog")

	var dmg_fists: int = int(fists_data.get("damage", 0))
	var dmg_knuckles: int = int(knuckles_data.get("damage", 0))
	var dmg_knife: int = int(knife_data.get("damage", 0))
	var dmg_bat: int = int(bat_data.get("damage", 0))
	var dmg_axe: int = int(axe_data.get("damage", 0))

	check(dmg_knife != dmg_axe, "Knife damage (%d) differs from Axe damage (%d)" % [dmg_knife, dmg_axe])
	check(dmg_fists < dmg_knuckles, "Fists (%d) < Knuckles (%d)" % [dmg_fists, dmg_knuckles])
	check(dmg_knuckles < dmg_knife, "Knuckles (%d) < Knife (%d)" % [dmg_knuckles, dmg_knife])
	check(dmg_knife < dmg_bat, "Knife (%d) < Bat (%d)" % [dmg_knife, dmg_bat])
	check(dmg_bat < dmg_axe, "Bat (%d) < Axe (%d)" % [dmg_bat, dmg_axe])

	# 2. Ammu-Nation stock availability
	var ammu = load("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	var stock: Array = ammu.stock
	check("knife" in stock, "Knife in Ammu-Nation stock")
	check("knuckles" in stock, "Knuckles in Ammu-Nation stock")
	check("bat" in stock, "Bat in Ammu-Nation stock")
	check("axe" in stock, "Axe in Ammu-Nation stock")
	ammu.free()

	# 3. Personal loadout slots
	var loadout_script = load("res://world/harbor/monaliza/PersonalLoadout.gd")
	check(loadout_script.slot_for("knuckles") == "corpo", "Knuckles maps to 'corpo' loadout slot")
	check(loadout_script.slot_for("bat") == "corpo", "Bat maps to 'corpo' loadout slot")
	check(loadout_script.slot_for("knife") == "corpo", "Knife maps to 'corpo' loadout slot")
	check(loadout_script.slot_for("axe") == "corpo", "Axe maps to 'corpo' loadout slot")

	# 4. Player combat poses & attack animation distinctiveness
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene

	var player = load("res://characters/Player.gd").new()
	player.name = "Player"
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)

	var poses: Dictionary = {}
	var melee_ids := ["fists", "knuckles", "knife", "bat", "axe"]

	for id in melee_ids:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		player.combat_pose.on_attack(id)
		# Advance 0.12s into the attack stroke
		player.combat_pose.update(player, 0.12, true, false, 0.0)
		var hand_pos: Vector3 = player.weapon_mount_node.global_position
		var hand_rot: Vector3 = player.weapon_mount_node.global_basis.get_euler()
		poses[id] = {"pos": hand_pos, "rot": hand_rot}

	# Ensure all 5 melee attack poses are mathematically distinct
	for i in melee_ids.size():
		for j in range(i + 1, melee_ids.size()):
			var id_a = melee_ids[i]
			var id_b = melee_ids[j]
			var pos_a: Vector3 = poses[id_a]["pos"]
			var pos_b: Vector3 = poses[id_b]["pos"]
			var rot_a: Vector3 = poses[id_a]["rot"]
			var rot_b: Vector3 = poses[id_b]["rot"]
			var dist := pos_a.distance_to(pos_b)
			var angle_diff := rot_a.distance_to(rot_b)
			var is_distinct := dist > 0.015 or angle_diff > 0.05
			check(is_distinct, "Attack animation %s differs from %s (dist=%.3f, rot_diff=%.3f)" % [id_a, id_b, dist, angle_diff])

	# 5. World pickups verification
	# Test HarborAlleys
	var alleys = load("res://world/harbor/HarborAlleys.gd").new()
	scene.add_child(alleys)
	var found_alley_knuckles := false
	var found_alley_bat := false
	for child in alleys.get_children():
		if child is WeaponPickup:
			if child.weapon_id == &"knuckles": found_alley_knuckles = true
			if child.weapon_id == &"bat": found_alley_bat = true
	check(found_alley_knuckles, "Alley contains knuckles pickup")
	check(found_alley_bat, "Alley contains bat pickup")
	alleys.free()

	# Test IronCobraCulDeSac
	var culdesac = load("res://IronCobraCulDeSac.gd").new()
	scene.add_child(culdesac)
	var found_culdesac_knuckles := false
	var found_culdesac_knife := false
	for child in culdesac.get_children():
		if child is WeaponPickup:
			if child.weapon_id == &"knuckles": found_culdesac_knuckles = true
			if child.weapon_id == &"knife": found_culdesac_knife = true
	check(found_culdesac_knuckles, "Cul-de-sac contains knuckles pickup")
	check(found_culdesac_knife, "Cul-de-sac contains knife pickup")
	culdesac.free()

	# Test HarborSouthPort
	var port_file := FileAccess.open("res://world/harbor/HarborSouthPort.gd", FileAccess.READ)
	var port_src := port_file.get_as_text() if port_file else ""
	check("PortMaintenanceAxePickup" in port_src and '&"axe"' in port_src, "Harbor South Port defines maintenance axe pickup")

	# 6. NPC Melee Rig and Gangster Attack Verification
	var ped = load("res://characters/AnimatedPedestrian3D.gd").new()
	scene.add_child(ped)
	ped.ensure_presentation()
	var rig_script = load("res://characters/pedestrians/NPCCombatRig.gd")
	var rig = rig_script.attach(ped, "knuckles")
	check(rig.active_weapon_id == "knuckles", "NPC rig equips knuckles")
	rig.attack()
	check(rig.combat_pose.action_age == 0.0, "NPC rig attack triggers combat pose")
	rig.equip("bat")
	check(rig.active_weapon_id == "bat", "NPC rig equips bat")
	rig.attack()
	check(rig.combat_pose.action_age == 0.0, "NPC rig bat attack triggers combat pose")
	ped.free()

	# 7. Logger damage stays independent from player weapon buffs
	var logger_file := FileAccess.open("res://world/mountain_pass/WinterResident.gd", FileAccess.READ)
	var logger_src := logger_file.get_as_text() if logger_file else ""
	check('var axe_dmg: int = 28' in logger_src, "Logger uses separately balanced damage")

	# Clean up
	scene.free()

	print("TEST COMPLETED with %d failures" % failures.size())
	if failures.is_empty():
		print("ALL MELEE TESTS PASSED!")
		quit(0)
	else:
		print("TESTS FAILED:")
		for f in failures:
			print("  - " + f)
		quit(1)
