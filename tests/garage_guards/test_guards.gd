extends SceneTree
const Guards := preload("res://runtime/garage_guards/Guards.gd")
const Places := preload("res://world/places/PlaceCatalog.gd")
var checks := 0
var failures: Array[String]=[]
class Gameplay extends RefCounted:
	# O guarda avisa as reações de civis a cada tiro (Gameplay real tem o mesmo sinal).
	signal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)
	var hits := 0
	func _sound(_id,_point): pass
	func _trace(_a,_b,_c,_d): pass
	func _damage(_actor,_amount,_source): hits+=1
	func find_path(_a,b): return PackedVector3Array([b])
class Session extends RefCounted:
	var world: Dictionary
	var state := {"place_id":"port_boss_garage"}
	var ready_for_play := true
	var room: Node3D
	var saves := 0
	func save_game(): saves+=1
	func position_clear(point):
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius=.28
		shape.height=1.7
		query.shape=shape
		query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.86)
		query.collision_mask=7
		return room.get_world_3d().direct_space_state.intersect_shape(query).is_empty()
class Garage extends Node:
	var session: Session
	var data := {"police_called":false,"alarm_remaining":-1.0}
	var alarms := 0
	func raise_alarm():
		if data.alarm_remaining>=0 or data.police_called: return
		alarms+=1
		data.alarm_remaining=15.0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures.append(label); push_error(label)
func settle():
	for i in 3: await physics_frame
func run():
	var world := Node3D.new()
	root.add_child(world)
	var room=Places.create_place("port_boss_garage")
	world.add_child(room)
	var player := CharacterBody3D.new()
	player.collision_layer=2
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height=1.7
	capsule.radius=.3
	collider.shape=capsule
	collider.position.y=.86
	player.add_child(collider)
	player.position=Vector3(7.3,.04,8)
	world.add_child(player)
	var garage := Garage.new()
	garage.session=Session.new()
	garage.session.room=room
	garage.session.world={"player":player,"driving":{"occupied":false,"car":null},"gameplay":Gameplay.new()}
	world.add_child(garage)
	var manager := Guards.new()
	garage.add_child(manager)
	manager.configure(garage)
	await settle()
	manager.sync()
	check(manager.actors.size()==2,"Both original guard capsule positions clear native garage solids")
	if manager.actors.size()!=2: world.free(); quit(1); return
	for actor in manager.actors: actor.set_physics_process(false)
	await settle()
	var guard=manager.actors[0]
	check(guard.position.is_equal_approx(Guards.POINTS[0]) and manager.actors[1].position.is_equal_approx(Guards.POINTS[1]),"Original two positions preserved")
	check(guard.health==50 and guard.clip==12,"Original patrol health and pistol magazine")
	check(guard.visual.mat_uniform.albedo_color==Color("454b42"),"Original private security uniform color")
	# PoliceModel sorteia um biotipo (altura) por pessoa; o guarda mantém a proporção
	# original 0,84 x 1 x 0,90 sobre esse biotipo.
	var body_height: float = float(guard.visual.get_meta("police_appearance",{"height":1.0}).height)
	check(guard.visual.scale.is_equal_approx(Vector3(.84,1,.90)*1.28*body_height) and guard.weapon.get_child_count()>0,"Original articulated rig proportions and mesh pistol")
	check(guard.get_meta("local_security",false) and guard.get_meta("interior_actor",false),"Private guards use local alarm and avoid remote emergency dispatch")
	check(not manager.alerted() and guard.can_see(player),"Guard sees nearby player without starting alarm")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(2,3,.3)
	wall_shape.shape=box
	wall.add_child(wall_shape)
	wall.position=Vector3(7.3,1.5,6.8)
	world.add_child(wall)
	await settle()
	check(not guard.can_see(player) and not guard.shoot(player),"Native wall occludes aim and prevents shooting")
	wall.queue_free()
	await settle()
	check(guard.shoot(player) and guard.clip==11,"Visible shot consumes actual magazine")
	check(guard.cooldown>=.85 and guard.cooldown<=1.05,"Original patrol cadence preserved")
	guard.receive_damage(10,player)
	check(guard.health==40 and garage.alarms==1 and garage.data.alarm_remaining==15,"Player damage triggers one original alarm")
	garage.data.alarm_remaining=7
	guard.receive_damage(10,player)
	check(garage.alarms==1 and garage.data.alarm_remaining==7,"Further damage cannot postpone or duplicate alarm")
	guard.receive_damage(100,player)
	check(guard.dead and guard.health==0 and guard.collision_layer==0,"Dead guard has no further combat or blocking capsule")
	var saved: Array=JSON.parse_string(JSON.stringify(manager.snapshot()))
	check(Guards.validate(saved) and saved[0].health==0 and saved[0].clip==11,"Guard damage and ammunition survive JSON")
	var bad: Array=saved.duplicate(true)
	bad[1].health=51
	check(not manager.restore(bad),"Reject health outside original guard limit")
	garage.session.state.place_id=""
	manager.sync()
	await settle()
	check(manager.actors.is_empty(),"Leaving room removes guard physics and visuals")
	check(manager.restore(saved),"Restore saved guard ledger")
	garage.session.state.place_id="port_boss_garage"
	manager.sync()
	check(manager.actors.size()==2 and manager.actors[0].dead,"Returning or reloading does not resurrect killed guard")
	world.free()
	await process_frame
	print("%s garage guards: %d checks"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
