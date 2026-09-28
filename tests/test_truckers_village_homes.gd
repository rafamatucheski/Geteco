extends SceneTree
const HOMES := preload("res://gameplay/urban_v1/TruckersVillageHomes.gd")
const LAYOUT := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").HOME_LAYOUT
const ACTOR := preload("res://scripts/Actor.gd")
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
var checks := 0
var failures: Array[String] = []
class WorldFixture extends Node3D:
	var player: Node3D
class SessionFixture extends RefCounted:
	var world
	var weather = null
class WeatherFixture extends Node:
	var updates:=0
	func _update(): updates+=1
class VillageFixture extends Node3D:
	var solids: Array[StaticBody3D] = []
	var placements: Array[Dictionary] = []
	var houses: Array[Vector3] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var world:=WorldFixture.new()
	root.add_child(world)
	var floor:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var ground:=BoxShape3D.new()
	ground.size=Vector3(350,.2,350)
	collision.shape=ground
	collision.position.y=-.1
	floor.add_child(collision)
	world.add_child(floor)
	var village:=VillageFixture.new()
	world.add_child(village)
	var homes:=HOMES.new()
	village.add_child(homes)
	homes.build(village,LAYOUT)
	var player:=ACTOR.new()
	player.is_player=true
	player.controlled_automatically=true
	player.position=Vector3(100,.04,100)
	world.add_child(player)
	world.player=player
	var outside_camera:=Camera3D.new()
	world.add_child(outside_camera)
	outside_camera.make_current()
	player.camera=outside_camera
	var session:=SessionFixture.new()
	session.world=world
	homes.configure(session)
	var npc:=RESIDENT.new()
	npc.configure({"id":"house_test_resident","stationary":true,"position":Vector3(104,.04,100)})
	world.add_child(npc)
	for i in 4: await physics_frame
	check(homes.homes.size()==6,"Six physically distinct accessible homes")
	for index in 6:
		var room:Dictionary=homes.homes[index]
		var home:Node3D=room.root
		var exterior:=home.to_global(Vector3(0,.04,6))
		var motion:Vector3=home.basis*Vector3(0,0,-5)
		check(player.test_move(Transform3D(Basis.IDENTITY,exterior),motion),"Closed house%d door blocks player"%index)
		check(npc.test_move(Transform3D(Basis.IDENTITY,exterior),motion),"Closed house%d door blocks resident"%index)
		player.teleport(exterior)
		for frame in 28: await physics_frame
		check(float(room.amount)>.98,"House%d proximity opens physical door"%index)
		var contact:=player.move_and_collide(motion)
		check(contact==null,"Player sweeps through house%d actual doorway"%index)
		for frame in 10: await physics_frame
		check(homes.current_home==index,"House%d presence activates interior"%index)
		check(not room.roof.visible and not room.upper.visible,"House%d roof and upper walls reveal room"%index)
		check(player.camera==homes.interior_camera,"House%d uses native orthographic camera"%index)
		check(homes.interior_camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"Orthographic indoor projection")
		check((homes.interior_camera.cull_mask & (1<<19))==0 and (outside_camera.cull_mask & (1<<19))!=0,"Indoor view excludes crowns while exterior camera retains them")
		check(absf(player.position.y)<.15,"House%d player remains on ground"%index)
		var capsule:=CapsuleShape3D.new()
		capsule.radius=.32
		capsule.height=1.8
		for point in homes.occupant_anchors(index)+[homes.loot_points[index]]:
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=capsule
			query.transform.origin=point+Vector3.UP*.95
			query.collision_mask=1
			check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"House%d occupant/loot full body clearance"%index)
		# Test a real resident through the same open entry without overlapping player.
		player.teleport(home.to_global(Vector3(-1.5,.04,-1)))
		for frame in 2: await physics_frame
		npc.global_position=exterior
		npc.velocity=Vector3.ZERO
		for frame in 28: await physics_frame
		check(float(room.amount)>.98,"Resident proximity reopens house%d door"%index)
		npc.global_position.y=.04
		contact=npc.move_and_collide(motion)
		check(contact==null,"Native resident sweeps through house%d door"%index)
		# Bed volume, including its sides, is fully solid for both body types.
		var beds:Array=homes.furniture.filter(func(row): return row.home==index and row.id=="Bed")
		for actor in [player,npc]:
			var bed:StaticBody3D=beds[0].body
			var start:=bed.global_position+home.basis*Vector3(0,0,2)
			start.y=.04
			actor.global_position=start
			actor.velocity=Vector3.ZERO
			for frame in 2: await physics_frame
			# A horizontal sweep starts just above ground so floor support is not
			# mistaken for the furniture contact under test.
			actor.global_position.y=.04
			var hit:KinematicCollision3D=actor.move_and_collide(home.basis*Vector3(0,0,-2.5))
			check(hit!=null and hit.get_collider()==bed,"House%d bed blocks %s"%[index,actor.name])
			check(absf(actor.position.y)<.15,"House%d actor never climbs onto furniture"%index)
			actor.global_position=Vector3(110+actor.get_instance_id()%3,.04,110)
			actor.velocity=Vector3.ZERO
			for frame in 2: await physics_frame
		player.teleport(home.to_global(Vector3(0,.04,1)))
		for frame in 10: await physics_frame
		player.teleport(home.to_global(Vector3(0,.04,3)))
		for frame in 28: await physics_frame
		player.global_position.y=.04
		contact=player.move_and_collide(home.basis*Vector3(0,0,4))
		check(contact==null,"House%d exit is physically traversable"%index)
		for frame in 10: await physics_frame
		check(homes.current_home==-1 and room.roof.visible,"House%d departure restores exterior"%index)
		check(player.camera==outside_camera,"House%d restores original gameplay camera"%index)
		player.teleport(Vector3(100,.04,100))
		for frame in 28: await physics_frame
	check(village.solids.size()==homes.solids.size(),"All indoor physical solids join region lifecycle")
	homes.set_region_active(false)
	check(homes.solids.all(func(body): return body.collision_layer==0),"Inactive homes release physical collision")
	homes.set_region_active(true)
	check(homes.solids.all(func(body): return body.collision_layer==1),"Reactivated homes restore solids")
	var weather:=WeatherFixture.new()
	root.add_child(weather)
	session.weather=weather
	homes._set_inside(0)
	var before_updates:int=weather.updates
	var solid_count:int=homes.solids.size()
	world.free()
	check(weather.updates==before_updates,"World teardown never updates a partially destroyed weather/audio owner")
	weather.free()
	print("TRUCKERS_VILLAGE_HOMES checks=",checks," solids=",solid_count," failures=",failures)
	quit(0 if failures.is_empty() else 1)
