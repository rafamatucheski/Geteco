extends SceneTree

const ENCOUNTER := preload("res://world/harbor/cobras/CobraEncounter.gd")
const TERRITORY := preload("res://world/harbor/cobras/CobraTerritory.gd")
var failures := 0
var completions := 0

class TestPlayer extends CharacterBody2D:
	var is_in_dialogue := false
	var is_control_disabled := false
	var is_dead := false
	func take_damage(_amount: int, _player: bool = false) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := TestPlayer.new()
	player.position = Vector2(200,0)
	player.add_to_group("player")
	world.add_child(player)
	var encounter := ENCOUNTER.new()
	encounter.configure("boss",PackedVector2Array([Vector2.ZERO,Vector2(0,100),Vector2(0,200)]))
	encounter.completed.connect(func(): completions += 1)
	world.add_child(encounter)
	encounter.set_physics_process(false)
	for actor in encounter.actors:
		actor.set_physics_process(false)
	check(encounter.actors.size()==3,"Finite boss cast has three real actors")
	for i in 3:
		var actor = encounter.actors[i]
		check(actor.weapon_id == ["smg","shotgun","pistol"][i],"Role weapon matches")
		check(actor.right_lower_arm.has_node("CobraWeapon_"+actor.weapon_id),"Distinct weapon attached to shared hand rig")
	var wall := StaticBody2D.new()
	wall.position = Vector2(100,0)
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20,100)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	var leader = encounter.actors[0]
	leader.combat_target = player
	check(not encounter.can_see(leader,player),"Walls block combat LOS")
	leader._gangster_shoot_target(player.global_position)
	check(leader.shots_fired==0,"No projectile fired through solid wall")
	wall.queue_free()
	await physics_frame
	await physics_frame
	check(encounter.can_see(leader,player),"Clear LOS restored after wall removed")
	leader._gangster_shoot_target(player.global_position)
	check(leader.shots_fired==1,"Role fires a real catalog projectile")
	var projectiles := 0
	for child in world.get_children():
		if child.get("owner_body") == leader:
			projectiles += 1
	check(projectiles==1,"SMG projectile physically instantiated")
	leader.take_damage(55,true)
	encounter._physics_process(0.1)
	check(encounter.phase=="reposition","Boss changes behavior after damage, not just inflated health")
	var retreat: Vector2 = encounter.get_tactical_destination(leader,Vector2.ZERO)
	check(retreat.distance_to(Vector2(0,200))>=25 and retreat.distance_to(Vector2(0,200))<=40,"Retreat selects an unoccupied pocket beside authored ally point")
	for actor in encounter.actors:
		actor.take_damage(1000,true)
	encounter._physics_process(0.1)
	encounter._physics_process(20.0)
	check(completions==1 and encounter.get_living_count()==0,"Death completes once; no respawn")
	var territory := TERRITORY.new()
	territory.configure(Rect2(-100,-100,600,600),PackedVector2Array([Vector2(0,300)]))
	world.add_child(territory)
	territory.set_mission_access(true)
	check(territory.combat_target_for(territory.guards[0])==null,"Authorized presence remains peaceful")
	territory.guards[0].take_damage(1,true)
	check(territory.state=="combat" and not territory.get_status().mission_access,"Attacking a guard revokes visitor permission")
	territory.set_mission_access(true)
	territory.set_encounter_active(true)
	territory.report_aggression()
	check(territory.combat_target_for(territory.guards[0])==null,"Finite encounter suppresses ambient interference")
	territory.set_encounter_active(false)
	territory.set_mission_access(false)
	territory.set_defeated(true)
	territory.report_aggression()
	check(territory.get_status().defeated and territory.get_status().living_guards==1,"Defeat persists local peace without deleting population")
	var neighbor := preload("res://world/harbor/cobras/CobraResident.gd").new()
	neighbor.guard = false
	neighbor.profile = 1
	neighbor.position = Vector2(400,400)
	world.add_child(neighbor)
	check(not neighbor.has_beard and not neighbor.has_vest and not neighbor.has_bandana,"Mission neighbor is not rendered as a bearded gang enforcer")
	check(neighbor.shirt_color==Color("627985"),"Civilian palette is visually distinct from the gang")
	print("COBRA ENCOUNTER: %d failure(s)" % failures)
	quit(0 if failures==0 else 1)
