extends SceneTree
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
const MANAGER := preload("res://gameplay/urban_v1/TruckersVillageResidents.gd")
const QUEST := preload("res://gameplay/urban_v1/TruckersVillageQuest.gd")
class Combat extends Node:
	var health := 100.0
	func damage_player(value): health-=value
class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var ready_for_play := true
	func show_message(_text): pass
	func close_menu(): pass
class Homes extends Node:
	signal house_entered(index)
	var homes: Array = []
	func _init():
		for i in 6: homes.append({"entry":Vector3(i*20,0,4.5),"center":Vector3(i*20,0,0)})
	func occupant_anchors(index): return [homes[index].center+Vector3(-1.5,0,-1),homes[index].center+Vector3(1.5,0,-1)]
	func house_at(point):
		for i in homes.size():
			var delta: Vector3=point-homes[i].center
			if absf(delta.x)<6.3 and absf(delta.z)<4.3: return i
		return -1
var checks := 0
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures.append(message); push_error(message)
func solid(parent,at,size,layer:=1):
	var body:=StaticBody3D.new()
	body.position=at
	body.collision_layer=layer
	var shape:=BoxShape3D.new()
	shape.size=size
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	parent.add_child(body)
	return body
func run():
	var scene:=Node3D.new()
	root.add_child(scene)
	solid(scene,Vector3(0,-.1,0),Vector3(900,.2,900))
	var player:=CharacterBody3D.new()
	player.collision_layer=2
	var collider:=CollisionShape3D.new()
	var shape:=CapsuleShape3D.new()
	shape.radius=.32
	shape.height=1.8
	collider.shape=shape
	collider.position.y=.9
	player.add_child(collider)
	scene.add_child(player)
	var combat:=Combat.new()
	scene.add_child(combat)
	var session:=Session.new()
	session.world={"player":player,"gameplay":combat,"driving":{"occupied":false}}
	session.state={"region_id":"harbor","place_id":"","economy":preload("res://systems/economy/Economy.gd").new()}
	var manager:=MANAGER.new()
	manager.configure(session)
	scene.add_child(manager)
	var quest:=QUEST.new()
	scene.add_child(quest)
	quest.configure(session)
	quest.bind_residents(manager)
	var homes:=Homes.new()
	scene.add_child(homes)
	manager.bind_homes(homes,quest)
	var guards=manager.house_guards
	guards.set_process(false)
	for index in 6:
		player.position=homes.homes[index].center+Vector3(0,.04,2)
		check(manager.house_entered(index,player.position),"Occupied home %d triggers intrusion alarm"%index)
		check(guards.pairs[index].size()==2,"Home %d has two physical residents"%index)
		var active_count:=0
		for pair in guards.pairs.values():
			for actor in pair:
				if actor.active: active_count+=1
		check(active_count==2,"Only current home's pair processes")
		check(manager.hostile and manager.residents[0].hostile,"Intrusion calls outdoor group")
		for actor in guards.pairs[index]: check(actor.weapon_id=="shotgun" and actor.model.weapon.visible,"House residents draw real doze")
	check(not manager.house_entered(0,player.position),"Wrong home identifier cannot trigger remote alarm")
	player.position=Vector3(0,.04,2)
	guards._activate(0)
	for actor in guards.pairs[0]: actor.receive_damage(100,player)
	quest.commerce.data.hostility=0
	manager.set_hostile(false)
	check(not manager.house_entered(0,player.position),"Dead occupants cannot call reinforcements")
	var saved: Dictionary=quest.snapshot()
	check(quest.restore_snapshot(saved),"Occupant health/death snapshot restores with quest")
	guards._activate(0)
	check(guards.pairs[0][0].dead and guards.pairs[0][1].dead,"Restore does not revive killed occupants")
	var invalid: Dictionary=saved.duplicate(true)
	invalid.house_guards.health["0"]=[91,90]
	check(not quest.restore_snapshot(invalid),"Invalid resident health snapshot rejected atomically")
	# Isolate actual shotgun rays from unrelated homes and actors.
	manager.set_region_active(false)
	guards._activate(-1)
	var shooter:=RESIDENT.new()
	shooter.configure({"id":"doze_test","weapon":"shotgun","stationary":true,"position":Vector3(0,.04,30)},combat)
	scene.add_child(shooter)
	player.position=Vector3(0,.04,35)
	shooter.set_hostile(true,player)
	for frame in 4: await physics_frame
	shooter._shot_left=0
	shooter._try_shoot()
	check(shooter.last_pellet_hits>1 and shooter.last_pellet_hits<=7,"Doze fires several independently traced pellets")
	check(combat.health==100-shooter.last_pellet_hits*4,"Damage equals pellets physically hitting player")
	var remaining:=combat.health
	shooter._try_shoot()
	check(combat.health==remaining and shooter._shot_left>2,"Shotgun cooldown blocks rapid repeat")
	var wall=solid(scene,Vector3(0,1.5,32.5),Vector3(4,3,.3))
	for frame in 3: await physics_frame
	shooter._shot_left=0
	shooter._try_shoot()
	check(combat.health==remaining,"Closed wall blocks whole shotgun blast")
	wall.collision_layer=4
	for frame in 3: await physics_frame
	shooter._try_shoot()
	check(combat.health==remaining,"Vehicle blocks shotgun blast")
	wall.free()
	player.position.z=42
	for frame in 3: await physics_frame
	shooter._try_shoot()
	check(combat.health==remaining,"Doze has bounded local range")
	print("TRUCKERS_VILLAGE_HOUSE_GUARDS checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
