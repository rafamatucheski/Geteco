extends SceneTree
const Garage := preload("res://runtime/GarageRewards.gd")
const Extra := preload("res://runtime/GarageRewardFleet.gd")
const Fleet := preload("res://runtime/FleetCatalog.gd")
const Activities := preload("res://activities/Activities.gd")
const Economy := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []
class Campaign extends RefCounted:
	var defeated := false
	var completed: Array = []
	var active_id := ""
	func snapshot(): return {"completed":completed}
	func cobra_status(): return {"defeated":defeated}
class Car extends CharacterBody3D:
	var visual: Node3D
	var archetype := ""
	var vehicle_id := ""
	var health := 100.0
	var max_health := 100.0
	var controlled := false
	var speed := 0.0
	var paint_color := Color.WHITE
	func repair(): health=max_health
	func place(point: Vector3, yaw: float): position=point; rotation.y=yaw; speed=0
class Controller extends RefCounted:
	var world: Node3D
	var vehicles: Array = []
	var blocked := false
	func spawn_vehicle(id,point,yaw,_crush_ratio := 1.0):
		if blocked: return null
		var car := Car.new()
		car.archetype=id
		car.position=point
		car.rotation.y=yaw
		car.max_health=float(Garage._spec(id).get("durability",100))
		car.health=car.max_health
		world.add_child(car)
		vehicles.append(car)
		return car
	func vehicle_position_clear(_car,_point,_yaw): return not blocked
class Gameplay extends RefCounted:
	const STAR_THRESHOLDS := [0,10,30,60,90]
	var stars := 0
	var crime_points := 0
	var health := 100.0
	var dispatch_timer := 5.0
	var dispatches := 0
	func register_crime(points,_position): crime_points+=points; stars=3; dispatches+=1
class Place extends Node3D:
	var interior_origin := Vector3(0,0,-130)
	var entry_position := Vector3(20,0,20)
	var definition: Dictionary
class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var controller: Controller
	var activities
	var mission_world: Dictionary
	var room: Node3D
	var ready_for_play := true
	var saves := 0
	func save_game(): saves+=1
	func show_message(_message): pass
	func position_clear(_point): return false # Guards have dedicated physical tests.
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	checks+=1
	if not ok: failures.append(message)
func _run():
	check(not Garage.is_open(.99) and Garage.is_open(1) and Garage.is_open(4.99) and not Garage.is_open(5),"Original garage window1h inclusive5h exclusive")
	var model := Extra.create(Extra.ID)
	check(model!=null and model.get_child_count()==10,"Original Ironback exported geometry has ten prepared meshes")
	model.free()
	check(Extra.spec(Extra.ID).max_speed==560 and Extra.spec(Extra.ID).durability==100,"Reward keeps original controller stats separately from Cobra V8")
	var world := Node3D.new()
	root.add_child(world)
	var room := Place.new()
	room.position=Vector3(0,0,-2400)
	room.definition=preload("res://world/places/PlaceCatalog.gd").get_definition("port_boss_garage")
	world.add_child(room)
	var maciota := Place.new()
	world.add_child(maciota)
	var player := CharacterBody3D.new()
	world.add_child(player)
	var campaign := Campaign.new()
	var gameplay := Gameplay.new()
	var session := Session.new()
	session.room=room
	session.controller=Controller.new()
	session.controller.world=world
	session.activities=Activities.new()
	session.world={"player":player,"maciota_place":maciota,"gameplay":gameplay,"driving":{"occupied":false,"car":null}}
	session.state={"campaign":campaign,"economy":Economy.new(),"world_state":{"time":.1},"place_id":"port_boss_garage","region_id":"harbor"}
	session.mission_world={"targets":{"neco_bay":Vector3(-40,0,40)}}
	var garage := Garage.new()
	world.add_child(garage)
	session.ready_for_play=false
	garage.configure(session)
	garage.set_physics_process(false)
	check(garage.cars.is_empty(),"Configure waits for restored location and physics readiness")
	session.ready_for_play=true
	garage.on_location_changed()
	check(garage.cars.size()==5,"Five original parked stock vehicles instantiate")
	garage.on_location_changed()
	check(garage.cars.size()==5 and session.controller.vehicles.size()==5,"Repeated admission cannot duplicate parked stock")
	check(not garage.data.vehicles.has(Garage.IRONBACK),"Port garage does not grant campaign Ironback")
	campaign.defeated=true
	garage._sync()
	check(not garage.data.vehicles.has(Garage.IRONBACK),"Defeated alone insufficient for victory car")
	campaign.completed=["cobra_finale"]
	garage._sync()
	check(garage.data.vehicles.has(Garage.IRONBACK) and not garage.cars.has(Garage.IRONBACK),"Victory reward belongs to Maciota and waits for physical room")
	var porto=garage.cars[Garage.PORT_ID]
	session.world.driving={"occupied":true,"car":porto}
	porto.controlled=true
	garage._physics_process(.01)
	check(garage.data.port_status=="stolen" and garage.data.alarm_remaining==15,"Boarding PortoRosso starts original15second alarm")
	garage._physics_process(14)
	check(gameplay.dispatches==0,"Alarm does not dispatch early")
	garage._physics_process(1)
	check(gameplay.dispatches==1 and gameplay.stars>=3,"Alarm dispatches at least three wanted stars")
	garage._physics_process(20)
	check(gameplay.dispatches==1,"Alarm dispatch is idempotent")
	session.world.driving.occupied=false
	porto.controlled=false
	session.state.place_id=""
	porto.set_meta("garage_place","")
	porto.set_meta("garage_origin",Vector3.ZERO)
	porto.place(session.mission_world.targets.neco_bay,0)
	player.position=porto.position+Vector3(2,0,0)
	garage.on_location_changed()
	check(not garage._porto_deliverable(),"Wanted player cannot deliver stolen PortoRosso")
	gameplay.stars=0
	check(garage._porto_deliverable(),"Original car stopped near Neco bay can be delivered on foot")
	porto.visual=Fleet.create("porto_rosso")
	porto.add_child(porto.visual)
	porto.add_to_group("drivable")
	var press=preload("res://world/neco_press/NecoPress3D.gd").new()
	press.position=porto.position+Vector3(8,0,0)
	world.add_child(press)
	await physics_frame
	await physics_frame
	var blocker := StaticBody3D.new()
	blocker.collision_layer=2
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size=Vector3.ONE
	blocker_shape.shape=blocker_box
	blocker.add_child(blocker_shape)
	blocker.position=press.position+Vector3(0,1,0)
	world.add_child(blocker)
	await physics_frame
	await physics_frame
	check(not garage.perform("porto_deliver") and porto.visible,"Occupied press refuses delivery and preserves real car")
	blocker.queue_free()
	await physics_frame
	await physics_frame
	check(garage.perform("porto_deliver") and session.state.economy.balance==0,"Press starts without early payout")
	check(not garage.perform("porto_deliver"),"Repeated interaction cannot start a second transaction")
	check(Garage.validate_snapshot(garage.snapshot()) and garage.data.port_status=="stolen","Save during animation retains undelivered ownership")
	garage.cancel_press_delivery()
	check(porto.visible and porto.is_in_group("drivable") and not press.is_active(),"Cancellation restores car and releases press")
	check(session.state.economy.balance==0 and session.activities.salvage_available()==6,"Cancellation pays nothing and consumes no quota")
	await physics_frame
	check(garage.perform("porto_deliver"),"Delivery starts before simulated chunk unload")
	press.queue_free()
	await physics_frame
	await physics_frame
	check(not garage._transition and porto.visible and session.state.economy.balance==0,"Unloading press restores car without paying")
	press=preload("res://world/neco_press/NecoPress3D.gd").new()
	press.position=porto.position+Vector3(8,0,0)
	world.add_child(press)
	await physics_frame
	await physics_frame
	check(garage.perform("porto_deliver"),"Cancelled delivery can restart")
	for frame in 300:
		await physics_frame
		if not garage._transition: break
	check(session.state.economy.balance==50000,"Completed press delivery pays50000")
	garage._press_finished(true)
	check(session.state.economy.balance==50000,"Duplicate completion cannot repeat payment")
	check(garage.data.port_status=="delivered" and session.activities.salvage_available()==5,"Port delivery consumes shared six-per-day limit")
	check(not garage.perform("porto_deliver") and session.state.economy.balance==50000,"Cannot repeat exclusive payout")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(garage.snapshot()))
	check(Garage.validate_snapshot(saved),"Garage snapshot retains original IDs and valid JSON")
	var bad: Dictionary=saved.duplicate(true)
	bad.alarm_remaining=NAN
	check(not garage.restore_snapshot(bad),"Corrupt timer does not replace valid state")
	check(garage.restore_snapshot(saved),"Valid garage state restores")
	session.state.place_id="maciota"
	player.position=Vector3(4,0,-130)
	garage.on_location_changed()
	check(garage.cars.has(Garage.IRONBACK),"Authorized original Ironback appears only in Maciota")
	var reward=garage.cars[Garage.IRONBACK]
	reward.health=23
	reward.place(Vector3(0,0,20),0)
	reward.set_meta("garage_place","")
	reward.set_meta("garage_origin",Vector3.ZERO)
	check(garage.perform("ironback_recover") and reward.health==23,"Recovering reward to bay preserves damage")
	check(garage.perform("ironback_repair") and reward.health==100,"Explicit bay repair restores original health")
	check(session.state.economy.balance==50000,"Original reward bay repair charges nothing")
	session.controller.blocked=true
	reward.place(Vector3(0,0,20),0)
	check(not garage.perform("ironback_recover"),"Occupied hull rejects recovery instead of pushing obstacles")
	session.controller.blocked=false
	var guest=session.controller.spawn_vehicle("sedan_classic",Vector3(0,.1,-126),0)
	guest.vehicle_id="ordinary_saved_car"
	session.state.world_state.vehicles=[{"vehicle_id":"ordinary_saved_car"}]
	check(garage.register_guest(guest) and guest.vehicle_id=="garage_guest_1","Accepted common car gains stable guest ownership")
	check(guest.get_meta("garage_reward",false) and session.state.world_state.vehicles.is_empty(),"Guest owns persistence before old current-car entry is cleared")
	check(garage.register_guest(guest) and guest.vehicle_id=="garage_guest_1","Registering guest repeatedly preserves identity")
	var guest_save: Dictionary=JSON.parse_string(JSON.stringify(garage.snapshot()))
	check(Garage.validate_snapshot(guest_save) and guest_save.vehicles.garage_guest_1.place_id=="maciota","Common car interior state survives JSON")
	var restored := Garage.new()
	check(restored.restore_snapshot(guest_save) and restored.data.vehicles.garage_guest_1==guest_save.vehicles.garage_guest_1,"Guest reload retains model transform damage and ownership")
	restored.free()
	bad=guest_save.duplicate(true)
	bad.vehicles.garage_guest_1.was_driven=true
	bad.vehicles[Garage.IRONBACK].was_driven=true
	check(not Garage.validate_snapshot(bad),"Snapshot cannot restore two simultaneous drivers")
	bad=guest_save.duplicate(true)
	bad.vehicles.garage_guest_1.archetype="unregistered_model"
	check(not Garage.validate_snapshot(bad),"Guest cannot inject an unknown model")
	bad=guest_save.duplicate(true)
	bad.vehicles["garage_guest_01"]=bad.vehicles.garage_guest_1
	check(not Garage.validate_snapshot(bad),"Guest IDs reject ambiguous integer spelling")
	bad=guest_save.duplicate(true)
	for i in range(2,66): bad.vehicles["garage_guest_%d"%i]=bad.vehicles.garage_guest_1.duplicate(true)
	check(not Garage.validate_snapshot(bad),"Guest cap bounds save and runtime fleet to64")
	var owned=session.controller.spawn_vehicle("towmaster",Vector3.ZERO,0)
	owned.vehicle_id="neco_tow_truck"
	check(not garage.register_guest(owned),"Tow mission ownership cannot be captured by garage")
	owned.vehicle_id="residence_extra"
	owned.set_meta("residence_vehicle",true)
	check(not garage.register_guest(owned),"Residence ownership cannot be captured by garage")
	session.activities.free()
	world.free()
	for message in failures: push_error(message)
	print("%s garage rewards: %d checks"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
