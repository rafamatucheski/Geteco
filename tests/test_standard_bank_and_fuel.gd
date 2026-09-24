extends "res://tests/test_bank_loot_presentation.gd"

# Interior migration regression: articulated guards, vault route/rewards and
# the relocated convenience checkout. Exterior police routing has its own suite.
func _run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.get_node("SaveManager")._save_dir = "user://standard-bank-fuel-validation/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_call_complete",true)
	var city = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	while not city.gameplay_ready: await process_frame
	var player = city.get_node("Player")
	player.active_weapon_id = "fists"
	player.weapon_aim_active = false
	var manager = city.get_node("Interiors")
	var room = manager.get_node("InteriorSpaces/BankInterior")
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	player.set_physics_process(false)
	await create_timer(.6).timeout
	await capture("01_entrada")
	player.active_weapon_id = "pistol"
	player.weapon_aim_active = true
	room._process(.5)
	check(room.armed_warning and not room.alarm_started,"Weapon warning preserves peaceful entry")
	await capture("02_advertencia")
	player.global_position = room.to_global(room.project_floor(Vector2.ZERO))
	player._respawn_grace_active = true
	player.weapon_fired.emit()
	check(room.alarm_started and room.dispatched,"First shot starts the existing police response")
	for frame in 90:
		await physics_frame
		if room.guards.any(func(guard): return guard.fire_cooldown>0): break
	check(room.guards.any(func(guard): return guard.fire_cooldown>0),"Rescaled guards fire real projectiles")
	for guard in room.guards: guard.take_damage(1000,true)
	for frame in 70: await physics_frame
	check(room._security_clear() and room.keycard_available,"Guards leave the security card")
	room.set_process(false)
	player.global_position = room.keycard_position
	room._tick_vault(1.3,true)
	check(room.keycard_taken,"Security card can be picked up")
	player.global_position = room.to_global(room.vault_position)
	room._tick_vault(.7,true)
	check(room.lockpick.active,"Card unlocks the lockpick interaction")
	for attempt in 3:
		room.lockpick.angle = room.lockpick.target_angle
		room.lockpick.attempt()
	room._process(3.1)
	check(room.vault_open and room.vault_body.collision_layer==0,"Vault opens physically")
	await capture("03b_cofre_aberto")
	var wallet: int = player.money
	var loot_achievements: Array = player.unlocked_achievements.duplicate()
	player.global_position = room.to_global(room.loot_positions[0])
	room._tick_vault(1.3,true)
	var loot_bonus := 0
	for id in player.unlocked_achievements:
		if id not in loot_achievements: loot_bonus += AchievementCatalog.cash_reward(id)
	print("BANK_PAYOUT first before=",wallet," after=",player.money," achievement_bonus=",loot_bonus)
	check(player.money==wallet+4000+loot_bonus,"First pile pays $4000 plus separate achievement rewards")
	await capture("04_coleta")
	manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",room.entrance.destination_id)
	var fuel = manager.get_node("InteriorSpaces/FuelInterior")
	player.global_position = fuel.to_global(fuel.project_floor(Vector2(0,.35)))
	player.set_physics_process(false)
	fuel.cashier_resists = false
	for frame in 5: await physics_frame
	fuel.set_process(false)
	player.weapon_aim_active = true
	var clerk = fuel.civilians[0]
	wallet = player.money
	var prior: Array = player.unlocked_achievements.duplicate()
	fuel._tick_cashier(3.2,clerk.global_position)
	var bonus := 0
	for id in player.unlocked_achievements:
		if id not in prior: bonus += AchievementCatalog.cash_reward(id)
	check(fuel.cash_paid and player.money==wallet+180+bonus,"Relocated checkout pays $180 plus separate achievement rewards")
	wallet = player.money
	fuel._tick_cashier(4,clerk.global_position)
	check(player.money==wallet,"Checkout does not repeat its payment")
	print("STANDARD_BANK_FUEL failures=",failures)
	quit(0 if failures.is_empty() else 1)
