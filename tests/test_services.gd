extends SceneTree
const Services := preload("res://runtime/Services.gd")
const Economy := preload("res://systems/economy/Economy.gd")
var count := 0
var failures: Array[String] = []
class Health extends RefCounted:
	var health := 100.0
	var stars := 3
	func heal(amount: float) -> bool:
		if health<=0 or health>=100: return false
		health=minf(100,health+amount)
		return true
	func clear_wanted(): stars=0
class Room extends Node3D:
	var interaction_points := {"service":Vector3.ZERO}
	var definition := {}
class Car extends CharacterBody3D:
	var health := 50.0
	var max_health := 180.0
	var speed := 0.0
	var horizontal_velocity := Vector3.ZERO
	var vehicle_id := "test_car"
	func repair(): health=max_health
class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var room: Node3D
	var ready_for_play := true
	var saves := 0
	var spoken: Array = []
	func save_game(): saves+=1
	func show_message(_text): pass
	func show_dialogue(lines): spoken=lines
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	count+=1
	if not ok: failures.append(message)
func _run():
	var session := Session.new()
	var room := Room.new()
	var player := Node3D.new()
	var car := Car.new()
	root.add_child(room)
	root.add_child(player)
	root.add_child(car)
	session.room=room
	var health := Health.new()
	var economy := Economy.new()
	economy.grant_reward("test",1000)
	session.state={"place_id":"harbor_hospital","region_id":"harbor","economy":economy}
	session.world={"player":player,"gameplay":health,"driving":{"occupied":false,"car":car}}
	var services := Services.new()
	root.add_child(services)
	services.configure(session)
	services.set_physics_process(false)
	player.position=Services.HOSPITAL_PICKUP
	services._physics_process(.1)
	check(services.hospital_cooldown==0,"Full health does not consume hospital pickup")
	health.health=25
	services._physics_process(.1)
	check(health.health==100 and services.hospital_cooldown==180,"Hospital heals fully on physical proximity")
	health.health=40
	services._physics_process(1)
	check(health.health==40,"Hospital unavailable during cooldown")
	player.position=Vector3.ZERO
	services._physics_process(179)
	check(services.hospital_cooldown==0 and health.health==40,"Cooldown expires without remote healing")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(services.snapshot()))
	check(Services.validate_snapshot(saved) and services.restore_snapshot(saved),"Service persistence JSON roundtrip")
	saved.hospital_cooldown=-1
	check(not services.restore_snapshot(saved),"Reject corrupt cooldown atomically")
	session.state.place_id="harbor_fire_station"
	player.position=Services.FIRE_HEAL
	health.health=40
	for i in 4: services._physics_process(.25)
	check(is_equal_approx(health.health,49),"Fire station restores nine HP per second")
	player.position=Vector3.ZERO
	services._physics_process(1)
	check(health.health==49,"Fire healing stops outside area")
	session.state.place_id="harbor_police"
	check(services.perform("police") and not session.spoken.is_empty(),"Original police conversation available nearby")
	check(health.stars==3,"Police dialogue never clears crime")
	check(not services.perform("hospital"),"Wrong building rejects service")
	room.definition={"npcs":[{"id":"ribeiro","local_position":Vector3(-3.4,0,-4.2)}]}
	check(not services.perform("ribeiro"),"Named resident cannot speak remotely")
	player.position=Vector3(-3.4,0,-3.2)
	check(services.nearest_action().get("target")=="ribeiro" and services.perform("ribeiro"),"Each authored resident uses their own physical dialogue point")
	check(session.spoken[0].speaker=="Detetive Ribeiro","Resident keeps original identity and dialogue")
	player.position=Vector3(-4.2,0,1.5)
	check(services.perform("police_terminal") and session.spoken[0].message.contains("#304"),"Physical terminal exposes original incident")
	session.state.place_id=""
	session.world.driving.occupied=true
	car.position=Services.AUTO_ORIGIN+Vector3(0,0,-131.0/16.0)
	var before: int = economy.balance
	services._physics_process(.1)
	services._physics_process(4.4)
	check(economy.balance==before and car.health==50,"No charge or repair before duration")
	services._physics_process(.1)
	check(economy.balance==before-100 and car.health==180 and health.stars==0,"Parked repair charges100 after4.5s and clears crime")
	services._physics_process(5)
	check(economy.balance==before-100,"Remaining parked cannot charge twice")
	var after: Dictionary = services.snapshot()
	services.restore_snapshot(after)
	services._physics_process(5)
	check(economy.balance==before-100,"Save restore prevents repeated repair charge")
	car.position+=Vector3(20,0,0)
	services._physics_process(.1)
	car.position=Services.AUTO_ORIGIN+Vector3(0,0,-131.0/16.0)
	car.health=50
	services._physics_process(.1)
	services._physics_process(2)
	car.speed=1
	services._physics_process(3)
	check(economy.balance==before-100 and car.health==50,"Moving away cancels unpaid repair")
	services.free()
	room.free()
	player.free()
	car.free()
	for failure in failures: push_error(failure)
	print("%s services: %d checks"%["PASS" if failures.is_empty() else "FAIL",count])
	quit(0 if failures.is_empty() else 1)
