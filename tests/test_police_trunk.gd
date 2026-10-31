extends SceneTree
const TRUNK := preload("res://runtime/PoliceTrunk.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
class Car extends CharacterBody3D:
	var vehicle_id := "parked"
	var archetype := "police_cruiser"
	var health := 100.0
	var controlled := false
	var external_input := false
	var speed := 0.0
	var half_length := 2.2
class Gameplay extends Node:
	signal changed
	var health := 100.0
	var armor := 0.0
class World extends Node3D:
	var player := CharacterBody3D.new()
	var gameplay := Gameplay.new()
	var driving := {"occupied":false}
class Session extends Node:
	var ready_for_play := true
	var modal := false
	var blocked := false
	var controller := {"save_invalid":false}
	var state := {"economy":ECONOMY.new()}
	var world := World.new()
	var saves := 0
	func is_transition_blocked() -> bool: return blocked
	func show_message(_text): pass
	func save_game(): saves += 1
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print("POLICE_TRUNK ","PASS " if ok else "FAIL ",label)
func run():
	var session := Session.new()
	root.add_child(session)
	root.add_child(session.world)
	session.world.add_child(session.world.player)
	session.world.add_child(session.world.gameplay)
	var car := Car.new()
	session.world.add_child(car)
	car.add_to_group("drivable")
	session.world.player.position = Vector3(0,0,3)
	await physics_frame
	check(not TRUNK.accessible(session,car),"unbroken patrol has no loot access")
	TRUNK.mark_unlocked(car)
	var identity := car.vehicle_id
	TRUNK.mark_unlocked(car)
	check(identity == car.vehicle_id,"unlock identity is stable")
	check(TRUNK.nearest(session) == car,"rear of unlocked patrol is accessible")
	car.set_meta("police_locked",true)
	check(not TRUNK.collect(session,car,"weapon"),"locked patrol rejects collection")
	car.remove_meta("police_locked")
	var seen := {}
	for i in 100:
		car.vehicle_id = TRUNK.PREFIX+str(i)
		seen[TRUNK.weapon(car)] = true
	check(seen.size() == 3,"random identities cover SMG shotgun and pistol")
	car.vehicle_id = identity
	var wallet = session.state.economy
	check(TRUNK.collect(session,car,"weapon") and wallet.owns_weapon(TRUNK.weapon(car)),"weapon enters real economy")
	check(not TRUNK.collect(session,car,"weapon"),"weapon cannot be collected twice")
	var restored = ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(wallet.snapshot()))),"economy save roundtrip")
	session.state.economy = restored
	check(TRUNK.taken(session,car,"weapon") and not TRUNK.collect(session,car,"weapon"),"reload keeps receipt spent")
	session.world.gameplay.armor = 100
	check(not TRUNK.collect(session,car,"armor") and not TRUNK.taken(session,car,"armor"),"full armor leaves vest available")
	session.world.gameplay.armor = 20
	check(TRUNK.collect(session,car,"armor") and session.world.gameplay.armor == 100,"vest replenishes armor")
	check(not TRUNK.collect(session,car,"armor"),"vest cannot duplicate")
	car.vehicle_id = TRUNK.PREFIX+"fresh"
	check(not TRUNK.taken(session,car,"armor"),"replacement patrol has separate loot")
	session.world.player.position = Vector3(0,0,-3)
	check(not TRUNK.collect(session,car,"armor"),"front of car rejects stale menu collection")
	session.world.player.position = Vector3(0,0,3)
	car.speed = 2
	check(not TRUNK.accessible(session,car),"moving car rejects access")
	car.speed = 0
	session.world.gameplay.health = 0
	check(not TRUNK.accessible(session,car),"dead player rejects access")
	session.world.gameplay.health = 100
	session.state.economy = ECONOMY.new()
	session.state.economy.enable_grid_inventory()
	# Ocupa o slot do ombro; uma segunda arma longa não cabe em dois bolsos.
	check(session.state.economy.grant_weapon("hunting_rifle"),"occupy carried long gun slot")
	for i in 100:
		car.vehicle_id = TRUNK.PREFIX+str(i)
		if TRUNK.weapon(car) == "shotgun": break
	check(not TRUNK.collect(session,car,"weapon") and not TRUNK.taken(session,car,"weapon"),"insufficient space preserves loot")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(3,3,.1)
	wall.add_child(shape)
	session.world.add_child(wall)
	wall.position = Vector3(0,1,2.75)
	await physics_frame
	await physics_frame
	check(not TRUNK.accessible(session,car),"wall blocks rear interaction")
	session.world.queue_free()
	session.queue_free()
	await process_frame
	print("POLICE_TRUNK_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
