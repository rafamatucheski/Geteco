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
	while not guard.dead and Time.get_ticks_msec() < deadline:
		world.gameplay.aim_point = guard.global_position + Vector3.UP
		if world.gameplay.fire_at(guard.global_position + Vector3.UP): accepted += 1
		await physics_frame
	if not guard.dead:
		print("MINING_RAID_FIRE_BLOCKED guard=", index, " player=", gallery.to_local(world.player.global_position), " target=", gallery.to_local(guard.global_position), " accepted=", accepted, " health=", guard.health)
	return check(guard.dead and accepted > 0 and guard.collision_layer == 0, "real player gunfire defeats guard " + str(index))

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
	root.size = Vector2i(1280, 720)
	output = FIXTURE.output_dir("mining-raid")
	var at := LAYOUT.SECRET_ENTRY + Vector3.UP * .08
	var snapshot := FIXTURE.full_snapshot(at, true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region": "desert", "position": [at.x, at.y, at.z]}
	snapshot.world[RAID_STATE.KEY] = RAID_STATE.defaults()
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
	var escaped_wallet: Dictionary = world.session.state.economy.snapshot()
	var haul_receipt: Dictionary = escaped_wallet.transactions.get("reward:"+RAID_STATE.RECEIPT,{})
	var earned_bonus := 0
	for achievement in ["first_grand","shark"]:
		var receipt_key: String = "reward:achievement:"+achievement
		if not before_escape_wallet.transactions.has(receipt_key) and escaped_wallet.transactions.has(receipt_key):
			earned_bonus += int(preload("res://data/catalogs/AchievementCatalog.gd").CASH_REWARDS[achievement])
	check(raid.completed() and haul_receipt.get("amount",0)==RAID_STATE.CASH and world.session.state.economy.balance==before_escape+RAID_STATE.CASH+earned_bonus,"live escape credits one R$12000 receipt plus independently earned achievement bonuses")
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
	var paid: int = world.session.state.economy.balance
	if not check(await walk(LAYOUT.SECRET_ENTRY), "walks back to the same access for completed-state check"): finish(1); return
	if not check(await world.session.enter_place(COAL.PLACE_ID, false), "completed raid room permits ordinary reentry"): finish(1); return
	gallery = world.session.room
	await wait_seconds(1.8)
	check(raid.live_count() == 0 and raid.actors.is_empty() and not gallery.model.raid_loot_available, "completed state suppresses guard and bag replenishment")
	check(world.session.state.economy.balance == paid and raid.nearest_action().is_empty(), "reentry cannot duplicate the payout")
	check(not gallery.secret_revealed and gallery.reward_points.is_empty(), "criminal raid does not consume or reveal the independent meteorite secret")
	check(await world.session.leave_place(), "final exit restores normal controls")
	finish(0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	if _finished: return
	_finished = true
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	if not output.is_empty():
		FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "enemy_shots": shots, "unprotected_player_damage": player_damage, "escape_only": _escape_only, "diagnostics_file": output.path_join("diagnostics.json"), "rendered": DisplayServer.get_name() != "headless", "engine": Engine.get_version_info().string, "note": "Real Main, normal interior walking and weapons. God mode used after proving enemy damage to isolate repeated lifecycle cases. Full mode additionally probes fatal production damage/death/rescue and the explicit cancel latch; --escape-only skips only those two attempts. Exterior placements are fixtures, not quarry-road traversal. No performance approval."}, "\t"))
	print("MINING_RAID checks=", checks, " failures=", failures.size(), " evidence=", output)
	quit(code)
