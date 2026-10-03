extends SceneTree
const Heist := preload("res://runtime/Robberies.gd")
const Aftermath := preload("res://runtime/BankAftermath.gd")
var checks := 0
var failures: Array[String] = []

class Clock extends RefCounted:
	var day := 2
	var time_of_day := .4
	func moon_day() -> int: return day

class Session extends RefCounted:
	var state := {"place_id":"harbor_bank", "region_id":"harbor", "economy":preload("res://systems/economy/Economy.gd").new()}
	var weather := Clock.new()
	var world: Dictionary
	var saves := 0
	var heist
	var saved: Dictionary = {}
	var weapon_shop_entrance: Node
	func save_game() -> void:
		saves += 1
		if heist != null: saved = heist.snapshot()

class Access extends Node:
	func _door_position(_id, definition) -> Vector3: return definition.exterior_position + Vector3(0,0,4.905)
	func _inward(_id) -> Vector3: return Vector3.FORWARD

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func run() -> void:
	var session := Session.new()
	var heist := Heist.new()
	root.add_child(heist)
	heist.set_physics_process(false)
	heist.session = session
	session.heist = heist
	var cycle := Aftermath.new()
	cycle.heist = heist
	heist.add_child(cycle)
	check(Heist.validate_snapshot(heist.snapshot()), "new snapshot valid")
	cycle.advance(5.0, true)
	check(heist.can_enter_bank(), "peaceful bank never closes from time alone")
	heist.data.bank_alarm = true
	heist.data.bank_shots = true
	cycle.advance(10.0, true)
	check(heist.can_enter_bank() and heist.data.aftermath == "", "escaping a robbery alive never schedules investigation")
	session.state.place_id = "harbor_fuel"
	heist.player_died()
	check(not heist.data.bank_failed, "death elsewhere cannot start the bank investigation")
	session.state.place_id = "harbor_bank"
	heist.player_died()
	check(heist.data.bank_failed and heist.can_enter_bank(), "death inside robbery schedules without immediately closing")
	cycle.advance(5.0, false)
	check(heist.data.elapsed_days == 0.0, "being inside or on screen never starts absence")
	cycle.advance(.8, true)
	check(heist.can_enter_bank(), "less than one full day away remains open")
	cycle.advance(.01, false)
	check(heist.data.elapsed_days == 0.0, "returning to the bank resets continuous absence")
	cycle.advance(.6, true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(heist.snapshot()))
	check(Heist.validate_snapshot(saved) and heist.restore_snapshot(saved), "pending absence survives JSON save restore")
	cycle.advance(.399, true)
	check(heist.can_enter_bank(), "restored absence does not close early")
	cycle.advance(.0011, true)
	check(not heist.can_enter_bank() and is_equal_approx(heist.data.elapsed_days, .0001), "one continuous day away starts three-day closure with the remaining elapsed time")
	cycle.advance(2.999, true)
	check(not heist.can_enter_bank(), "investigation lasts three full in-game days")
	cycle.advance(.002, false)
	check(not heist.can_enter_bank(), "expired investigation does not remove tape while visible")
	cycle.advance(0.0, true)
	check(heist.can_enter_bank() and heist.data.bank_cycle == 1 and not heist.data.bank_alarm, "offscreen reopening resets robbery and changes generation")
	check(heist.data.guards == [160.0,160.0] and heist.data.clerks == [100.0,100.0], "new team recovers full intended health")
	# The functional fixture has no live gameplay physics tick; model the
	# restored living player, which resets this latch in _physics_process.
	heist._death_latched = false
	heist.data.bank_alarm = true
	heist.player_died()
	cycle.advance(2.0, true)
	check(heist.data.aftermath == "closed" and heist.data.elapsed_days == 1.0, "calendar jumps carry excess absence into investigation")
	check(session.saved.aftermath == "closed" and session.saved.elapsed_days == 1.0, "transition save includes excess elapsed calendar time")
	cycle.advance(2.0, true)
	check(heist.can_enter_bank() and heist.data.bank_cycle == 2, "four calendar days complete both stages")
	var legacy := Heist.defaults()
	legacy.version = 1
	legacy.erase("bank_failed")
	legacy.guards = [25.0, 0.0]
	legacy.clerks = [80.0, 40.0]
	legacy.bank_alarm = true
	legacy.bank_shots = true
	legacy.aftermath = "closed"
	legacy.elapsed_days = 2.0
	check(Heist.validate_snapshot(legacy) and heist.restore_snapshot(legacy), "legacy saves stay loadable")
	check(heist.can_enter_bank() and not heist.data.bank_failed and heist.data.guards == [80.0,0.0], "legacy automatic closure is removed and wounded/dead guards preserved")
	check(Heist.validate_snapshot(heist.snapshot()), "migrated save validates as v2")
	var corrupt := heist.snapshot()
	corrupt.aftermath = "closed"
	check(not Heist.validate_snapshot(corrupt), "v2 rejects closure without a player death")
	# Productive clock sampling: wall delta never defines bank days.
	var player := Node3D.new()
	var camera := Camera3D.new()
	root.add_child(player)
	root.add_child(camera)
	session.world = {"player":player,"camera":camera}
	session.state.region_id = "mountain"
	session.state.place_id = ""
	heist.data = Heist.defaults()
	heist.data.bank_alarm = true
	heist.data.bank_failed = true
	heist.data.aftermath = "pending"
	cycle.reset_clock()
	cycle.update(1.0)
	cycle.update(6000.0)
	check(heist.data.elapsed_days == 0.0, "paused world clock never advances from real seconds")
	session.weather.day += 1
	cycle.update(.21)
	check(not heist.can_enter_bank(), "one actual world calendar day triggers closure")
	session.weather.day += 2
	cycle.update(.21)
	check(not heist.can_enter_bank(), "two calendar days cannot complete investigation")
	session.weather.day += 1
	cycle.update(.21)
	check(heist.can_enter_bank(), "third calendar day reopens outside view")
	# Real camera projection guards both near-bank and wide-screen visibility.
	session.state.region_id = "harbor"
	var bank: Dictionary = Aftermath.PLACES.get_definition("harbor_bank")
	player.position = bank.exterior_position
	check(not cycle.bank_is_away(), "standing beside bank never counts as away")
	player.position += Vector3(0,0,90)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 240
	camera.position = bank.exterior_position + Vector3(0,100,100)
	camera.look_at(bank.exterior_position)
	check(not cycle.bank_is_away(), "bank visible in a wide camera prevents replacement even at distance")
	camera.position += Vector3(700,0,0)
	check(cycle.bank_is_away(), "distant bank outside camera allows investigation")
	var access := Access.new()
	root.add_child(access)
	session.weapon_shop_entrance = access
	var facade := Node3D.new()
	facade.set_meta("place_id", "harbor_bank")
	facade.add_to_group("v2_walkin_facade")
	root.add_child(facade)
	heist.data.bank_alarm = true
	heist.data.bank_failed = true
	heist.data.aftermath = "closed"
	cycle._sync_tape()
	check(is_instance_valid(cycle._tape) and cycle._tape.visible and cycle._tape.get_child_count() == 8, "closed bank has crossed exterior tapes and solid posts")
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = .875
	walker.add_child(collider)
	root.add_child(walker)
	await physics_frame
	await physics_frame
	var tape_point: Vector3 = cycle._tape.global_position
	check(walker.test_move(Transform3D(Basis.IDENTITY, tape_point + Vector3(1.65,.04,2)), Vector3(0,0,-4)), "whole actor sweep collides with investigation post")
	check(not walker.test_move(Transform3D(Basis.IDENTITY, tape_point + Vector3(0,.04,2)), Vector3(0,0,-4)), "side posts leave the doorway free of invisible tape collision")
	heist._reopen_bank()
	cycle._sync_tape()
	await physics_frame
	check(not is_instance_valid(cycle._tape), "reopened bank removes exterior tape")
	check(not walker.test_move(Transform3D(Basis.IDENTITY, tape_point + Vector3(1.65,.04,2)), Vector3(0,0,-4)), "reopening removes post collisions too")
	heist.free()
	player.free()
	camera.free()
	access.free()
	facade.free()
	walker.free()
	for failure in failures: push_error(failure)
	print("%s bank aftermath: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
