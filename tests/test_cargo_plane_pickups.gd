extends SceneTree
## Real Main/.NET plane: approach audio, physical cash/SMG collection and save
## receipts. --no-save is mandatory; disk evidence has a unique isolated path.
## Playing voices prove routing/lifecycle, not a human listening review or FPS.
const PLANE := preload("res://world/places/CargoPlaneNative.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(150).timeout.connect(func(): push_error("CARGO_PLANE_PICKUPS timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CARGO_PLANE_PICKUPS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func walk(target: Vector3) -> bool:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 10000:
		var direction: Vector3 = target - world.player.global_position
		direction.y = 0.0
		if direction.length() < .16:
			world.player.automatic_direction = Vector3.ZERO
			await frames(4)
			return world.player.is_on_floor()
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	print("CARGO_PLANE_PICKUPS blocked=", world.player.global_position, " target=", target)
	return false

func reward_stamp(kind: String) -> int:
	var pool: Node = world.get_node_or_null("RewardAudioVoices")
	return int(pool.get_meta("last_" + kind, -1000)) if pool != null else -1000

func treasure_footprint_clear(plane: Node3D) -> bool:
	# Probe the authored chest volume above the deck; layer 1 excludes the actor.
	# A hidden chest must leave neither its centre nor its corners blocked.
	for x in [.25, .55, .85]:
		for z in [-7.56, -7.35, -7.15]:
			var from := plane.to_global(Vector3(x, .26, z))
			var to := plane.to_global(Vector3(x, 2.2, z))
			var query := PhysicsRayQueryParameters3D.create(from, to, 1)
			query.hit_from_inside = true
			if not plane.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return false
	return true

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save --skip-arrival and isolated user-data directories.")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "actual .NET Main starts")
	if not failures.is_empty(): await finish(); return
	var session = world.session
	check(world.production.no_save, "personal saves are protected")
	var origin := DEFINITIONS.at(Vector2(5450, -1150), "mountain")
	check(world.production.travel("mountain", origin + Vector3(0, 0, 10.0)), "production travel reaches the plane site")
	for index in 1200:
		await physics_frame
		if not world.production.travel_busy and session.ready_for_play: break
	check(session.state.region_id == "mountain" and not world.production.travel_busy, "mountain transition completes")
	if not failures.is_empty(): await finish(); return
	await frames(90)
	var plane
	for source in get_nodes_in_group("native_world_rewards"):
		if source.get_script() == PLANE: plane = source; break
	check(is_instance_valid(plane) and plane.reward_points.size() == 2, "streamed aircraft owns exactly its cash and SMG rewards")
	if not failures.is_empty(): await finish(); return
	var cash = plane.model.get_node("TreasurePickup")
	var weapon = plane.model.get_node("SmgPickup")
	check(cash.proximity_audio_enabled and weapon.proximity_audio_enabled, "both aircraft rewards have proximity audio enabled")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.0
	check(await walk(plane.to_global(Vector3(.1, 0, 1.0))), "Dante enters the ramp and reaches the clear cargo aisle")
	await create_timer(1.6).timeout
	check(is_instance_valid(cash.proximity_voice) and int(cash.proximity_voice.get_meta("cue_count", 0)) > 0, "treasure emits a real proximity voice")
	check(is_instance_valid(weapon.proximity_voice) and int(weapon.proximity_voice.get_meta("cue_count", 0)) > 0, "SMG emits a real proximity voice")
	if is_instance_valid(cash.proximity_voice):
		check(cash.proximity_voice.stream == REWARD_AUDIO.stream("collectible") and cash.proximity_voice.bus == REWARD_AUDIO.AUDIO.SFX_BUS_NAME, "approach cue reuses the original collectible sample and SFX route")
	if not failures.is_empty(): await finish(); return
	var balance_before: int = session.state.economy.balance
	var cash_before := reward_stamp("cash")
	check(await walk(plane.to_global(Vector3(.45, 0, -6.25))), "Dante physically approaches the treasure on the clear side")
	await frames(25)
	check(session.state.economy.balance == balance_before + 1800, "treasure grants its authored R$ 1800 once")
	check(reward_stamp("cash") > cash_before, "actual collection plays the existing cash reward cue")
	check(cash.consumed and not cash.visible and not cash.proximity_voice.playing, "collected treasure stops proximity audio and finishes absorption")
	check(treasure_footprint_clear(plane), "collected treasure leaves its physical footprint free")
	check(await walk(plane.to_global(Vector3(.55, 0, -7.35))), "Dante walks through the collected treasure's former space")
	var weapon_before := reward_stamp("weapon")
	check(await walk(plane.to_global(Vector3(-.5, 0, -6.95))), "Dante reaches the SMG through the free aisle")
	await frames(25)
	check(session.state.owns_weapon("smg") and reward_stamp("weapon") > weapon_before, "SMG ownership and existing weapon reward cue are published together")
	check(weapon.consumed and not weapon.visible and not weapon.proximity_voice.playing, "collected SMG stops proximity audio and finishes absorption")
	var saved_economy: Dictionary = session.state.economy.snapshot()
	var saved_markers: Array = session.state.world_state.rewards.duplicate()
	var store := STORE.new()
	store.path = "res://evidence/cargo-plane/reward-save-%d.json" % Time.get_ticks_usec()
	check(store.save(session.state) == OK, "actual reward state saves to an isolated disk path")
	var loaded := STATE.new()
	check(store.load_into(loaded).get("ok", false), "reward state loads through the production SaveStore")
	for point in plane.reward_points:
		check(loaded.world_state.rewards.has(point.id) and loaded.economy.has_reward_receipt(point.id), "marker and receipt survive load: " + str(point.id))
		var retry: Dictionary = loaded.economy.grant_world_reward(point.reward)
		check(retry.ok and not retry.changed, "restored receipt rejects a second grant: " + str(point.id))
	var old_cash_stamp := reward_stamp("cash")
	var old_weapon_stamp := reward_stamp("weapon")
	check(store.load_into(session.state).get("ok", false), "collected state restores into the live GameState")
	session._collect_reward(plane)
	await frames(20)
	check(treasure_footprint_clear(plane), "save reconciliation keeps the chest footprint physically free")
	check(await walk(plane.to_global(Vector3(.55, 0, -7.35))), "Dante crosses the former chest space after restore and reconciliation")
	check(session.state.economy.snapshot() == saved_economy and reward_stamp("cash") == old_cash_stamp and reward_stamp("weapon") == old_weapon_stamp, "reward reconciliation neither pays nor plays collection sounds again")
	check(session.state.world_state.rewards == saved_markers, "reconciliation leaves persisted reward markers unchanged")
	await finish()

func finish() -> void:
	print("CARGO_PLANE_PICKUPS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	quit(0 if failures.is_empty() else 1)
