extends SceneTree
const HOMES := preload("res://gameplay/urban_v1/TruckersVillageHomes.gd")
const LOOT := preload("res://gameplay/urban_v1/TruckersVillageHouseLoot.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var failures: Array[String]=[]
var checks:=0
class PlayerFixture extends Node3D:
	var dead:=false
class SessionFixture extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var ready_for_play:=true
	var messages:=0
	func show_message(_message): messages+=1
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func tick(loot: Node) -> void:
	loot._scan=0
	loot._process(.2)
func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	var homes:=HOMES.new()
	scene.add_child(homes)
	var layout:Array=[]
	for i in 6: layout.append([Vector3(i*25,0,0),"a49673",float(i)*.25])
	homes.build(scene,layout)
	var player:=PlayerFixture.new()
	scene.add_child(player)
	var session:=SessionFixture.new()
	session.world={"player":player,"gameplay":{"health":100.0},"driving":{"occupied":false}}
	session.state={"region_id":"harbor","place_id":"","economy":ECONOMY.new()}
	var loot:=LOOT.new()
	scene.add_child(loot)
	loot.configure(session,homes)
	loot.set_process(false)
	var before:int=session.state.economy.balance
	for i in 6:
		var stash:Node3D=homes.homes[i].loot
		player.global_position=stash.global_position
		homes.current_home=-1
		tick(loot)
		check(session.state.economy.balance==before,"Inactive house%d cannot award pickup"%i)
		homes.current_home=i
		player.dead=true
		tick(loot)
		check(session.state.economy.balance==before,"Dead player cannot take house%d cash"%i)
		player.dead=false
		session.world.gameplay.health=0
		tick(loot)
		check(session.state.economy.balance==before,"Zero gameplay health blocks house%d reward"%i)
		session.world.gameplay.health=100
		player.global_position=homes.homes[i].root.to_global(Vector3(0,0,6))
		tick(loot)
		check(session.state.economy.balance==before,"Outside physical home%d cannot award stash"%i)
		player.global_position=stash.global_position
		session.state.region_id="mountain"
		tick(loot)
		check(session.state.economy.balance==before,"Other region cannot collect home%d stash"%i)
		session.state.region_id="harbor"
		session.world.driving.occupied=true
		tick(loot)
		check(session.state.economy.balance==before,"Vehicle occupant cannot collect home%d stash"%i)
		session.world.driving.occupied=false
		tick(loot)
		check(session.state.economy.balance==before+LOOT.CASH[i],"Exact house%d reward R$%d"%[i,LOOT.CASH[i]])
		check(stash.consumed,"Collected house%d stash starts absorbing"%i)
		await create_timer(.35).timeout
		check(not stash.visible,"Collected house%d stash disappears"%i)
		before=session.state.economy.balance
		tick(loot)
		check(session.state.economy.balance==before,"Standing on stash cannot repeat house%d reward"%i)
		var snapshot:Dictionary=session.state.economy.snapshot()
		var restored:=ECONOMY.new()
		check(restored.restore_snapshot(snapshot),"Economy restores house%d receipt"%i)
		session.state.economy=restored
		stash.show()
		tick(loot)
		check(session.state.economy.balance==before and not stash.visible,"Restored receipt prevents duplicate house%d reward"%i)
	check(session.messages==6,"One pickup message for each of six unique rewards")
	print("TRUCKERS_VILLAGE_HOUSE_LOOT checks=",checks," failures=",failures)
	homes.current_home=-1
	scene.free()
	quit(0 if failures.is_empty() else 1)
