extends SceneTree
const Heist := preload("res://runtime/Robberies.gd")
const Economy := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []
class Player extends CharacterBody3D:
	var input_locked := false
class Gameplay extends Node3D:
	signal weapon_fired(id: String, origin: Vector3)
	var health := 100.0
	var aim_point := Vector3.ZERO
	var crimes: Array = []
	func register_crime(points: int, position: Vector3): crimes.append({"points":points,"position":position})
class Room extends Node3D:
	var vault_amount := 0.0
	func set_vault_open(amount): vault_amount=amount
class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var room: Node3D
	var room_npc: CharacterBody3D
	var ready_for_play := true
	var modal := false
	var saves := 0
	func position_clear(_position): return true
	func save_game(): saves+=1
	func show_message(_message): pass
	func close_menu(): modal=false; world.player.input_locked=false
func _initialize(): _run.call_deferred()
func check(value: bool, message: String):
	checks+=1
	if not value: failures.append(message)
func _run():
	var default := Heist.defaults()
	check(Heist.validate_snapshot(default),"Initial heist state valid")
	var corrupt := default.duplicate(true)
	corrupt.keycard_taken=true
	check(not Heist.validate_snapshot(corrupt),"Cannot restore keycard that never dropped")
	corrupt=default.duplicate(true)
	corrupt.guards=[NAN,50]
	check(not Heist.validate_snapshot(corrupt),"Reject nonfinite actor health")
	corrupt=default.duplicate(true)
	corrupt.fuel_alarm_remaining=-1
	check(not Heist.validate_snapshot(corrupt),"Reject negative dispatch timer")
	var session := Session.new()
	var room := Room.new()
	var player := Player.new()
	var gameplay := Gameplay.new()
	root.add_child(room)
	root.add_child(player)
	root.add_child(gameplay)
	session.room=room
	session.world={"player":player,"gameplay":gameplay,"driving":{"occupied":false}}
	session.state={"place_id":"harbor_bank","equipped_weapon":"pistol","economy":Economy.new()}
	var heist := Heist.new()
	root.add_child(heist)
	heist.configure(session)
	heist.set_physics_process(false)
	heist._physics_process(.01)
	check(heist._actors.size()==4 and heist._piles.size()==3,"Native bank actors and original treasure install")
	for actor in heist._actors: actor.set_physics_process(false)
	gameplay.weapon_fired.emit("pistol",Vector3.ZERO)
	check(heist.data.bank_alarm and heist.data.bank_shots and gameplay.crimes.size()==1,"A real weapon-fired event triggers bank alarm once")
	gameplay.weapon_fired.emit("pistol",Vector3.ZERO)
	check(gameplay.crimes.size()==1,"Repeated shots cannot duplicate bank dispatch")
	var guard = heist._actors[0]
	guard.receive_damage(50)
	check(heist.data.keycard_available and heist.data.guards[0]==0,"Defeated actual guard drops keycard")
	player.position=Vector3(-5,0,.5)
	check(heist.perform("bank_card"),"Keycard action requires local player")
	heist._tick_hold(.6,true)
	check(not heist.data.keycard_taken,"Short press cannot take keycard")
	heist._tick_hold(.6,true)
	check(heist.data.keycard_taken,"Holding physically nearby takes keycard")
	player.position=Heist.VAULT
	check(heist.perform("bank_vault"),"Card grants physical lockpick action")
	heist._tick_hold(.6,true)
	check(heist.lockpick.active and session.modal,"Lockpick blocks movement while puzzle active")
	for i in 3:
		heist.lockpick.angle=heist.lockpick.target_angle+1
		heist.lockpick.attempt()
	check(not heist.lockpick.active and not heist.data.vault_open and heist.data.bank_alarm,"Three mistakes abort puzzle without stopping alarm")
	heist.perform("bank_vault")
	heist._tick_hold(.6,true)
	for i in 3:
		heist.lockpick.angle=heist.lockpick.target_angle
		heist.lockpick.attempt()
	check(heist.data.opening_remaining==3 and not heist.data.vault_open,"Three timed pins begin three-second door animation")
	heist._physics_process(1.5)
	check(is_equal_approx(room.vault_amount,.5) and not heist.data.vault_open,"Door opens progressively")
	heist._physics_process(1.5)
	check(heist.data.vault_open and room.vault_amount==1,"Door unlocks after complete animation")
	player.position=Heist.LOOT[0]
	heist.perform("bank_cash0")
	heist._tick_hold(1.2,true)
	check(session.state.economy.balance==4000 and heist.data.bank_cash0,"Physical cash hold pays original amount")
	check(not heist.perform("bank_cash0") and session.state.economy.balance==4000,"Taken pile cannot pay again")
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(heist.snapshot()))
	check(Heist.validate_snapshot(roundtrip) and heist.restore_snapshot(roundtrip),"Heist health loot and timers survive JSON roundtrip")
	session.state.place_id=""
	heist._physics_process(.01)
	check(not heist.can_enter_bank() and heist.data.aftermath=="closed","Leaving robbery closes bank while exit remains usable")
	heist._physics_process(2399.98)
	check(not heist.can_enter_bank(),"Bank stays closed before four original days")
	heist._physics_process(.02)
	check(heist.can_enter_bank() and heist.data.bank_cycle==1 and not heist.data.bank_cash0,"Bank reopens and resets loot after investigation")
	session.state.place_id="harbor_fuel"
	heist._physics_process(.01)
	check(heist._actors.size()==1 and heist.data.fuel_initialized,"Fuel installs original cashier once")
	heist._actors[0].set_physics_process(false)
	heist.data.fuel_resists=false
	player.position=Vector3(4.6,0,-1.8)
	gameplay.aim_point=Vector3(4.6,0,-3.8)
	var wall := StaticBody3D.new()
	wall.collision_layer=1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(1,1,.3)
	shape.shape=box
	wall.add_child(shape)
	wall.position=Vector3(4.6,1.65,-2.8)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	heist._tick_cashier(3,true)
	check(not heist.data.fuel_alarm and heist._intimidation==0,"Solid wall blocks physical cashier intimidation")
	wall.free()
	await physics_frame
	heist.data.fuel_resists=true
	heist._tick_cashier(3,true)
	check(not heist.data.fuel_register,"Resisting cashier never pays from aim alone")
	heist.data.fuel_resists=false
	heist._intimidation=0
	heist._tick_cashier(2,true)
	check(not heist.data.fuel_register,"Cashier requires three continuous seconds of aim")
	heist._tick_cashier(1,true)
	check(heist.data.fuel_register and session.state.economy.balance==4180,"Live visible cashier pays original180")
	heist._tick_cashier(4,true)
	check(session.state.economy.balance==4180,"Fuel register reward idempotent")
	check(gameplay.crimes.size()==1,"Fuel alarm delay does not dispatch immediately")
	heist._physics_process(30)
	check(gameplay.crimes.size()==2 and gameplay.crimes[1].points==15,"Fuel dispatch occurs after original30 seconds")
	for actor in heist._actors: actor.set_physics_process(false)
	check(Heist.validate_snapshot(heist.snapshot()),"End-to-end heist snapshot valid")
	heist.free()
	room.free()
	player.free()
	gameplay.free()
	for message in failures: push_error(message)
	print("%s robberies: %d checks"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
