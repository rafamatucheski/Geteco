extends SceneTree
## Real Main integration: port guard interaction, payment, physical gate and saved visits.
const URBAN := preload("res://gameplay/urban_v1/UrbanOperations.gd")
const STATE := preload("res://runtime/GameState.gd")
const GATE := Vector3(3310.0 / 16.0, .08, 3380.0 / 16.0)
const GUARD := Vector3(3390.0 / 16.0, .08, 3340.0 / 16.0)
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("VIDEO_PHASE2_PORT ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func place(point: Vector3) -> void:
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(point)
	for _i in 180:
		await physics_frame
		if world.production.region.prepare_collision_at(point): break
	world.player.teleport(point)
	await frames(12)

func walk_to(point: Vector3, limit: int = 210) -> bool:
	for _i in limit:
		var offset: Vector3 = point - world.player.global_position
		offset.y = 0
		if offset.length() < .18:
			world.player.automatic_direction = Vector3.ZERO
			await frames(8)
			return true
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	print("PORT_WALK stopped=", world.player.global_position, " target=", point)
	for index in world.player.get_slide_collision_count():
		var slide: KinematicCollision3D = world.player.get_slide_collision(index)
		var body: Object = slide.get_collider()
		print("PORT_WALK_SLIDE ", body.get_path() if body is Node else body, " normal=", slide.get_normal())
	return false

func payment_button() -> Button:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with("Pagar propina"): return child
	return null

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save --skip-arrival; never use the personal save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "real session ready")
	if not failures.is_empty():
		quit(1)
		return
	var session = world.session
	var state = session.state
	var operations = session.urban_operations
	var security = operations.security
	check(world.production.no_save, "personal save isolated")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.input_locked = false
	world.player.speed = 3.5
	# First prove the closed physical boom prevents entering through its center.
	await place(GATE + Vector3(0, 0, -1.3))
	check(not security.gate_open, "unpaid gate starts closed")
	world.player.automatic_direction = Vector3.BACK
	await frames(65)
	world.player.automatic_direction = Vector3.ZERO
	check(world.player.global_position.z < GATE.z and not security.was_inside, "closed gate blocks actual player movement")
	check(world.player.is_on_floor(), "approach has physical floor support")
	await place(GUARD + Vector3(0, 0, .8))
	var action: Dictionary = session.nearest()
	check(action.get("target") == "south_port_checkpoint" and action.get("label") == "Conversar", "real session selects the nearby port guard")
	check(session.interact() and session.modal, "normal interaction opens portaria menu")
	var pay := payment_button()
	check(pay != null, "menu exposes payment action")
	if pay == null:
		await finish()
		return
	check(state.spend(state.economy.balance, "video_phase2_empty_wallet"), "fixture empties wallet through economy")
	pay.pressed.emit()
	check(state.economy.balance == 0 and not security.authorized_entry and not security.gate_open, "insufficient funds do not authorize or open gate")
	check(session.modal, "insufficient funds keep conversation available")
	check(state.economy.grant_reward("video_phase2_funds", 500), "fixture funds accepted")
	pay.pressed.emit()
	check(state.economy.balance == 400 and security.authorized_entry and not session.modal, "payment debits R$100 and authorizes entry")
	pay.pressed.emit()
	check(state.economy.balance == 400, "duplicate payment signal cannot debit twice")
	var paid: Dictionary = state.world_state.get("urban_operations", {}).duplicate(true)
	check(paid.get("security", {}).get("authorized_entry", false), "accepted payment immediately enters saved state")
	# JSON round-trip through the complete GameState validator, then the production adapter.
	var restored = STATE.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(state.snapshot()))), "paid full save survives serialization and validation")
	var legacy: Dictionary = paid.duplicate(true)
	legacy.erase("security")
	check(operations.restore_snapshot(legacy) and not security.authorized_entry, "legacy urban save restores without phantom authorization")
	check(operations.restore_snapshot(restored.world_state.urban_operations) and security.authorized_entry, "paid entry permission restores through real adapter")
	check(state.economy.balance == 400, "restoration never charges again")
	var saved_position: Vector3 = world.player.global_position
	session.ready_for_play = false
	world.player.teleport(Vector3.ZERO)
	security._process(.2)
	check(security.authorized_entry and not security.initialized, "startup before saved location admission cannot revoke paid entry")
	world.player.teleport(saved_position)
	session.ready_for_play = true
	restored = null
	# Reject all security errors before mutating any other urban subsystem.
	var stable: Dictionary = operations.snapshot()
	var malformed: Array = [null, {}, {"version":1,"authorized_entry":"yes","authorized_visit":false,"exiting_port":false}, {"version":1,"authorized_entry":true,"authorized_visit":true,"exiting_port":false}]
	for index in malformed.size():
		var bad: Dictionary = stable.duplicate(true)
		bad.security = malformed[index]
		bad.cemetery.serial = int(bad.cemetery.serial) + 1
		check(not operations.restore_snapshot(bad) and operations.snapshot() == stable, "invalid checkpoint snapshot %d rejected before partial restore" % index)
	await frames(12)
	check(security.gate_open and security._gate_parts.all(func(part): return part.collision.disabled), "restored authorization opens boom and collision")
	check(await walk_to(GATE + Vector3(0, 0, -1.3)), "guard is reachable from the gate approach")
	var crime_before: float = world.gameplay.crime_points
	check(await walk_to(GATE + Vector3(0, 0, 3.1)), "authorized player physically walks through the gate")
	check(security.authorized_visit and not security.authorized_entry and not security.alerted, "crossing consumes entry into one authorized visit")
	check(world.gameplay.crime_points <= crime_before, "authorized passage adds no crime")
	check(session.save_game(), "save accepts active port visit")
	var visit: Dictionary = state.world_state.urban_operations.duplicate(true)
	check(operations.restore_snapshot(visit), "active visit restores")
	await frames(12)
	check(security.authorized_visit and security.gate_open and not security.alerted, "restored visitor remains authorized inside")
	# Building transitions must not consume the visit; the hold already provides useful content.
	check(await session.enter_place("santa_mare_hold", false), "existing cargo hold remains enterable")
	await frames(8)
	check(security.authorized_visit, "entering a port building preserves the visit")
	check(session.room != null and session.room.reward_points.size() == 1, "existing hold exposes its persistent R$2800 treasure")
	check(session.leave_place(), "cargo hold returns to the exterior")
	await frames(12)
	check(security.authorized_visit, "return from port building remains authorized")
	check(security._inside_security_zone(world.player.global_position), "ship deck belongs to the same secured visit")
	# Workers use the center lane; use the free side of the four-metre gangway.
	# Both capsules retain their collision, and every segment is real movement.
	var deck_lane: bool = await walk_to(Vector3(266.4, .08, 192.0), 120)
	var reached_quay: bool = deck_lane and await walk_to(Vector3(266.4, .08, 3260.0/16.0), 250)
	check(reached_quay, "player physically walks from hold exit across gangway to quay")
	check(security.authorized_visit and not security.alerted, "deck and gangway return to quay without a false invasion")
	for point in [Vector3(6200.0/16.0,0,3700.0/16.0), Vector3(6200.0/16.0,0,4260.0/16.0)]:
		check(security._inside_security_zone(point), "authored loading pier remains part of the visit")
	check(not security._inside_security_zone(Vector3(6400.0/16.0,0,4000.0/16.0)), "open sea is not added to port authorization area")
	await place(GATE + Vector3(0, 0, 3.1))
	check(await walk_to(GATE + Vector3(0, 0, -1.8)), "authorized visit can physically leave the port")
	await frames(12)
	check(not security.authorized_visit and not security.authorized_entry and not security.exiting_port, "leaving to the public road ends the paid visit")
	check(not security.gate_open, "gate closes behind the departing player")
	await place(GATE + Vector3(5.5, 0, 3.1))
	check(security.alerted and world.gameplay.crime_points > crime_before, "new unpaid perimeter crossing still alerts security")
	# The port authorization must not override the separate restricted garage schedule.
	for hour in [.99, 1.0, 4.999, 5.0, 12.0]:
		state.world_state.time = hour / 24.0
		check(session.garage_rewards.can_enter("port_boss_garage") == (hour >= 1.0 and hour < 5.0), "boss garage preserves 1–5h schedule at %.3f" % hour)
	await finish()

func finish() -> void:
	print("VIDEO_PHASE2_PORT checks=", checks, " failures=", failures.size())
	if is_instance_valid(world): world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)
