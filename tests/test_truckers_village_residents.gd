extends SceneTree
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
const RESIDENTS := preload("res://gameplay/urban_v1/TruckersVillageResidents.gd")
var checks := 0
var failures: Array[String] = []
class DamageController extends Node:
	var health := 100.0
	func damage_player(amount: float) -> void: health-=amount
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func solid(parent: Node3D,at: Vector3,size: Vector3,layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position=at
	body.collision_layer=layer
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	parent.add_child(body)
	return body
func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	solid(scene,Vector3(-150,-.1,50),Vector3(600,.2,400))
	var village:=preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").new()
	scene.add_child(village)
	var manager:=RESIDENTS.new()
	scene.add_child(manager)
	for i in 4: await physics_frame
	check(manager.residents.size()==3,"Three bounded roaming residents")
	var starts: Array[Vector3]=[]
	for i in manager.residents.size():
		var resident=manager.residents[i]
		check(resident.model.has_node("Pelvis" ) or resident.model.get("pelvis")!=null,"Native articulated human rig")
		check(not resident.model.weapon.visible,"Resident starts unarmed")
		check(resident.model.find_children("CowboyHat","",true,false).size()==1,"Country hat attached to head joint")
		for j in RESIDENTS.ROUTES[i].size():
			var from:Vector3=RESIDENTS.ORIGIN+RESIDENTS.ROUTES[i][j]+Vector3.UP*.04
			var to:Vector3=RESIDENTS.ORIGIN+RESIDENTS.ROUTES[i][(j+1)%RESIDENTS.ROUTES[i].size()]+Vector3.UP*.04
			check(not resident.test_move(Transform3D(Basis.IDENTITY,from),to-from),"Real resident capsule traverses route %d segment %d"%[i,j])
		resident.point_index=1
		resident._pause=0
		starts.append(resident.global_position)
	for i in 100: await physics_frame
	for i in manager.residents.size():
		var resident=manager.residents[i]
		var travelled:Vector3=resident.global_position-starts[i]
		check(travelled.length()>.7,"Resident physically walks along its route")
		check(absf(resident.global_position.y)<.1,"Resident feet remain on physical ground")
		check(resident.model.global_basis.z.dot(travelled.normalized())>.8,"Resident faces walking direction")
		check(resident.model._speed>.5 and resident.model._move_w>.5 and not is_zero_approx(resident.model._phase),"Native gait advances from measured displacement")
	manager.set_region_active(false)
	for resident in manager.residents: check(not resident.is_physics_processing() and resident.collision_layer==0,"Inactive residents suspend physics and collision")
	manager.set_region_active(true)
	check(manager.residents[0].is_physics_processing(),"Residents reactivate")
	var gameplay:=DamageController.new()
	scene.add_child(gameplay)
	var shooter:=RESIDENT.new()
	shooter.configure({"id":"country_shooter","variant":0,"position":Vector3(0,.04,0),"stationary":true},gameplay)
	scene.add_child(shooter)
	var player:=CharacterBody3D.new()
	player.position=Vector3(0,.04,8)
	player.collision_layer=2
	var collider:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.32
	capsule.height=1.8
	collider.shape=capsule
	collider.position.y=.9
	player.add_child(collider)
	scene.add_child(player)
	shooter.set_hostile(true,player)
	for i in 5: await physics_frame
	check(shooter.model.weapon.visible,"Provoked resident draws real weapon")
	shooter._shot_left=0
	shooter._try_shoot()
	check(gameplay.health==94 and shooter.shots_fired==1,"Clear line of sight damages player once")
	shooter._try_shoot()
	check(gameplay.health==94,"Fire cooldown blocks immediate repeated damage")
	var wall:=solid(scene,Vector3(0,1.5,4),Vector3(4,3,.5))
	for i in 3: await physics_frame
	shooter._shot_left=0
	shooter._try_shoot()
	check(gameplay.health==94,"Solid scenery blocks gunfire")
	wall.collision_layer=4
	for i in 3: await physics_frame
	shooter._shot_left=0
	shooter._try_shoot()
	check(gameplay.health==94,"Vehicle collision layer blocks gunfire")
	wall.free()
	player.position.z=22
	for i in 3: await physics_frame
	shooter._shot_left=0
	shooter._try_shoot()
	check(gameplay.health==94,"Outside local shot range is safe")
	shooter.set_hostile(false)
	check(not shooter.model.weapon.visible and not shooter.hostile,"End of conflict holsters weapon")
	shooter.receive_damage(NAN)
	check(shooter.health==90,"Invalid damage ignored")
	shooter.receive_damage(100,player)
	check(shooter.dead and shooter.collision_layer==0 and not shooter.is_physics_processing(),"Resident death disables combat and physics")
	print("TRUCKERS_VILLAGE_RESIDENTS checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
