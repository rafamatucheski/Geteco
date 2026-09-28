extends SceneTree
const Quest := preload("res://gameplay/urban_v1/TruckersVillageQuest.gd")
const Economy := preload("res://systems/economy/Economy.gd")
var failures: Array[String] = []
var checks := 0
class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var controller: Dictionary = {"vehicles":[]}
	var ready_for_play := true
	var saves := 0
	func save_game(): saves += 1
	func show_message(_message): pass
class Car extends Node3D:
	var health := 25.0
	var max_health := 100.0
	var speed := 0.0
	var controlled := false
	var traffic := false
	func repair(): health = max_health
class Resident extends Node3D:
	var dead := false
	var health := 100.0
class Village extends Node3D:
	var tonico: Node3D
	func set_part_collected(_id, _collected): pass
	func set_repaired(_repaired): pass
func _initialize(): _run.call_deferred()
func check(condition: bool, reason: String):
	checks += 1
	if not condition: failures.append(reason)
func _run():
	var player := Node3D.new()
	root.add_child(player)
	var session := Session.new()
	session.world = {"player":player,"driving":{"occupied":false,"car":null},"gameplay":{"health":100.0}}
	session.state = {"region_id":"harbor","place_id":"","economy":Economy.new()}
	var quest := Quest.new()
	root.add_child(quest)
	quest.configure(session)
	player.position = Quest.BELT_POINT
	check(quest.nearest_action().is_empty(),"Parts cannot be taken before accepting quest")
	player.position = Quest.TONICO_POINT
	session.state.region_id = "mountain"
	check(quest.nearest_action().is_empty(),"Quest cannot trigger at same coordinates in other region")
	session.state.region_id = "harbor"
	session.world.driving.occupied = true
	check(not quest.perform("truckers_village_tonico"),"Cannot interact from inside vehicle")
	session.world.driving.occupied = false
	session.world.gameplay.health = 0
	check(not quest.perform("truckers_village_tonico"),"Dead player cannot start quest")
	session.world.gameplay.health = 100
	var visual := Village.new()
	root.add_child(visual)
	visual.tonico = Resident.new()
	visual.add_child(visual.tonico)
	quest.village = visual
	visual.tonico.dead = true
	check(not quest.perform("truckers_village_tonico"),"Dead Tonico cannot offer dialogue")
	visual.tonico.dead = false
	visual.tonico.health = 0
	check(quest.nearest_action().is_empty(),"Tonico with zero health has no conversation prompt")
	visual.tonico.health = 100
	check(quest.nearest_action().get("target") == "truckers_village_tonico","Living Tonico remains available")
	check(quest.perform("truckers_village_tonico") and session.saves == 0,"Talking starts quest without bypassing completion-only checkpoints")
	visual.tonico.dead = true
	check(not quest.perform("truckers_village_belt"),"Remote collection blocked")
	player.position = Quest.BELT_POINT
	session.world.gameplay.health = 0
	check(not quest.perform("truckers_village_belt") and not quest.data.belt,"Dead player cannot collect pieces")
	session.world.gameplay.health = 100
	check(quest.perform("truckers_village_belt"),"First hidden piece collected")
	check(not quest.perform("truckers_village_belt"),"Repeated pickup blocked")
	var midway := quest.snapshot()
	check(quest.restore_snapshot(midway) and quest.data.belt and not quest.data.crank,"Mid-quest progress survives reload")
	player.position = Quest.PUMP_POINT
	check(not quest.perform("truckers_village_repair"),"Repair requires both parts")
	player.position = Quest.CRANK_POINT
	check(quest.perform("truckers_village_crank"),"Second hidden piece collected")
	player.position = Quest.PUMP_POINT
	session.world.gameplay.health = 0
	check(not quest.perform("truckers_village_repair") and session.state.economy.balance == 0,"Dead player cannot claim reward")
	session.world.gameplay.health = 100
	check(quest.perform("truckers_village_repair") and session.state.economy.balance == 450,"Restoration grants exact reward")
	check(quest.objective().is_empty(),"Completed objective removed")
	check(not quest.perform("truckers_village_repair") and session.state.economy.balance == 450,"Repeated repair never duplicates money")
	check(quest.restore_snapshot(midway) and quest.data.completed,"Wallet reconciles stale quest progress")
	check(session.state.economy.balance == 450,"Restore never grants cash again")
	var malformed := quest.snapshot()
	malformed.belt = false
	check(not quest.restore_snapshot(malformed) and quest.data.completed,"Invalid completed snapshot rejected without state loss")
	var car := Car.new()
	root.add_child(car)
	car.position = Quest.PARKING_POINT + Vector3(4,0,0)
	session.controller.vehicles.append(car)
	check(not quest.perform("truckers_village_service"),"Unselected fleet/traffic car cannot receive player service")
	session.world.driving.car = car
	car.traffic = true
	check(not quest.perform("truckers_village_service"),"Traffic-controlled vehicle cannot be serviced")
	car.traffic = false
	car.speed = 1.0
	check(not quest.perform("truckers_village_service") and car.health == 25,"Moving vehicles cannot be repaired")
	car.speed = 0
	car.health = 0
	check(not quest.perform("truckers_village_service"),"Wreck cannot be resurrected")
	car.health = 25
	check(quest.perform("truckers_village_service") and car.health == 100,"Restored station repairs parked vehicle")
	check(session.state.economy.balance == 450,"Local service costs nothing")
	car.health = 25
	car.position += Vector3(20,0,0)
	check(not quest.perform("truckers_village_service"),"Repair does not affect distant vehicles")
	player.free()
	car.free()
	quest.free()
	visual.free()
	for failure in failures: push_error(failure)
	print("Truckers village quest: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
