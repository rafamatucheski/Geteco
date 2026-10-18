extends SceneTree
## Main integration: actual player gunfire, service-vault theft, guard projectiles,
## convoy radio, production police dispatch and natural death/loot forfeiture.
## The player alone is positioned at a collision-checked rear access for setup.
## No convoy/guard is teleported, disabled, killed or replaced by this test.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
const TRANSPORT := preload("res://gameplay/armored/ArmoredTransport.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const ACHIEVEMENTS := preload("res://data/catalogs/AchievementCatalog.gd")
var world
var convoy
var folder := ""
var origin := "harbor_bank"
var checks := 0
var failures: Array[String] = []
var _finished := false
var _guard_shots := 0
var _player_shots := 0
var _radio_reports := 0
var _death_observed := false
var _police_observed := false
var _police_motion := 0.0
var _police_previous: Dictionary = {}
var _worst_player_health := 100.0
var _last_trace := 0

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): check(false, "bounded Main combat watchdog"); finish(3))
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("ARMORED_COMBAT_SESSION ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _npc_fire(_point: Vector3, _direction: Vector3, shooter: Node3D) -> void:
	if is_instance_valid(convoy) and convoy.guards.has(shooter): _guard_shots += 1

func _player_fire(_weapon: String, _point: Vector3) -> void:
	_player_shots += 1

func _reported(points: int) -> void:
	# The authored first alarm contributes 90. Gunfire testimony is capped at 4.
	if points >= 90: _radio_reports += 1

func _trace(label: String) -> void:
	if not is_instance_valid(world) or not is_instance_valid(convoy): return
	var row := {"label":label, "phase":convoy.data.get("phase", "none"),
		"hostile":convoy.data.get("hostile", false), "reported":convoy.data.get("reported", false),
		"radio_left":convoy.data.get("report_remaining", -1), "future_security":convoy.security_level,
		"health":world.gameplay.health, "armor":world.gameplay.armor, "stars":world.gameplay.stars,
		"pending":convoy.data.get("pending", 0), "fleet":convoy.fleet.size(),
		"guard_shots":_guard_shots, "player_shots":_player_shots,
		"police":world.dispatch.status(), "point":str(world.player.global_position)}
	print("ARMORED_COMBAT_TRACE ", JSON.stringify(row))

func _observe_police() -> void:
	for unit in world.dispatch.units:
		if not unit.is_police() or not is_instance_valid(unit.vehicle): continue
		_police_observed = true
		var id: int = unit.vehicle.get_instance_id()
		var point: Vector3 = unit.vehicle.global_position
		if _police_previous.has(id): _police_motion += point.distance_to(_police_previous[id])
		_police_previous[id] = point

func _rear_setup() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for truck_index in mini(2, convoy.fleet.size()):
		var truck: CharacterBody3D = convoy.fleet[truck_index]
		if absf(truck.speed) > .3: continue
		var rear: Vector3 = truck.global_basis.z
		var side: Vector3 = truck.global_basis.x
		for lateral in [0.0, .5, -.5]:
			var point: Vector3 = truck.door_point() + rear * .7 + side * lateral
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN * 2.0, 1))
			if floor_hit.is_empty() or floor_hit.normal.y < .7: continue
			point.y = floor_hit.position.y + .08
			if not world.session.position_clear(point): continue
			for actor in convoy.guards:
				if not is_instance_valid(actor) or actor.dead: continue
				if actor.global_position.distance_to(point) > 18: continue
				var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.2, actor.global_position + Vector3.UP, 7, [world.player.get_rid()])
				var hit := space.intersect_ray(query)
				if hit.is_empty() or hit.collider == actor:
					return {"point":point, "guard":actor, "truck":truck_index,
						"retreat":point + side * (8.0 if lateral >= 0 else -8.0) + rear * 5.0}
	return {}

func _persist_diagnostic() -> void:
	# A separate evidence store validates the live state; this does not bypass
	# FullSession's prohibition on player checkpoints while carrying stolen cash.
	var store := STORE.new()
	store.path = folder.path_join("live-state-diagnostic.json")
	if not check(store.path != STORE.PATH and store.save(world.session.state) == OK, "live convoy snapshot serializes to an isolated diagnostic file"): return
	var restored := STATE.new()
	if not check(store.load_into(restored).get("ok", false), "diagnostic checkpoint restores through the production SaveStore"): return
	var replay := TRANSPORT.new()
	replay.configure({"state":restored})
	check(replay.security_level == 1 and replay.data.security_level == 0 and replay.data.escalated,
		"disk restoration preserves next-trip security without upgrading the current crew twice")
	var next := SCHEDULE.initial(SCHEDULE.departure(3, 14.0 / 24.0), replay.security_level)
	check(SCHEDULE.security(next.security_level).road_report_delay < SCHEDULE.security(0).road_report_delay,
		"restored security makes the next departure report sooner")
	replay.free()

func _verify_failed_wallet(before: Dictionary) -> void:
	var wallet = world.session.state.economy
	var after: Dictionary = wallet.snapshot()
	var armored_receipts: Array[bool] = []
	for index in 2:
		armored_receipts.append(wallet.has_reward_receipt("armored:%s:truck:%d" % [convoy.data.id, index]))
	var new_transactions: Dictionary = {}
	var achievement_income := 0
	for key in after.transactions:
		if before.transactions.has(key): continue
		var receipt: Dictionary = after.transactions[key]
		new_transactions[key] = receipt
		if str(key).begins_with("reward:achievement:"):
			var achievement := str(key).trim_prefix("reward:achievement:")
			if ACHIEVEMENTS.CASH_REWARDS.has(achievement) and receipt.kind == "reward" and int(receipt.amount) == int(ACHIEVEMENTS.CASH_REWARDS[achievement]):
				achievement_income += int(receipt.amount)
	var delta := int(after.balance) - int(before.balance)
	var evidence := {"before":before, "after":after, "new_transactions":new_transactions,
		"balance_delta":delta, "achievement_income":achievement_income,
		"armored_receipts":armored_receipts, "convoy":convoy.data.duplicate(true)}
	FileAccess.open(folder.path_join("wallet-settlement-diagnostic.json"), FileAccess.WRITE).store_string(JSON.stringify(evidence, "\t"))
	print("ARMORED_WALLET_TRACE ", JSON.stringify({"before":before.balance, "after":after.balance,
		"delta":delta, "achievement_income":achievement_income, "new_transactions":new_transactions,
		"armored_receipts":armored_receipts}))
	check(armored_receipts == [false, false] and convoy.data.secured == [false, false], "failed robbery creates no truck reward receipt or secured cargo")
	# Wanted level 3 legitimately awards 'most_wanted' (R$100) during this
	# confrontation. Reconcile that independent source instead of banning income.
	check(delta == achievement_income, "wallet increase is exactly the unrelated achievement rewards, with no stolen cargo credit")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--desert" in OS.get_cmdline_user_args(): origin = "desert_bank"
	seed(7102026)
	folder = FIXTURE.output_dir("armored-combat-" + origin)
	var bank: Vector3 = PLACES.get_definition(origin).entry_position
	var point := bank + Vector3(4, .08, 1)
	var snapshot := FIXTURE.full_snapshot(point, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var region := "desert" if origin == "desert_bank" else "harbor"
	snapshot.region_id = region
	snapshot.world.pedestrian = {"region":region, "position":[point.x, point.y, point.z]}
	snapshot.world.moon_day = 3 if region == "desert" else 1
	snapshot.world.time = (14.0 if region == "desert" else 9.0) / 24.0
	var path := FIXTURE.write_fixture(folder, "checkpoint.json", snapshot)
	if not check(not path.is_empty(), "isolated post-finale scheduled checkpoint accepted"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if not check(world.session != null and world.session.ready_for_play and not world.production.save_invalid, "Main starts with the valid isolated checkpoint"): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	check(world.production.store.path == path and world.production.no_save, "personal saves remain disabled and the selected store is isolated")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(point)
	for index in 3: await physics_frame
	if session.position_clear(point): world.player.teleport(point)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null and world.dispatch.enabled and world.gameplay.dispatch_owned, "compiled C# routing and production police dispatch are active")
	convoy = session.armored_transport
	deadline = Time.get_ticks_msec() + 45000
	var rear_setup: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if convoy.fleet.size() == 4 and convoy.guards.size() >= 6 and convoy.data.phase == "loading":
			rear_setup = _rear_setup()
			if not rear_setup.is_empty(): break
	if not check(not rear_setup.is_empty(), "scheduled convoy admits real crew and a clear witnessed rear access"): _trace("admission-failed"); finish(1); return
	check(not convoy.data.hostile and world.gameplay.stars == 0, "legal observation leaves guards and police neutral")
	world.player.teleport(rear_setup.point)
	world.camera.initialized = false
	# Ordinary starting equipment, set once. No invulnerability, healing, damage
	# suppression or regeneration is used during the confrontation.
	world.gameplay.armor = 100
	session.state.grant_weapon("pistol")
	session.state.add_ammo("pistol", 36)
	if not check(session.state.equip_weapon("pistol"), "fixture equips a normal pistol and finite starting body armor"): finish(1); return
	world.gameplay.npc_gunfire.connect(_npc_fire)
	world.gameplay.weapon_fired.connect(_player_fire)
	world.gameplay.crime_reported.connect(_reported)
	world.gameplay.player_died.connect(func(): _death_observed = true)
	for index in 3: await physics_frame
	await photo("before-attack")
	var target: CharacterBody3D = rear_setup.guard
	var fired := false
	deadline = Time.get_ticks_msec() + 3000
	while is_instance_valid(target) and Time.get_ticks_msec() < deadline:
		fired = world.gameplay.fire_at(target.global_position + Vector3.UP)
		if fired: break
		await physics_frame
	if not check(fired and _player_shots > 0, "normal Gameplay.fire_at emits real player gunfire beside the convoy"): _trace("fire-blocked"); finish(1); return
	await physics_frame
	check(target.health < float(convoy.profile.guard_health), "real player bullet damages the visible transport guard")
	if not check(convoy.data.hostile and convoy.security_level == 1 and convoy.data.security_level == 0, "actual gunfire alarms the convoy and escalates only future trips"): finish(1); return
	var wallet_before: int = session.state.economy.balance
	var economy_before: Dictionary = session.state.economy.snapshot()
	if not check(session.nearest().get("id", "") == "armored_transport", "ordinary session interaction selects the exposed service vault"): _trace("vault-unreachable"); finish(1); return
	check(await session.interact(), "ordinary E interaction takes the service cash under live threat")
	check(convoy.data.pending == SCHEDULE.CASH_PER_TRUCK and session.state.economy.balance == wallet_before, "one truck stays unsecured while the armed response is active")
	check(not session.save_block_reason().is_empty() and not session.save_game(), "production checkpoint writes are refused while carrying the money")
	_persist_diagnostic()
	await photo("robbery")
	var initial_health: float = world.gameplay.health
	var combat_started := Time.get_ticks_msec()
	var second_shot := false
	deadline = combat_started + 65000
	while Time.get_ticks_msec() < deadline and not _death_observed:
		await physics_frame
		_observe_police()
		_worst_player_health = minf(_worst_player_health, world.gameplay.health)
		# A short ordinary retreat gives the convoy and real dispatcher time to
		# react. Collision resolves every step; this is not an escape certificate.
		var offset: Vector3 = rear_setup.retreat - world.player.global_position
		offset.y = 0
		world.player.automatic_direction = offset.normalized() if Time.get_ticks_msec() - combat_started < 5000 and offset.length() > .35 else Vector3.ZERO
		if not second_shot and is_instance_valid(target) and not target.dead and world.gameplay.cooldown <= 0:
			second_shot = world.gameplay.fire_at(target.global_position + Vector3.UP)
		if Time.get_ticks_msec() - _last_trace > 10000:
			_last_trace = Time.get_ticks_msec()
			_trace("combat")
	world.player.automatic_direction = Vector3.ZERO
	for index in 2: await physics_frame
	_observe_police()
	check(_guard_shots >= 2 and _worst_player_health < initial_health, "live security projectiles injure the unprotected-by-cheats player")
	check(convoy.data.reported and _radio_reports == 1, "convoy radio registers exactly one high-value alarm in the real crime system")
	check(_police_observed and _police_motion > 1.0, "production police spawns and physically drives in response without manual dispatch")
	check(second_shot and convoy.security_level == 1 and convoy.data.security_level == 0, "repeat real player shots do not multiply security escalation")
	check(_death_observed, "continuing the confrontation can kill Dante through real combat")
	if _death_observed:
		check(convoy.data.phase == "finished" and convoy.data.pending == 0 and convoy.fleet.is_empty() and convoy.guards.is_empty(), "death closes the event and releases its finite convoy without retaining stolen cash")
		_verify_failed_wallet(economy_before)
		check(SCHEDULE.valid_saved(session.state.world_state.get(SCHEDULE.KEY, {})), "failed live event retains a valid persistent escalation record")
	_trace("result")
	await photo("result")
	finish(0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	if _finished: return
	_finished = true
	print("ARMORED_COMBAT_SESSION_RESULT ", JSON.stringify({"checks":checks, "failures":failures,
		"evidence":folder, "origin":origin, "guard_shots":_guard_shots, "police_motion":_police_motion}))
	if is_instance_valid(world): world.queue_free()
	quit(code)
