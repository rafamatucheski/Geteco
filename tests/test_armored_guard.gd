extends SceneTree
## Real guard, native body and real Gameplay ballistic sweep on a physics fixture.
## Calendar/radio ownership remains in the transport integration tests.
const GUARD := preload("res://gameplay/armored/ArmoredGuard.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
class State extends RefCounted:
	var allowed := true
	var place_id := ""
	var equipped_weapon := "pistol"
	func weapons_allowed() -> bool: return allowed
	func owns_weapon(_id: String) -> bool: return false
class World extends Node3D:
	var player: CharacterBody3D
	var gameplay: Node
	var driving := {"occupied":false, "car":null}
class Player extends CharacterBody3D:
	var input_locked := false
class Convoy extends Node3D:
	var session: Dictionary
	var data := {"hostile":false}
	var reports: Array[Node] = []
	var operational := true
	func crew_operational() -> bool: return operational
	func provoke(source: Node) -> void:
		reports.append(source)
		if source == session.world.player: data.hostile = true
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARMORED_GUARD ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func shape(node: CollisionObject3D, size: Vector3, point: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = point
	node.add_child(collision)
func frames(count: int) -> void:
	for index in count: await physics_frame
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	shape(floor_body, Vector3(80, .2, 80), Vector3(0, -.1, 0))
	world.add_child(floor_body)
	world.player = Player.new()
	world.player.collision_layer = 2
	shape(world.player, Vector3(.8, 1.8, .8), Vector3.UP * .9)
	world.add_child(world.player)
	world.player.position = Vector3(0, 0, -8)
	var state := State.new()
	world.gameplay = preload("res://gameplay/Gameplay.gd").new()
	world.gameplay.configure(world, world.player, null, state)
	world.add_child(world.gameplay)
	world.gameplay.set_physics_process(false)
	var convoy := Convoy.new()
	convoy.session = {"state":state, "world":world}
	world.add_child(convoy)
	var guard := GUARD.new()
	guard.configure_security(SCHEDULE.security(0))
	guard.convoy = convoy
	convoy.add_child(guard)
	guard.set_physics_process(false)
	await frames(3)
	check(guard.health == 110 and guard.is_in_group("v2_damageable"), "finite crew starts with authored security health")
	check(guard.visual.body != null and guard.visual.weapon_id == "pistol", "security uses the shared articulated rig and physical weapon")
	check(guard.can_see_player(), "unobstructed exterior suspect is visible")
	check(not world.gameplay.police_case.observe(4, world.player.global_position, "gunfire") and world.gameplay.police_case.pending.is_empty(), "security never bypasses its convoy radio with the generic civilian call timer")
	world.gameplay.aiming = true
	world.gameplay.aim_point = Vector3(0, 0, -20)
	check(not guard.player_is_aiming_at_me(), "pointing away from the guard is not a threat")
	world.gameplay.aim_point = guard.global_position
	check(guard.player_is_aiming_at_me(), "aim toward visible guard is a real threat")
	var wall := StaticBody3D.new()
	shape(wall, Vector3(5, 3, .2), Vector3(0, 1.5, -4))
	world.add_child(wall)
	await frames(2)
	check(not guard.can_see_player() and not guard.player_is_aiming_at_me(), "wall blocks visual identification and threat detection")
	wall.free()
	await frames(2)
	state.place_id = "maciota_garage"
	check(not guard.can_see_player(), "exterior guard cannot see or attack Dante in an interior")
	state.place_id = ""
	state.allowed = false
	check(not guard.can_see_player(), "weapon-free context independently suppresses engagement")
	state.allowed = true
	world.gameplay.aiming = false
	guard.receive_damage(NAN)
	guard.receive_damage(-5)
	check(guard.health == 110 and convoy.reports.is_empty(), "invalid damage neither poisons health nor reports a crime")
	var stranger := Node3D.new()
	world.add_child(stranger)
	guard.receive_damage(5, stranger)
	check(guard.health == 105 and convoy.reports.back() == stranger and not convoy.data.hostile, "damage retains its real author for transport crime attribution")
	guard.cargo_carrying = true
	guard._physics_process(.05)
	guard.visual._body_weapon_targets()
	check(guard.visual.cash_case.visible and not guard.visual.weapon.visible, "carrier holds the case and puts away the firearm")
	var contacts: Array = guard.visual._body_weapon_targets()
	check(contacts[1].distance_to(guard.visual.cash_case.to_global(Vector3(0, .194, 0))) < .001, "left hand contacts the case handle")
	guard.receive_damage(5, world.player)
	guard._physics_process(.05)
	check(convoy.data.hostile and guard._reaction > 0 and world.gameplay._police_rounds.is_empty(), "first attack is telegraphed before guards open fire")
	check(guard.visual.case_dropped and guard.visual.cash_case.get_parent() == convoy, "threat makes carrier drop the case in world space")
	guard.visual.update_pose(1, true, false, 0, 0)
	convoy.session.modal = true
	world.player.input_locked = true
	guard._reaction = 0
	guard._scan_clock = 0
	guard._physics_process(.05)
	check(world.gameplay._police_rounds.size() == 1 and world.gameplay.health == 100, "guard fires a travelling projectile instead of instant damage")
	if not world.gameplay._police_rounds.is_empty():
		world.gameplay._police_rounds[0].direction = (world.gameplay._police_rounds[0].point as Vector3).direction_to(world.player.global_position + Vector3.UP)
		for index in 30: world.gameplay._advance_police_rounds(.01)
	check(world.gameplay.health < 100, "modal interaction and locked input do not protect Dante from ballistic contact")
	var hurt_health: float = world.gameplay.health
	guard.cooldown = 0
	guard._rounds = 0
	guard._physics_process(.05)
	check(guard._reload_left > 0 and world.gameplay._police_rounds.is_empty(), "empty magazine forces a vulnerable reload interval")
	state.allowed = false
	guard._reload_left = 0
	guard.cooldown = 0
	guard._physics_process(1)
	check(world.gameplay._police_rounds.is_empty() and world.gameplay.health == hurt_health, "garage safety blocks combat even after hostility")
	state.allowed = true
	convoy.data.hostile = false
	guard.patrol_target = Vector3(2, 0, 0)
	guard.set_physics_process(true)
	await frames(105)
	guard.set_physics_process(false)
	check(guard.reached_target() and guard.is_on_floor(), "crew reaches cargo/boarding target through physical walking")
	world.gameplay.health = 4
	guard.visual.update_pose(1, true, false, 0, 0)
	world.gameplay.police_shoot(guard, 8)
	if not world.gameplay._police_rounds.is_empty():
		world.gameplay._police_rounds[0].direction = (world.gameplay._police_rounds[0].point as Vector3).direction_to(world.player.global_position + Vector3.UP)
		for index in 40: world.gameplay._advance_police_rounds(.01)
	check(world.gameplay.health == 0 and world.gameplay._dead_notified, "security bullets can kill Dante while an interaction holds input")
	guard.receive_damage(1000, world.player)
	check(guard.dead and guard.health == 0 and guard.collision_layer == 0, "security can die and no longer blocks the standing lane")
	guard.receive_damage(1000, world.player)
	check(guard.health == 0 and not guard.weapon.visible, "corpse damage cannot resurrect crew or leave a visible weapon flash")
	await frames(2)
	for slot in 10:
		var crew := GUARD.new()
		crew.convoy = convoy
		crew.slot = slot
		crew.position = Vector3(float(slot)*2.0,0,6)
		crew.configure_security(SCHEDULE.security(SCHEDULE.MAX_SECURITY))
		convoy.add_child(crew)
		crew.set_physics_process(false)
		await frames(2)
		var chest := crew.global_position+Vector3.UP
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(chest+Vector3.FORWARD*3,chest+Vector3.BACK,7))
		check(hit.get("collider") == crew,"visible crew slot %d has a hittable body" % slot)
		if hit.get("collider") == crew: world.gameplay._damage_bullet(hit.collider,200,world.player)
		check(crew.dead and crew.health == 0,"normal bullet damage can kill crew slot %d, including escorts" % slot)
	print("ARMORED_GUARD_RESULT checks=", checks, " failures=", failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)
