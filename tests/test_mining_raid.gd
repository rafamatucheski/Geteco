extends "res://tests/test_mining_session.gd"
## Real Main: first damage is unprotected; subsequent fixture combat uses the
## existing god-mode option to isolate guards, loot and lifecycle deterministically.
## Player kills use Gameplay.fire_at. No guard health or death is injected.
const RAID_STATE := preload("res://gameplay/mining/MiningRaidState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")
var raid: Node3D
var gallery: Node3D
var shots := 0
var player_damage := 0.0
var fixture_path := ""
var _finished := false
var _guard_ids: Array[int] = []
var _diagnostics: Array[Dictionary] = []
var _escape_only := false
var _reentry_only := false
var _vehicle_escape := false
var _repopulation_only := false
var _resume_snapshot := ""

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): failures.append("360s mining raid watchdog"); finish(3))
	run.call_deferred()

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _gunfire(_origin: Vector3, _direction: Vector3, shooter: Node3D) -> void:
	if shooter.is_in_group("mining_bandits"): shots += 1

func _walk_gallery(points: Array[Vector3]) -> bool:
	for point in points:
		if not check(await walk(gallery.to_global(point)), "physical raid route " + str(point)): return false
	return true

func _enter_gallery() -> bool:
	if not check(world.session.nearest().get("place", "") == COAL.PLACE_ID, "entry is available at the actual deep-pit access"): return false
	await world.session.interact()
	var deadline := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session.state.place_id == COAL.PLACE_ID and not world.session.is_transition_blocked(): break
	if not check(world.session.state.place_id == COAL.PLACE_ID, "ordinary E interaction admits player into gallery"): return false
	gallery = world.session.room
	deadline = Time.get_ticks_msec() + 9000
	while raid.live_count() < 4 and Time.get_ticks_msec() < deadline: await physics_frame
	if not check(raid.live_count() == 4 and raid.actors.size() == 4, "four armed bandits admitted without replacing dead slots"): return false
	# Admission occurs on the process tick; allow the last capsule to execute
	# real physics and settle the authored .05 m spawn lift before querying it.
	await wait_seconds(.25)
	_guard_ids.clear()
	for guard: CharacterBody3D in raid.actors.values():
		_guard_ids.append(guard.get_instance_id())
		check(guard.is_in_group("mining_bandits") and guard.is_in_group("v2_damageable") and not guard.is_in_group("desert_bandits"), "raid guard uses production damage and a distinct ownership group")
		check(guard.is_on_floor() and not guard.test_move(guard.global_transform, Vector3.UP * .01), "guard capsule has support and full clearance")
	return true

func _shoot_guard(index: int) -> bool:
	var guard: CharacterBody3D = raid.actors.get(index)
	if not check(is_instance_valid(guard), "target guard exists " + str(index)): return false
	var accepted := 0
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(guard) and not guard.dead and Time.get_ticks_msec() < deadline:
		world.gameplay.aim_point = guard.global_position + Vector3.UP
		if world.gameplay.fire_at(guard.global_position + Vector3.UP): accepted += 1
		await physics_frame
	if is_instance_valid(guard) and not guard.dead:
		print("MINING_RAID_FIRE_BLOCKED guard=", index, " player=", world.player.global_position, " target=", guard.global_position, " accepted=", accepted, " health=", guard.health)
	var defeated: bool = (guard.dead and guard.collision_layer == 0) if is_instance_valid(guard) else raid.completed()
	return check(defeated and accepted > 0, "real player gunfire defeats guard " + str(index))

func _fight_and_take_bag(prove_damage: bool) -> bool:
	if not prove_damage and not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	# Clear the rock lip at x=16 before the turn; cutting this corner diagonally
	# was correctly rejected by the physical gallery contract test.
	if not await _walk_gallery([Vector3(9, 0, 3), Vector3(16.7, 0, 3), Vector3(16.7, 0, -.5)]): return false
	var deadline := Time.get_ticks_msec() + 8000
	while not raid.engaged and Time.get_ticks_msec() < deadline: await physics_frame
	check(raid.engaged, "walking into the eastern chamber engages the bandits")
	if prove_damage:
		var before: float = world.gameplay.health
		deadline = Time.get_ticks_msec() + 7500
		while (shots < 2 or world.gameplay.health >= before) and world.gameplay.health > 0 and Time.get_ticks_msec() < deadline:
			await physics_frame
		player_damage = before - float(world.gameplay.health)
		if not check(shots >= 2 and player_damage > 0 and world.gameplay.health > 0, "real enemy projectiles damage the unprotected living player"): return false
		check(not world.player.input_locked and not raid.save_block_reason().is_empty(), "combat keeps controls and blocks unsafe saving")
		await photo("raid-real-incoming-damage")
		world.gameplay.toggle_god_mode()
		world.session._menu("Pausa da validação")
		await wait_seconds(.45)
		var before_pause := shots
		var paused_positions: Dictionary = {}
		for index in raid.actors: paused_positions[index] = raid.actors[index].global_position
		await wait_seconds(.85)
		var still := shots == before_pause
		for index in raid.actors: still = still and raid.actors[index].global_position.is_equal_approx(paused_positions[index])
		check(still and not raid.operational(), "modal pause stops guard motion and new shots")
		world.session.close_menu()
		await wait_seconds(.3)
		check(raid.operational(), "closing modal resumes raid controls")
	world.session.state.grant_weapon("m4a1")
	world.session.state.add_ammo("m4a1", 180)
	if not check(world.session.state.equip_weapon("m4a1"), "fixture equips normal owned M4A1"): return false
	for index in [1, 3, 2]:
		if not await _shoot_guard(index): return false
	# The western stack is genuine cover. Walk around its left edge instead of
	# weakening that cover or directing an artificial damage event through it.
	if not await _walk_gallery([Vector3(16.7, 0, 6.3)]): return false
	if not await _shoot_guard(0): return false
	check(raid.live_count() == 0 and raid.actors.size() == 4, "all four defeated guards stay owned without replenishment")
	await wait_seconds(.65)
	if not await _walk_gallery([Vector3(16.7, 0, -.5), Vector3(22, 0, -.5), COAL.RAID_LOOT]): return false
	var before_bag: int = world.session.state.economy.balance
	if not check(world.session.nearest().get("target", "") == "raid_loot", "bag action uses the published raid_loot contract"): return false
	if not check(await world.session.interact(), "ordinary E interaction takes cash bag"): return false
	check(raid.pending_cash and world.session.state.economy.balance == before_bag and not raid.completed(), "carrying cash does not credit the wallet or create a receipt")
	check(not world.session.save_block_reason().is_empty() and not world.session.save_game(), "carried cash blocks production checkpoint writes")
	check(not gallery.model.raid_loot_available and raid.nearest_action().is_empty(), "carried bag cannot be collected again")
	return true

func _walk_to_exit() -> bool:
	return await _walk_gallery([Vector3(22, 0, -.5), Vector3(16.7, 0, -.5), Vector3(16.7, 0, 3), Vector3(9, 0, 3), Vector3(9, 0, 10.5)])

func _assert_released(label: String) -> void:
	await wait_seconds(.45)
	var released: bool = raid.actors.is_empty() and get_nodes_in_group("mining_bandits").is_empty()
	for instance_id in _guard_ids: released = released and not is_instance_id_valid(instance_id)
	for pickup in world.gameplay._loot:
		if is_instance_valid(pickup) and pickup.has_meta("mining_raid_loot"): released=false
	check(released, label)

func _diagnose(label: String, baseline: Dictionary = {}) -> void:
	var candidate: Dictionary = world.session.state.snapshot()
	var wallet: Dictionary = world.session.state.economy.snapshot()
	var current_combat: Dictionary = world.gameplay.snapshot()
	var live_candidate: Dictionary = candidate.duplicate(true)
	live_candidate.combat = current_combat
	var changes: Dictionary = {}
	var old_transactions: Dictionary = baseline.get("transactions", {})
	for key in wallet.get("transactions", {}):
		if not old_transactions.has(key) or old_transactions[key] != wallet.transactions[key]: changes[key] = wallet.transactions[key]
	var filename := output.path_join("candidate-" + label + ".json")
	FileAccess.open(filename, FileAccess.WRITE).store_string(JSON.stringify({"snapshot": candidate, "live_combat": current_combat}, "\t"))
	var row := {"phase": label, "before_economy": baseline, "after_economy": wallet,
		"balance_delta": int(wallet.balance) - int(baseline.get("balance", wallet.balance)), "changed_transactions": changes,
		"save_block_reason": world.session.save_block_reason(), "last_save_error": world.session.last_save_error,
		"stars": world.gameplay.stars, "crime_points": world.gameplay.crime_points,
		"hidden_time": world.gameplay.hidden_time, "health": world.gameplay.health,
		"place": world.session.state.place_id, "region": world.session.state.region_id,
		"pending_cash": raid.pending_cash, "raid_completed": raid.completed(),
		"raid_state": world.session.state.world_state.get(RAID_STATE.KEY, {}),
		"save_invalid": world.production.save_invalid, "no_save": world.production.no_save,
		"candidate_valid": GAME_STATE.new().restore_snapshot(candidate),
		"candidate_with_live_combat_valid": GAME_STATE.new().restore_snapshot(live_candidate), "candidate_file": filename}
	_diagnostics.append(row)
	var summary := row.duplicate()
	summary.erase("before_economy")
	summary.erase("after_economy")
	print("MINING_RAID_DIAGNOSTIC ", JSON.stringify(summary))
	FileAccess.open(output.path_join("diagnostics.json"), FileAccess.WRITE).store_string(JSON.stringify(_diagnostics, "\t"))

func run() -> void:
	seed(6102026)
	_escape_only = "--escape-only" in OS.get_cmdline_user_args()
	_reentry_only = "--reentry-only" in OS.get_cmdline_user_args()
	_vehicle_escape = "--vehicle-escape" in OS.get_cmdline_user_args()
	_repopulation_only = "--repopulation-only" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-snapshot="): _resume_snapshot = argument.trim_prefix("--resume-snapshot=")
	root.size = Vector2i(1280, 720)
	output = FIXTURE.output_dir("mining-raid")
	var at := LAYOUT.SECRET_ENTRY + Vector3.UP * .08
	var snapshot := FIXTURE.full_snapshot(at, true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region": "desert", "position": [at.x, at.y, at.z]}
	snapshot.world[RAID_STATE.KEY] = RAID_STATE.defaults()
	if _repopulation_only:
		var paid_state := GAME_STATE.new()
		if not check(paid_state.restore_snapshot(snapshot), "completed-raid fixture begins with a valid world"): finish(1); return
		paid_state.economy.grant_reward(RAID_STATE.RECEIPT, RAID_STATE.CASH)
		paid_state.world_state[RAID_STATE.KEY] = {"version":1,"escaped":true}
		snapshot = paid_state.snapshot()
	if _reentry_only:
		snapshot = STORE.read_valid(_resume_snapshot)
		if not check(not snapshot.is_empty(), "resume completed checkpoint from prior disk evidence"): finish(1); return
	fixture_path = FIXTURE.write_fixture(output, "checkpoint.json", snapshot)
	if not check(not fixture_path.is_empty(), "isolated raid checkpoint validates before Main startup"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", fixture_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 75000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session != null and world.session.ready_for_play and not world.production.save_invalid and world.production.store.path == fixture_path, "real Main admitted only the isolated save"): finish(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "compiled C# routing active")
	world.production.no_save = false
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.armor = 0
	world.gameplay._rng.seed = 6102026
	world.gameplay.npc_gunfire.connect(_gunfire)
	world.session.weather.time_of_day = .9
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	raid = world.session.mining.raid
	if not check(is_instance_valid(raid), "production session owns mining raid"): finish(1); return
	if _repopulation_only:
		await _check_repopulation()
		finish(0 if failures.is_empty() else 1)
		return
	if _reentry_only:
		check(raid.completed() and world.session.state.world_state[RAID_STATE.KEY].escaped, "restored checkpoint owns the completed receipt")
		await _check_completed_reentry()
		finish(0 if failures.is_empty() else 1)
		return
	if _vehicle_escape:
		await _check_vehicle_escape()
		finish(0 if failures.is_empty() else 1)
		return
	if not await _enter_gallery(): finish(1); return
	var safe_health: float = world.gameplay.health
	await wait_seconds(1.2)
	check(shots == 0 and not raid.engaged and is_equal_approx(float(world.gameplay.health), safe_health), "entrance is safe from instant hostile fire")
	await photo("raid-safe-entrance")
	if not await _fight_and_take_bag(true): finish(1); return
	if not _escape_only:
		await photo("raid-bag-before-death")
		var before_death: int = world.session.state.economy.balance
		# Deliberate fatal production damage probes the actual death/rescue hook;
		# it is separate from the enemy projectiles already observed above.
		if world.gameplay.god_mode: world.gameplay.toggle_god_mode()
		world.gameplay.damage_environment(1000)
		check(world.gameplay.health <= 0 and not raid.pending_cash and not raid.completed(), "actual fatal damage discards carried money before rescue")
		deadline = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			if world.gameplay.health > 0 and not world.session.rescue_pending and not world.session.respawn_busy and world.session.state.place_id.is_empty(): break
		if not check(world.gameplay.health > 0 and world.session.state.place_id.is_empty() and not world.player.input_locked, "production death presentation and rescue restore exterior controls"): finish(1); return
		check(world.session.state.economy.balance == before_death and not raid.completed(), "death and rescue credit no stolen money")
		await _assert_released("death unload frees all owned guards and corpses")
		# The return to the remote portal is a fixture relocation, not a claim that
		# this test drove the exterior quarry road after rescue.
		world.production.region.set_focus(at)
		world.production.region.prepare_collision_at(at)
		world.player.teleport(at)
		world.camera.initialized = false
		await wait_seconds(1.0)
		if not await _enter_gallery(): finish(1); return
		if not await _fight_and_take_bag(false): finish(1); return
		var before_cancel: int = world.session.state.economy.balance
		raid.cancel()
		check(not raid.pending_cash and not raid.completed() and world.session.state.economy.balance == before_cancel, "explicit cancel hook discards bag without a payout")
		await _assert_released("cancel latch prevents respawn in the same room instance")
		if not await _walk_to_exit(): finish(1); return
		if not check(await world.session.interact(), "cancelled attempt exits through ordinary action"): finish(1); return
		check(world.session.state.economy.balance == before_cancel and not raid.completed(), "leaving a cancelled attempt gives no money")
		if not check(await walk(LAYOUT.SECRET_ENTRY), "physically returns to portal after cancelled escape"): finish(1); return
		if not await _enter_gallery(): finish(1); return
		if not await _fight_and_take_bag(false): finish(1); return
	var before_escape: int = world.session.state.economy.balance
	var before_escape_wallet: Dictionary = world.session.state.economy.snapshot()
	_diagnose("bag-before-exit-walk", before_escape_wallet)
	await photo("raid-ready-to-escape")
	if not await _walk_to_exit(): finish(1); return
	if world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	_diagnose("at-exit-before-transition", before_escape_wallet)
	if not check(await world.session.interact(), "live player exits through the normal room transition"): finish(1); return
	_diagnose("after-live-escape", before_escape_wallet)
	check(world.session.state.place_id.is_empty() and world.player.global_position.distance_to(LAYOUT.SECRET_RETURN) < .6 and world.gameplay.health > 0, "escape reaches actual deep-pit return alive")
	check(raid.ambush and raid.pending_cash and not raid.completed() and world.session.state.economy.balance == before_escape, "gallery exit starts ambush without premature cash receipt")
	check(not world.session.save_block_reason().is_empty(), "exterior ambush retains unsafe-save protection")
	deadline = Time.get_ticks_msec() + 9000
	while raid.actors.size() < 3 and Time.get_ticks_msec() < deadline: await physics_frame
	if not check(raid.actors.size() == 3 and raid.live_count() == 3, "three exterior reinforcements admitted once on supported quarry floor"): finish(1); return
	for guard in raid.actors.values():
		check(guard.get_meta("police_place_id", "wrong") == "" and guard.engaged, "ambushers use exterior visibility and active combat")
	await photo("raid-exterior-ambush")
	if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	# Keep the normal controller and physical ground path around the spoil pile.
	if not check(await walk(LAYOUT.world(Vector3(-24,-28,3))), "walk clear of gallery mouth under ambush"): finish(1); return
	if not await _shoot_guard(0): finish(1); return
	if not check(await walk(LAYOUT.world(Vector3(-17,-28,8))), "flank around fixed mining workstations"): finish(1); return
	if not check(await walk(LAYOUT.world(Vector3(-4,-28,0))), "advance through clear quarry floor"): finish(1); return
	for index in [1,2]:
		if not await _shoot_guard(index): finish(1); return
	await wait_seconds(.5)
	check(not raid.ambush and not raid.pending_cash, "defeating reinforcements completes and cleans exterior encounter")
	if world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	var escaped_wallet: Dictionary = world.session.state.economy.snapshot()
	var haul_receipt: Dictionary = escaped_wallet.transactions.get("reward:"+RAID_STATE.RECEIPT,{})
	var earned_bonus := 0
	for achievement in ["first_grand","shark"]:
		var receipt_key: String = "reward:achievement:"+achievement
		if not before_escape_wallet.transactions.has(receipt_key) and escaped_wallet.transactions.has(receipt_key):
			earned_bonus += int(preload("res://data/catalogs/AchievementCatalog.gd").CASH_REWARDS[achievement])
	check(raid.completed() and haul_receipt.get("amount",0)==RAID_STATE.CASH and world.session.state.economy.balance==before_escape+RAID_STATE.CASH+earned_bonus,"surviving exterior ambush credits one R$12000 receipt plus independently earned achievement bonuses")
	check(is_instance_valid(world.driving.car) and world.driving.car.global_position.y > -1 and preload("res://runtime/FleetState.gd").validate(preload("res://runtime/FleetState.gd").capture(world.driving.car,"desert")),"remote on-foot startup preserves the highway starter car and valid save coordinates")
	check(world.session.state.world_state[RAID_STATE.KEY].escaped, "successful escape publishes persistent raid state")
	await _assert_released("successful departure frees all owned guards and corpses")
	_diagnose("before-explicit-save", before_escape_wallet)
	var saved_ok: bool = world.session.save_game()
	_diagnose("after-explicit-save", before_escape_wallet)
	check(saved_ok, "completed raid writes production isolated save")
	var saved := STORE.read_valid(fixture_path)
	FileAccess.open(output.path_join("disk-after-escape.json"), FileAccess.WRITE).store_string(JSON.stringify(saved, "\t"))
	var restored := GAME_STATE.new()
	check(not saved.is_empty() and restored.restore_snapshot(saved) and restored.economy.has_reward_receipt(RAID_STATE.RECEIPT) and restored.world_state[RAID_STATE.KEY].escaped, "disk restore validates matching escape state and unique receipt")
	if not saved.is_empty():
		var damaged: Dictionary=saved.duplicate(true)
		damaged.economy.transactions["reward:"+RAID_STATE.RECEIPT].amount=1
		check(not GAME_STATE.new().restore_snapshot(damaged),"raid save rejects a receipt with a mismatched payout")
		damaged=saved.duplicate(true)
		damaged.world[RAID_STATE.KEY].escaped=false
		check(not GAME_STATE.new().restore_snapshot(damaged),"raid save rejects a receipt without the completed escape")
	await _check_completed_reentry()
	finish(0 if failures.is_empty() else 1)

func _check_completed_reentry() -> void:
	var paid: int = world.session.state.economy.balance
	# The direct return diagonal clips the parked tractor at (-11,5). Pass
	# south of its rear attachment, then return along the gallery approach.
	for point in [Vector3(-4,-28,13), Vector3(-17,-28,13), Vector3(-24,-28,3), LAYOUT.SECRET_ENTRY-LAYOUT.CENTER]:
		if not check(await walk(LAYOUT.world(point)), "physical completed-raid return " + str(point)): return
	if not check(await world.session.enter_place(COAL.PLACE_ID, false), "completed raid room permits ordinary reentry"): return
	gallery = world.session.room
	await wait_seconds(1.8)
	check(raid.live_count() == 0 and raid.actors.is_empty() and not gallery.model.raid_loot_available, "quick completed reentry suppresses guard respawn and the unique bag")
	check(world.session.state.economy.balance == paid and raid.nearest_action().is_empty(), "reentry cannot duplicate the payout")
	check(not gallery.secret_revealed and gallery.reward_points.is_empty(), "criminal raid does not consume or reveal the independent meteorite secret")
	check(await world.session.leave_place(), "final exit restores normal controls")

func _check_repopulation() -> void:
	check(raid.completed(), "repopulation starts after an already-paid completed raid")
	var wallet: Dictionary = world.session.state.economy.snapshot()
	var near := LAYOUT.SECRET_ENTRY + Vector3.UP * .08
	var far := Vector3(-180, .08, -1540)
	# Fixture moves and deadline advances isolate policy; no claim of driving
	# the quarry route or waiting five wall-clock minutes in this test.
	world.production.region.prepare_collision_at(far)
	world.player.teleport(far)
	await wait_seconds(.5)
	check(not raid._repopulation_ready, "distance alone cannot bypass five-minute cooldown")
	world.production.region.prepare_collision_at(near)
	world.player.teleport(near)
	raid._repopulate_at = Time.get_ticks_msec() / 1000.0 - .01
	await wait_seconds(.5)
	check(not raid._repopulation_ready, "elapsed cooldown cannot repopulate beside the entrance")
	world.player.teleport(far)
	await wait_seconds(.5)
	check(raid._repopulation_ready, "elapsed cooldown plus distant player arms one replacement gang")
	world.production.region.prepare_collision_at(near)
	world.player.teleport(near)
	await wait_seconds(.4)
	if not await _enter_gallery(): return
	check(raid._repeat_visit and not raid._repopulation_ready and not gallery.model.raid_loot_available, "replacement gang enters without restoring the unique cash bag")
	if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	world.session.state.grant_weapon("m4a1")
	world.session.state.add_ammo("m4a1", 100)
	world.session.state.equip_weapon("m4a1")
	if not await _walk_gallery([Vector3(9,0,3), Vector3(16.7,0,3), Vector3(16.7,0,-.5)]): return
	if not await _shoot_guard(1): return
	raid._repopulate_at = Time.get_ticks_msec() / 1000.0 - .01
	await wait_seconds(.6)
	check(raid.live_count() == 3 and raid.actors.size() == 4 and raid.actors[1].dead, "dead replacement guard does not respawn during this same fight")
	check(raid.nearest_action().is_empty() and not raid.pending_cash, "repeat combat has no second campaign bag or cash pending")
	if not await _walk_to_exit(): return
	check(await world.session.leave_place(), "repeat raid exits through real room transition")
	await wait_seconds(2)
	check(raid.ambush and raid._repeat_visit and raid.live_count() == 3, "engaged replacement gang triggers three fresh exterior reinforcements")
	await photo("repeat-ambush")
	world.player.teleport(LAYOUT.SECRET_RETURN + Vector3(60,0,0))
	await wait_seconds(.6)
	check(not raid.ambush and not raid._repeat_visit and not raid._repopulation_ready, "escaping repeat ambush clears it and restarts cooldown")
	var after_wallet: Dictionary = world.session.state.economy.snapshot()
	var receipt_key := "reward:" + RAID_STATE.RECEIPT
	check(after_wallet.transactions.get(receipt_key) == wallet.transactions.get(receipt_key) and int(after_wallet.balance) - int(wallet.balance) < RAID_STATE.CASH, "repeat encounter preserves the unique R$12000 receipt while allowing ordinary enemy drops")
	check(raid._repopulate_at > Time.get_ticks_msec() / 1000.0 + 290, "next replacement wave has a fresh full cooldown")
	check(GAME_STATE.new().restore_snapshot(world.session.state.snapshot()), "save remains compatible after repeated population")
	await _assert_released("repeat departure frees guards and corpses")



func _approach_escape_door(car: CharacterBody3D, target: Vector3) -> bool:
	# The public interaction contract is a clear ray within 1.8m of the door.
	# The old .24m waypoint forced the capsule against the ore stockpile even
	# after the actual door could already be reached through normal interaction.
	var deadline := Time.get_ticks_msec() + 10000
	var option: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		option = world.driving._entry_option()
		if option.get("car") == car: break
		var offset: Vector3 = target - world.player.global_position
		offset.y = 0
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var contacts: Array[Dictionary] = []
	for index in world.player.get_slide_collision_count():
		var collision = world.player.get_slide_collision(index)
		for part in collision.get_collision_count():
			var body: Object = collision.get_collider(part)
			var shape_node: Object
			if body is CollisionObject3D:
				shape_node = body.shape_owner_get_owner(body.shape_find_owner(collision.get_collider_shape_index(part)))
			contacts.append({"body":str(body.get_path()) if body is Node else str(body), "shape":str(shape_node.get_path()) if shape_node is Node else "", "solid":shape_node.get_meta("mining_solid", "") if shape_node is Node else "", "position":str(collision.get_position(part)), "normal":str(collision.get_normal(part))})
	var door_rays: Array[Dictionary] = []
	for side in car.boarding_sides():
		var anchor: Vector3 = car.driver_door_anchor(side)
		var query := PhysicsRayQueryParameters3D.create(world.player.global_position + Vector3.UP * .9, anchor + Vector3.UP * .9, 7, [world.player.get_rid(),car.get_rid()])
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		var obstruction := ""
		if not hit.is_empty() and hit.collider is Node: obstruction = str(hit.collider.get_path())
		door_rays.append({"side":side,"anchor":str(anchor),"gap":anchor.distance_to(world.player.global_position),"obstruction":obstruction})
	var probe := {"player":str(world.player.global_position), "car":str(car.global_position), "yaw":car.rotation.y,"health":car.health,"speed":car.speed,"player_locked":world.player.input_locked,"car_visible":car.is_visible_in_tree(),"car_layer":car.collision_layer,"transition":world.driving.is_body_transition_active(),"door_rays":door_rays, "waypoint":str(target), "door_positive":option.get("car") == car, "gap":option.get("gap", -1), "side":option.get("side", 0), "contacts":contacts}
	print("MINING_RAID_DOOR_PROBE ", JSON.stringify(probe))
	FileAccess.open(output.path_join("escape-door-probe.json"), FileAccess.WRITE).store_string(JSON.stringify(probe, "\t"))
	await photo("raid-bison-door-probe")
	return option.get("car") == car


func _escape_hull_clear(car: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.shape.shape
	query.transform = car.shape.global_transform
	query.collision_mask = 5
	query.exclude = [car.get_rid(), world.player.get_rid()]
	var overlaps: Array[Dictionary] = []
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var body: CollisionObject3D = hit.collider
		# The continuous terrain is supporting contact, not an obstruction.
		if body.get_meta("desert_continuous_ground", false) or body.has_meta("desert_ground_height"): continue
		var shape_node: Object = body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
		overlaps.append({"body":str(body.get_path()), "shape":str(shape_node.get_path()) if shape_node is Node else "", "solid":shape_node.get_meta("mining_solid", "") if shape_node is Node else ""})
	FileAccess.open(output.path_join("escape-hull-probe.json"), FileAccess.WRITE).store_string(JSON.stringify({"point":str(car.global_position), "overlaps":overlaps}, "\t"))
	print("MINING_RAID_HULL_PROBE ", JSON.stringify(overlaps))
	await photo("raid-bison-hull-probe")
	return overlaps.is_empty()

func _check_vehicle_escape() -> void:
	# Diagnostic setup only: prior full run proved real combat, bag pickup and
	# departure. This isolates the alternative exterior payout through driving.
	if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	raid.pending_cash = true
	raid.ambush = true
	raid.engaged = true
	var before_wallet: Dictionary = world.session.state.economy.snapshot()
	check(not raid.completed() and not world.session.save_block_reason().is_empty(), "diagnostic carried-bag fixture blocks saving before vehicle escape")
	var deadline := Time.get_ticks_msec() + 9000
	while raid.live_count() < 3 and Time.get_ticks_msec() < deadline: await physics_frame
	if not check(raid.live_count() == 3, "diagnostic exterior attempt has three live production guards"): return
	var car: CharacterBody3D
	for candidate in world.production.vehicles:
		if is_instance_valid(candidate) and candidate.vehicle_id == "mineradora_escape": car = candidate; break
	if not check(is_instance_valid(car), "persistent Bison escape pickup present"): return
	if not check(await _escape_hull_clear(car), "escape pickup hull is clear of static props and neighboring vehicles"): return
	# Walk around the spoil and western work station to the actual driver's door.
	for point in [Vector3(-24,-28,3), Vector3(-17,-28,8), Vector3(-16,-28,0), Vector3(-16,-28,-5), Vector3(-12,-28,-5)]:
		if not check(await walk(LAYOUT.world(point)), "physical approach to escape pickup " + str(point)): return
	var door: Vector3 = car.driver_door_anchor(1) + car.global_basis.x * .45
	if not check(await _approach_escape_door(car, door), "physical approach offers the real unobstructed Bison door"): return
	if not check(world.driving.interact(), "ordinary door interaction starts Bison boarding"): return
	deadline = Time.get_ticks_msec() + 10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await physics_frame
	if not check(world.driving.occupied and world.driving.car == car and not car.external_input, "player takes control of the actual Bison"): return
	await photo("raid-bison-boarding")
	var start: Vector3 = car.global_position
	var driven := 0.0
	var previous: Vector3 = start
	var trace: Array[Dictionary] = []
	var trace_clock := 0.0
	# The old waypoint at (1.8,-7) delayed the north turn until the nose
	# hit BeltSupport at (3.3,-8.7). Full-hull steering sweep puts the
	# approach waypoint at (-2,-6), with .34m minimum analytical post margin.
	var route := [Vector2(-9,-7), Vector2(-2,-6), Vector2(1.8,-20), Vector2(4,-28), Vector2(11,-34), Vector2(23,-34)]
	var waypoint := 0
	var progress_anchor: Vector3 = car.global_position
	var stalled_seconds := 0.0
	deadline = Time.get_ticks_msec() + 90000
	while not raid.completed() and waypoint < route.size() and Time.get_ticks_msec() < deadline:
		var target := LAYOUT.CENTER + Vector3(route[waypoint].x, 0, route[waypoint].y)
		var offset: Vector3 = target - car.global_position
		offset.y = 0
		if offset.length() < 2.1:
			waypoint += 1
			continue
		var desired := atan2(-offset.x, -offset.z)
		var angle := angle_difference(car.rotation.y, desired)
		var steering := clampf(angle * 2.8, -1.0, 1.0)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if steering > .02: Input.action_press("move_left", steering)
		elif steering < -.02: Input.action_press("move_right", -steering)
		var cruise := 2.1 if absf(angle) > .45 else 3.0
		Input.action_release("accelerate")
		if absf(car.speed) < cruise: Input.action_press("accelerate", .3)
		await physics_frame
		driven += car.global_position.distance_to(previous)
		previous = car.global_position
		trace_clock += 1.0 / float(Engine.physics_ticks_per_second)
		if car.global_position.distance_to(progress_anchor) > .2:
			progress_anchor = car.global_position
			stalled_seconds = 0
		else:
			stalled_seconds += 1.0 / float(Engine.physics_ticks_per_second)
		if stalled_seconds > 5.0:
			print("MINING_RAID_DRIVE_BLOCKED waypoint=", waypoint, " point=", car.global_position)
			break
		if trace_clock >= .5:
			trace_clock = 0
			var contacts: Array[Dictionary] = []
			for index in car.get_slide_collision_count():
				var contact := car.get_slide_collision(index)
				for part in contact.get_collision_count():
					var body: Object = contact.get_collider(part)
					var shape_node: Object
					if body is CollisionObject3D: shape_node = body.shape_owner_get_owner(body.shape_find_owner(contact.get_collider_shape_index(part)))
					contacts.append({"body":str(body.get_path()) if body is Node else str(body), "solid":shape_node.get_meta("mining_solid", str(shape_node.name)) if shape_node is Node else "", "normal":str(contact.get_normal(part))})
			trace.append({"point":str(car.global_position), "speed":car.speed, "waypoint":waypoint, "angle":angle, "contacts":contacts})
	Input.action_release("accelerate")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_press("handbrake")
	await wait_seconds(1)
	Input.action_release("handbrake")
	FileAccess.open(output.path_join("vehicle-escape-trace.json"), FileAccess.WRITE).store_string(JSON.stringify(trace, "\t"))
	print("MINING_RAID_DRIVE point=", car.global_position, " waypoint=", waypoint, " driven=", driven, " portal_distance=", car.global_position.distance_to(LAYOUT.SECRET_RETURN))
	check(driven > 35 and car.global_position.distance_to(LAYOUT.SECRET_RETURN) >= raid.ESCAPE_DISTANCE, "ordinary throttle and steering physically escape the ambush perimeter")
	check(raid.completed() and not raid.pending_cash and not raid.ambush, "vehicle escape secures the carried haul and ends the ambush")
	var wallet: Dictionary = world.session.state.economy.snapshot()
	check(not before_wallet.transactions.has("reward:" + RAID_STATE.RECEIPT) and wallet.transactions.get("reward:" + RAID_STATE.RECEIPT, {}).get("amount", 0) == RAID_STATE.CASH, "vehicle branch credits the same unique R$12000 receipt")
	await photo("raid-bison-escaped")
	if not check(world.driving.leave(), "ordinary Bison disembark starts after vehicle escape"): return
	deadline = Time.get_ticks_msec() + 10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await physics_frame
	await frames(12)
	check(not world.driving.occupied and not world.player.input_locked and world.player.is_on_floor(), "escape disembark restores pedestrian controls on supported ground")
	check(world.session.position_clear(world.player.global_position), "escape disembark preserves full capsule clearance")
	await photo("raid-bison-disembarked")

func finish(code: int) -> void:
	if _finished: return
	_finished = true
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	Input.action_release("move_left")
	Input.action_release("move_right")
	if not output.is_empty():
		if _repopulation_only:
			FileAccess.open(output.path_join("repopulation-fixture.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":"repopulation-only", "note":"Real Main guards, damage, room transitions and cleanup. Completed reward is seeded, deadlines advanced and exterior positions relocated to isolate cooldown/distance policy; no five-minute wall-clock wait or physical exterior escape claim."}, "\t"))
		FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "enemy_shots": shots, "unprotected_player_damage": player_damage, "escape_only": _escape_only, "reentry_only": _reentry_only, "vehicle_escape_diagnostic": _vehicle_escape, "resume_snapshot": _resume_snapshot, "diagnostics_file": output.path_join("diagnostics.json"), "rendered": DisplayServer.get_name() != "headless", "engine": Engine.get_version_info().string, "note": ("DIAGNOSTIC: carried bag and exterior ambush state injected; normal on-foot door approach, boarding, player throttle/steering, physical escape and receipt verified. Does not replay prior combat or bag pickup." if _vehicle_escape else "Real Main, normal interior walking and weapons. God mode used after proving enemy damage to isolate repeated lifecycle cases. Full mode additionally probes fatal production damage/death/rescue and the explicit cancel latch; --escape-only skips only those two attempts. Exterior placements are fixtures, not quarry-road traversal. No performance approval.")}, "\t"))
	print("MINING_RAID checks=", checks, " failures=", failures.size(), " evidence=", output)
	quit(code)
