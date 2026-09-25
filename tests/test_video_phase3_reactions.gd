extends SceneTree
## Causal Main regression: real gunfire/fire, physical retreat, service interruption
## and recovery, without touching the personal save or protected garage residents.
const REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
var world
var checks := 0
var failures: Array[String] = []
class ScopeGameplay extends Node:
	signal weapon_fired(weapon_id: String, origin: Vector3)
	signal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(origin: Vector3, radius: float, source: Node)
	var state := {"place_id":"maciota"}

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("REACTION_TEST timeout"); quit(3))
	if "--scope-only" in OS.get_cmdline_user_args(): scope_test.call_deferred()
	else: run.call_deferred()
func frames(count: int) -> void:
	for _i in count: await physics_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	print("VIDEO_PHASE3_REACTIONS ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func place(point: Vector3) -> void:
	world.production.region.set_focus(point)
	for _i in 180:
		await physics_frame
		if world.production.region.prepare_collision_at(point): break
	world.player.teleport(point)
	await frames(12)
func shoot_away() -> bool:
	world.session.state.equip_weapon("pistol")
	world.gameplay.cooldown = 0
	return world.gameplay.fire_at(world.player.global_position + Vector3(-8, 0, 0))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main session ready")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	# Isolate cessation of danger: skip_dispatch alone leaves legacy police active.
	# Actual initiating shots and NPC-gunfire events remain connected and exercised.
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.input_locked = false
	session.weather.time_of_day = .45
	session.state.grant_weapon("pistol")
	if "--cargo-only" in OS.get_cmdline_user_args():
		await cargo_probe(session)
		await finish()
		return
	if "--remaining-only" in OS.get_cmdline_user_args():
		await remaining(session)
		await finish()
		return
	var security = session.urban_operations.security
	var staff: Node3D = security._staff[0]
	await place(staff.global_position + Vector3(0, .08, 1))
	var reaction: Node = staff.get_node_or_null("WorkplaceThreatReaction")
	check(reaction != null, "port staff connected to threat events")
	check(security.nearest_action().get("target") == "south_port_checkpoint", "port staff serves before danger")
	var original_position := staff.global_position
	check(shoot_away(), "real pistol shot accepted beside port staff")
	await frames(30)
	check(staff.get_meta("workplace_threatened", false), "nearby gunfire interrupts port staff")
	check(security.nearest_action().is_empty(), "frightened staff offers no conversation")
	check(reaction != null and reaction.body.hand_provider.is_valid() and reaction.body.hand_targets[0] is Vector3, "port staff actually raises articulated hands")
	check(staff.global_position.is_equal_approx(original_position), "static staff shields without sliding through scenery")
	await frames(280)
	check(not staff.get_meta("workplace_threatened", false) and not reaction.body.hand_provider.is_valid(), "quiet restores port staff pose and service")
	check(not reaction.body.is_processing(), "static staff returns to its original animation budget")
	var fire: Node3D = world.gameplay.emergency.ignite(staff.global_position + Vector3(2.5, 0, 0), world.player)
	check(fire != null, "real ground fire admitted on port floor")
	await frames(300)
	check(staff.get_meta("workplace_threatened", false), "ongoing visible fire renews threat beyond gunfire timeout")
	world.gameplay.emergency.extinguish(fire, 10.0)
	await frames(280)
	check(not staff.get_meta("workplace_threatened", false), "extinguished fire permits return to work")
	check(security.perform("south_port_checkpoint"), "port conversation opens after recovery")
	# NPC gunfire is a real shared gameplay signal and can occur during a menu.
	world.gameplay.npc_gunfire.emit(staff.global_position + Vector3(0, 1, 3), Vector3.FORWARD, null)
	check(not session.modal and security.nearest_action().is_empty(), "incoming gunfire closes an active port conversation")
	var balance: int = session.state.economy.balance
	security._pay_bribe()
	check(session.state.economy.balance == balance and not security.authorized_entry, "stale bribe action cannot charge frightened staff")
	await frames(280)
	# Stream an authored moving worker, then fire away from the worker.
	await place(Vector3(3900.0 / 16.0, .08, 3370.0 / 16.0 + 3.0))
	var worker = session._routine_director().actors.get("south_port_worker_00")
	check(is_instance_valid(worker), "authored cargo worker is physically active")
	if is_instance_valid(worker):
		var stock: int = worker.crate_total()
		check(shoot_away(), "gunfire reaches the active cargo route")
		var home: Vector3 = worker.global_position
		var stopped_activity: String = worker.activity
		var stopped_timer: float = worker.activity_left
		await frames(75)
		check(worker.get_meta("workplace_threatened", false) and not worker.is_physics_processing(), "cargo routine yields movement ownership during danger")
		check(worker.activity == stopped_activity and is_equal_approx(worker.activity_left, stopped_timer) and worker.crate_total() == stock, "interruption preserves cargo and unfinished work")
		var retreat: float = worker.global_position.distance_to(home)
		print("REACTION_WORKER retreat=", retreat, " position=", worker.global_position)
		check(retreat > .2 and retreat <= REACTION.RETREAT_DISTANCE + .1 and worker.is_on_floor(), "cargo worker visibly retreats a bounded distance on the real floor")
		await frames(310)
		check(not worker.get_meta("workplace_threatened", false) and worker.is_physics_processing() and worker.crate_total() == stock, "cargo resumes its existing routine after physical return")
	await cargo_probe(session)
	if await session.enter_place("harbor_bank", false):
		await frames(35)
		var clerks: Array = session.robberies._actors.filter(func(candidate): return not candidate.guard)
		check(clerks.size() == 2, "both real bank clerks spawned")
		var homes: Array = clerks.map(func(candidate): return candidate.global_position)
		check(shoot_away(), "real shot inside bank")
		# Stop the alarm's guard response to isolate recovery after the initiating shot.
		session.robberies.data.bank_shots = false
		await frames(80)
		for i in clerks.size():
			var clerk = clerks[i]
			var response: Node = clerk.get_node_or_null("WorkplaceThreatReaction")
			check(response != null and response.active and response.body.hand_provider.is_valid(), "bank clerk %d visibly protects head" % i)
			check(clerk.health == 80 and clerk.global_position.distance_to(homes[i]) <= REACTION.RETREAT_DISTANCE + .1, "bank clerk %d keeps health and remains within bounded retreat" % i)
		await frames(300)
		for i in clerks.size():
			check(not clerks[i].get_meta("workplace_threatened", false) and clerks[i].global_position.distance_to(homes[i]) < .08, "bank clerk %d physically returns to the counter" % i)
		check(session.robberies.data.bank_alarm, "recovery does not erase the bank crime/alarm")
		check(session.leave_place(), "leave bank after reaction")
	else: check(false, "enter bank")
	await frames(10)
	await remaining(session)
	await finish()

func remaining(session) -> void:
	await focus_test(session)
	if await session.enter_place("harbor_ammunation", false):
		await frames(35)
		var vendor: Node3D = session.static_service_actor
		check(vendor.get_node_or_null("WorkplaceThreatReaction") != null, "ordinary shop vendor is connected through session")
		world.player.teleport(session.room.interaction_points.service + Vector3.UP * .05)
		await frames(5)
		check(session.nearest().get("id") == "service", "vendor service available before threat")
		check(shoot_away(), "real shot beside shop vendor")
		await frames(20)
		check(vendor.get_meta("workplace_threatened", false) and session.nearest().get("id") != "service", "shop stops service during threat")
		await frames(340)
		check(not vendor.get_meta("workplace_threatened", false) and session.nearest().get("id") == "service", "quiet restores shop service after collision-safe return")
		check(session.interact() and session.modal, "recovered vendor opens real storefront")
		world.gameplay.npc_gunfire.emit(vendor.global_position + Vector3(0, 1, 2), Vector3.FORWARD, null)
		check(not session.modal and not session.storefronts.is_open(), "incoming threat closes already-open vendor storefront")
		check(session.leave_place(), "leave shop after recovery")
		await frames(8)
		check(await session.enter_place("harbor_ammunation", false), "Vance room can be entered again")
		var response: Node = session.static_service_actor.get_node("WorkplaceThreatReaction")
		check(response.get_signal_connection_list("threat_started").size() == 1, "reentry retains exactly one service reaction callback")
		check(session.leave_place(), "leave reentered shop")
	else: check(false, "enter weapon shop")
	await frames(10)
	if await session.enter_place("maciota", false):
		await frames(15)
		check(not session.state.weapons_allowed() and session.state.equipped_weapon == "fists", "garage still holsters every weapon")
		check(not session.state.equip_weapon("pistol") and not world.gameplay.fire_at(world.player.global_position + Vector3.RIGHT * 4), "garage blocks drawing and attacking")
		check(world.gameplay.emergency.ignite(world.player.global_position, world.player) == null, "garage rejects player ground fire")
		for npc in [world.maciota_place.maciota, world.maciota_place.mechanic]:
			check(PROTECTION.is_protected(npc) and not npc.has_method("receive_damage") and not npc.has_method("die"), "garage resident retains absolute protection without mortality API")
			check(REACTION.install(npc, npc, world.gameplay) == null and npc.get_node_or_null("WorkplaceThreatReaction") == null, "protected resident cannot be enrolled in threat adapter")
	else: check(false, "enter protected garage")
	check(session.leave_place(), "leave protected garage")
	await frames(8)
	if await session.enter_place("harbor_hospital", false):
		await frames(25)
		var doctor: Node3D
		for npc in session.room_npcs:
			if npc.get_meta("interior_npc_id", "") == "hospital_miguel": doctor = npc
		check(doctor != null, "real hospital doctor available")
		if doctor != null:
			world.player.teleport(doctor.global_position + Vector3(0, .05, 1))
			await frames(5)
			check(session.interact() and session.dialogue_open, "real doctor dialogue opens")
			var completed := [false]
			session.dialogue_done = func(): completed[0] = true
			session._advance_dialogue()
			check(session.dialogue_open and session._service_menu_open, "next dialogue line preserves service ownership")
			world.gameplay.npc_gunfire.emit(doctor.global_position + Vector3(0, 1, 2), Vector3.FORWARD, null)
			check(not session.modal and not session.dialogue_open and not completed[0] and not session.dialogue_done.is_valid(), "threat interrupts continued doctor dialogue without completing it")
			await frames(340)
			session.show_inventory()
			check(session.modal and not session._service_menu_open, "ordinary inventory is independent of service dialogue")
			world.gameplay.npc_gunfire.emit(doctor.global_position + Vector3(0, 1, 2), Vector3.FORWARD, null)
			check(session.modal, "threat does not dismiss unrelated inventory")
			session.close_menu()
	else: check(false, "enter hospital")

func focus_test(session) -> void:
	session._menu("First fixture menu")
	session._button("Removed before deferred focus", func(): pass)
	session._menu("Replacement fixture menu")
	session._button("Current button", func(): pass)
	var current: Button = session.column.get_child(session.column.get_child_count() - 1)
	await frames(3)
	check(root.gui_get_focus_owner() == current, "same-frame replacement focuses only the live menu button")
	session._menu("Interrupted fixture menu")
	session._button("Closed before deferred focus", func(): pass)
	var closed: Button = session.column.get_child(session.column.get_child_count() - 1)
	session.close_menu()
	await frames(3)
	check(root.gui_get_focus_owner() != closed and not session.modal, "same-frame close does not focus an invisible menu")

func finish() -> void:
	print("VIDEO_PHASE3_REACTIONS checks=", checks, " failures=", failures.size())
	for failure in failures: print("FAILED: ", failure)
	world.queue_free()
	await frames(5)
	quit(0 if failures.is_empty() else 1)

func cargo_probe(session) -> void:
	await place(Vector3(3900.0 / 16.0, .08, 3370.0 / 16.0 + 3.0))
	var worker = session._routine_director().actors.get("south_port_worker_00")
	check(is_instance_valid(worker), "probe has authored cargo worker")
	if not is_instance_valid(worker): return
	check(shoot_away(), "probe real gunfire")
	var response = worker.get_node("WorkplaceThreatReaction")
	await frames(75)
	var away: Vector3 = (worker.global_position - response._home).normalized()
	check(worker.global_position.distance_to(response._home) > 1.4, "probe worker actually retreated before return obstruction")
	# A newly closed route must stop recovery; this fixture never removes authored solids.
	var wall := StaticBody3D.new()
	wall.name = "ReactionReturnObstruction"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 2, .08)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = worker.global_position.lerp(response._home, .5) + Vector3.UP
	wall.rotation.y = atan2(-away.x, -away.z)
	await frames(260)
	print("CARGO_BLOCKED p=", worker.global_position, " home=", response._home, " quiet=", response.quiet_left)
	check(response.active and response.returning and response.quiet_left == 0.0, "quiet worker waits when physical return route closes")
	check((worker.global_position - wall.global_position).dot(away) > .28, "returning worker never crosses the new solid")
	wall.queue_free()
	await frames(95)
	check(not response.active and worker.is_physics_processing(), "probe recovers cargo route")

func scope_test() -> void:
	var gameplay := ScopeGameplay.new()
	root.add_child(gameplay)
	var outside_staff := Node3D.new()
	root.add_child(outside_staff)
	var model := Node3D.new()
	outside_staff.add_child(model)
	check(REACTION.install(outside_staff, model, gameplay) != null, "garage save context still installs an unrelated outdoor worker")
	outside_staff.free()
	for id in ["maciota", "mechanic", "mecanico"]:
		var protected := Node3D.new()
		protected.set_meta("interior_npc_id", id)
		root.add_child(protected)
		check(REACTION.install(protected, protected, gameplay) == null, "explicit protected identity excluded: " + id)
		protected.free()
	var ancestor := Node3D.new()
	ancestor.set_meta("invulnerable", true)
	root.add_child(ancestor)
	var descendant := Node3D.new()
	ancestor.add_child(descendant)
	check(REACTION.install(descendant, descendant, gameplay) == null, "ancestral protection also excludes descendants")
	ancestor.free()
	gameplay.free()
	print("VIDEO_PHASE3_REACTIONS scope checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
