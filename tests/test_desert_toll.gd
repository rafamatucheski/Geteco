extends SceneTree
const TOLL:=preload("res://runtime/desert/entrance/DesertToll.gd")
const PLAZA:=preload("res://world/desert/entrance/DesertTollPlaza.gd")
const ECONOMY:=preload("res://systems/economy/Economy.gd")
var failed:=false
class Car extends Node3D:
	var speed:=0.0
	var input_locked:=false
	var half_length:=2.5
	var traffic:=false
	var external_input:=false
class Session extends Node:
	var ready_for_play:=true
	var modal:=false
	var state: Dictionary
	var world: Dictionary
	var controller: Dictionary
	var saves:=0
	func has_position_transition() -> bool: return false
	func show_message(_message: String) -> void: pass
	func save_game() -> void: saves+=1

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	print("TOLL ","PASS " if value else "FAIL ",label)
	failed=failed or not value
func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	var plaza:=PLAZA.new()
	scene.add_child(plaza)
	var car:=Car.new()
	scene.add_child(car)
	car.add_to_group("drivable")
	car.position=PLAZA.POSITION+Vector3(2.7,0,1)
	var player:=Node3D.new()
	scene.add_child(player)
	player.position=car.position
	var session:=Session.new()
	scene.add_child(session)
	var wallet:=ECONOMY.new()
	session.state={"region_id":"desert","place_id":"","economy":wallet}
	session.world={"driving":{"occupied":true,"car":car},"gameplay":{"health":100},"player":player}
	session.controller={"vehicles":[car]}
	var toll:=TOLL.new()
	scene.add_child(toll)
	toll.configure(session)
	check(not toll.nearest_action().is_empty(),"stopped inbound car can pay")
	toll.perform()
	check(wallet.balance==0 and toll.paid_car==null,"insufficient funds keeps gate closed without debit")
	wallet.grant_reward("entrance_test",100)
	var funded: int=wallet.balance
	car.speed=3
	check(toll.nearest_action().is_empty() and not toll.perform(),"moving car cannot pay")
	car.speed=0
	check(toll.perform(),"payment succeeds")
	check(wallet.balance==funded-TOLL.PRICE and toll.paid_car==car,"exactly one debit grants passage")
	check(not toll.perform() and wallet.balance==funded-TOLL.PRICE,"repeated interaction cannot double charge")
	check(not toll.save_block_reason().is_empty(),"save waits until paid car clears plaza")
	for i in 100: await physics_frame
	check(plaza.arms[0].rotation.z>1.4,"physical entry arm opens")
	car.position.z-=32
	player.position=car.position
	toll._refresh()
	check(toll.paid_car==null and toll.save_block_reason().is_empty() and session.saves==1,"crossing releases lease and checkpoints debit")
	var snapshot: Dictionary=wallet.snapshot()
	check(ECONOMY.validate_snapshot(snapshot),"payment receipt persists in real economy schema")
	var restored:=ECONOMY.new()
	check(restored.restore_snapshot(snapshot),"wallet restores")
	session.state.economy=restored
	car.position=PLAZA.POSITION+Vector3(2.7,0,1)
	player.position=car.position
	check(toll.perform() and restored.balance==funded-2*TOLL.PRICE,"return after load uses a new receipt")
	toll.cancel_attempt()
	car.position=PLAZA.POSITION+Vector3(-2.7,0,-10)
	player.position=car.position
	toll._refresh()
	check(toll.nearest_action().is_empty() and plaza.targets[1]<-1.4,"outbound lane opens without payment")
	check(restored.balance==funded-2*TOLL.PRICE,"return is free")
	var police:=Car.new()
	police.external_input=true
	scene.add_child(police)
	police.add_to_group("drivable")
	police.position=PLAZA.POSITION+Vector3(2.7,0,8)
	toll._refresh()
	check(plaza.targets[0]>1.4,"NPC dispatch vehicle outside ambient fleet opens entry")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
