extends SceneTree
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PROJECTILE := preload("res://gameplay/Projectile.gd")
var failures: Array[String] = []
class ExplosionProbe extends Node3D:
	var impacts: Array[Vector3] = []
	func explode(at: Vector3, _radius: float, _damage: float, _shooter: Node3D, _hurt: bool) -> void:
		impacts.append(at)
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("CULVERT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func run() -> void:
	var room = PLACES.create_place("desert_under_culvert")
	root.add_child(room)
	var probe := ExplosionProbe.new()
	root.add_child(probe)
	await physics_frame
	await physics_frame
	check(room.is_floor_clear(room.definition.spawn, .35), "spawn fits the player")
	check(room.is_floor_clear(room.definition.exit, .35), "exit fits the player")
	for item in room.definition.rewards:
		var found := false
		for point in room.reward_points:
			if point.reward.id == item.id:
				found = point.visual.position.is_equal_approx(item.local_position)
		check(found, "reward remains at authored position: "+str(item.id))
	for x in range(-19, 16): check(room.is_floor_clear(Vector3(x, 0, 0), .35), "central aisle x=%d" % x)
	# Raios acima das antigas paredes de dois metros, incluindo a parede da frente escondida.
	for target in [Vector3(0, 2.7, -7), Vector3(0, 2.7, 7), Vector3(-22, 2.7, 0), Vector3(22, 2.7, 0), Vector3(0, 5, 0)]:
		var start := Vector3(0, 2.7, 0)
		var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, target, 1))
		check(not hit.is_empty(), "enclosure blocks high trajectory towards %s" % target)
	var shots: Array[Node3D] = []
	for pair in [[Vector3(-18, 1.5, 0), Vector3(-15, 7, 0)], [Vector3(18, 1.5, 0), Vector3(15, 7, 0)], [Vector3(0, 1.5, -3), Vector3(0, 7, -15)], [Vector3(0, 1.5, 3), Vector3(0, 7, 15)], [Vector3(0, 1.5, 0), Vector3(0, 14, 0)]]:
		var shot := PROJECTILE.new()
		shot.controller = probe
		shot.position = pair[0]
		shot.velocity = pair[1]
		shot.fuse = 2.0
		root.add_child(shot)
		shots.append(shot)
	var escaped := false
	for i in 150:
		await physics_frame
		for shot in shots:
			if is_instance_valid(shot):
				var p: Vector3 = shot.position
				if absf(p.x) > 20.05 or absf(p.z) > 5.05 or p.y > 3.25 or p.y < -.1: escaped = true
	check(not escaped, "five real grenade trajectories stay inside walls and ceiling")
	check(probe.impacts.size() == 5, "all grenades detonate inside")
	var actor := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = .9
	actor.add_child(collider)
	actor.collision_mask = 1
	root.add_child(actor)
	actor.position = Vector3(-17, .05, 0)
	await physics_frame
	check(actor.move_and_collide(Vector3(-2, 0, 0)) == null, "swept body walks from spawn to exit")
	check(actor.move_and_collide(Vector3(-5, 0, 0)) != null, "west wall stops body beyond exit")
	actor.position = Vector3(12.6, .05, .8)
	check(actor.move_and_collide(Vector3(0, 0, 2)) != null, "workbench blocks the whole body")
	print("CULVERT_ENCLOSURE failures=", failures)
	quit(0 if failures.is_empty() else 1)
