extends "res://tests/test_mountain_zoo_tickets.gd"
## Real Actor, combat raycasts, emergency collection and ticket state. No saves.
const GAMEPLAY = preload("res://gameplay/Gameplay.gd")
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	super.check(ok, label)

func _cashier_count(admission: Node) -> int:
	var count := 0
	for child in admission.get_children():
		if child.name.begins_with("ZooCashier") and not child.is_queued_for_deletion(): count += 1
	return count

func _try_npc_payment(admission: Node, visitor: Dictionary) -> void:
	visitor.phase = "pay"
	visitor.wait = 0.0
	visitor.note.show()
	var waiting: Array[Dictionary] = [visitor]
	admission._update_visitor(visitor, waiting, .1)

func run() -> void:
	var session := TestSession.new()
	root.add_child(session)
	root.add_child(session.world)
	session.world.gameplay.free()
	var combat = GAMEPLAY.new()
	session.world.gameplay = combat
	session.world.add_child(session.world.driving)
	var player = session.world.player
	player.is_player = true
	player.controlled_automatically = true
	session.world.add_child(player)
	player.set_physics_process(false)
	combat.configure(session.world, player, null, session.state)
	session.world.add_child(combat)
	combat.set_physics_process(false)
	# The fixture directs corpse collection; no service vehicles/police needed.
	combat.emergency.set_physics_process(false)
	var zoo := ZOO.new()
	zoo.position = ZOO.CENTER
	root.add_child(zoo)
	zoo.session = session
	zoo.set_process(false)
	GEO.solid(zoo, "FixtureGround", Vector3(0,-.1,0), Vector3(160,.2,160))
	var admission = zoo.admission
	admission.set_physics_process(false)
	player.teleport(zoo.to_global(Vector3(-.7,.08,22)))
	admission._physics_process(0.0)
	await frames(12)
	var cashier = admission.cashier
	check(admission._cashier_available() and _cashier_count(admission) == 1, "One living cashier admits customers")
	check(cashier.is_physics_processing() and cashier.is_on_floor(), "Cashier settles on physical ground")
	check(cashier.automatic_direction == Vector3.ZERO, "Cashier stands at service point")
	admission._initialize_staff()
	check(admission.cashier == cashier and _cashier_count(admission) == 1, "Repeated initialization cannot duplicate cashier")
	session.state.economy.grant_reward("cashier_test", 150)
	check(admission.purchase(), "Living cashier sells player ticket")
	var ticket: Dictionary = admission.state().duplicate(true)
	var paid_balance: int = session.state.economy.balance
	admission._spawn_visitor(0)
	var paid_visitor: Dictionary = admission.visitors[0]
	_try_npc_payment(admission, paid_visitor)
	check(paid_visitor.paid and admission.npc_sales == 1 and admission.npc_revenue == 30, "Living cashier sells NPC ticket")
	admission._spawn_visitor(1)
	var waiting_visitor: Dictionary = admission.visitors[1]
	waiting_visitor.phase = "pay"
	waiting_visitor.wait = .5
	# Shoot through the service opening; the rear approach crosses the perimeter.
	check(session.state.grant_weapon("pistol") and session.state.equip_weapon("pistol"), "Fixture equips pistol")
	player.teleport(zoo.to_global(Vector3(-3.2,.08,24.7)))
	combat.aim_point = cashier.global_position + Vector3.UP * 1.2
	combat._aim_hold = 1.0
	# Advance the actual hand/weapon rig after teleport before tracing its muzzle.
	player.set_physics_process(true)
	combat.set_physics_process(true)
	await frames(12)
	player.set_physics_process(false)
	combat.set_physics_process(false)
	var origin: Vector3 = combat._muzzle_world_position()
	var direction: Vector3 = cashier.global_position - origin
	direction.y = 0.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 8.0, 7, [player.get_rid()])
	var hit: Dictionary = zoo.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == cashier, "Actual chest-height muzzle ray reaches cashier through service opening")
	if hit.get("collider") != cashier: print("CASHIER_RAY origin=", origin, " hit=", hit.get("collider"), " position=", hit.get("position"))
	combat._rng.seed = 624
	var health_before: float = cashier.health
	combat.cooldown = 0.0
	check(combat.fire_at(cashier.global_position + Vector3.UP), "Real pistol fires at cashier")
	check(cashier.health < health_before, "Bullet ray damages mortal cashier")
	combat._damage(cashier, 200.0, player)
	check(cashier.dead and cashier.collision_layer == 0, "Fatal combat damage kills cashier")
	check(not admission._cashier_available(), "Dead cashier is unavailable")
	player.teleport(zoo.to_global(Vector3(-.7,.08,22)))
	admission._physics_process(0.0)
	check(admission.state() == ticket and session.state.economy.balance == paid_balance, "Death preserves already purchased player ticket")
	check(player.get_collision_exceptions().has(admission.gate), "Paid player retains gate exception after death")
	check(paid_visitor.paid and paid_visitor.actor.get_collision_exceptions().has(admission.gate), "Paid NPC retains admission after death")
	var wallet: int = waiting_visitor.wallet
	_try_npc_payment(admission, waiting_visitor)
	check(not waiting_visitor.paid and waiting_visitor.wallet == wallet and admission.npc_sales == 1 and admission.npc_revenue == 30, "Dead cashier cannot collect pending NPC payment")
	check(not waiting_visitor.note.visible and waiting_visitor.actor.automatic_direction == Vector3.ZERO, "Waiting NPC stops offering money to corpse")
	# Finish the paid visit normally, then attempt another purchase while dead.
	player.teleport(zoo.to_global(Vector3(-.7,.08,17)))
	admission._physics_process(0.0)
	player.teleport(zoo.to_global(Vector3(-.7,.08,22)))
	admission._physics_process(0.0)
	check(not admission.state().active and not admission.purchase() and session.state.economy.balance == paid_balance, "Dead cashier cannot sell another player ticket")
	var collected := false
	for key in combat.emergency.incidents.keys():
		if combat.emergency.incidents[key].actor == cashier:
			combat.emergency.complete(key)
			collected = true
	check(collected, "Actor death reaches real emergency service")
	check(not admission.purchase(), "Queued cashier cannot sell")
	await frames(3)
	check(not is_instance_valid(admission.cashier), "Emergency collection removes cashier")
	admission._physics_process(4.0)
	check(not admission._cashier_available() and _cashier_count(admission) == 0, "Missing cashier does not respawn while nearby")
	check(not admission.purchase(), "Freed cashier cannot sell")
	_try_npc_payment(admission, waiting_visitor)
	check(not waiting_visitor.paid and admission.npc_revenue == 30, "Freed cashier cannot collect NPC revenue")
	player.teleport(zoo.to_global(Vector3(70,.08,0)))
	admission._physics_process(0.0)
	await frames(2)
	check(not admission._initialized and admission.visitors.is_empty(), "Leaving residency clears old service state")
	player.teleport(zoo.to_global(Vector3(-.7,.08,22)))
	admission._physics_process(0.0)
	await frames(12)
	check(admission._cashier_available() and _cashier_count(admission) == 1 and admission.cashier.health == 100, "Return creates exactly one healthy cashier")
	check(admission.purchase(), "Returned cashier sells a new player ticket")
	admission._spawn_visitor(0)
	_try_npc_payment(admission, admission.visitors[0])
	check(admission.npc_sales == 2 and admission.npc_revenue == 60, "Returned cashier resumes NPC sales")
	# Noncombat removal must follow the same no-resurrection contract.
	admission.cashier.queue_free()
	check(not admission._cashier_available(), "Queued living cashier is unavailable")
	await frames(2)
	admission._physics_process(0.0)
	check(_cashier_count(admission) == 0, "Externally removed cashier stays absent nearby")
	root.remove_child(zoo)
	await frames(2)
	root.add_child(zoo)
	admission._physics_process(0.0)
	check(admission._cashier_available() and _cashier_count(admission) == 1, "Unloading and returning restores one cashier")
	print("ZOO_CASHIER_LIFECYCLE ", checks, " checks ", "PASS" if failures.is_empty() else str(failures))
	zoo.free()
	session.world.free()
	session.free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
