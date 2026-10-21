extends SceneTree
## Focused native Vance contract: shared human rig, solid body and threat pose.
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
const REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
var failures: Array[String] = []

class ShopGameplay extends Node:
	signal weapon_fired(weapon_id: String, origin: Vector3)
	signal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(origin: Vector3, radius: float, source: Node)
	var emergency: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var npc = ART.gunsmith(stage, true)
	await frames(3)
	check(npc.name == "VanceMilitaryGunsmith", "service lookup retains Vance identity")
	check(npc.get_script().resource_path == "res://world/places/VanceGunsmithModel.gd", "Vance uses modern shared civilian presentation")
	check(npc.scale.is_equal_approx(Vector3.ONE), "human rig has no legacy nonuniform multiplier")
	check(npc.get("skeleton") != null and npc.get("mesh_node") != null, "real imported human body and skeleton are active")
	var dante: Node3D = preload("res://assets/dante.glb").instantiate()
	dante.scale = Vector3.ONE * 1.03 # Actor's production player scale.
	stage.add_child(dante)
	var dante_mesh: MeshInstance3D = dante.find_child("Mesh0", true, false)
	if npc.get("mesh_node") != null and dante_mesh != null:
		var body_mesh: MeshInstance3D = npc.mesh_node
		var body_bounds: AABB = body_mesh.global_transform * body_mesh.get_aabb()
		var dante_bounds: AABB = dante_mesh.global_transform * dante_mesh.get_aabb()
		print("VANCE_HUMAN_SCALE height=", body_bounds.size.y, " dante=", dante_bounds.size.y)
		check(body_bounds.size.y / dante_bounds.size.y > .85 and body_bounds.size.y / dante_bounds.size.y < 1.15, "Vance height matches Dante's production body")
	dante.queue_free()
	check(npc.find_children("*", "SubViewport", true, false).is_empty(), "staff shares the native room renderer")
	var solid := npc.get_node_or_null("VanceBody") as StaticBody3D
	check(is_instance_valid(solid), "staff has a physical body")
	if solid != null:
		var shape: CollisionShape3D = solid.get_node("BodyCapsule")
		var capsule := shape.shape as CapsuleShape3D
		check(capsule != null and is_equal_approx(capsule.height, 1.76), "staff capsule follows shared human height")
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, .9, 1), Vector3(0, .9, -1), 2)
		var hit: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider == solid, "physics ray hits Vance torso")
	var gameplay := ShopGameplay.new()
	stage.add_child(gameplay)
	var reaction: Node = REACTION.install(npc, npc, gameplay)
	check(reaction != null, "service reaction installs on the modern rig")
	gameplay.npc_gunfire.emit(Vector3(0, 1, 2), Vector3.FORWARD, null)
	await frames(4)
	check(npc.get_meta("workplace_threatened", false) and reaction.body == npc, "nearby threat claims the actual visible body")
	check(npc.hand_provider.is_valid() and npc.hand_targets[0] is Vector3, "articulated hands shield Vance")
	reaction.quiet_left = 0.0
	await frames(4)
	check(not npc.get_meta("workplace_threatened", false) and not npc.hand_provider.is_valid(), "quiet restores staff pose and service availability")
	var room = preload("res://world/places/PlaceCatalog.gd").create_place("harbor_ammunation")
	room.position.x = 30
	stage.add_child(room)
	await frames(3)
	var resident: Node3D = room.find_child("VanceMilitaryGunsmith", true, false)
	check(resident != null and resident.get_script().resource_path == "res://world/places/VanceGunsmithModel.gd", "production Harbor room owns modern Vance")
	if resident != null:
		var local: Vector3 = room.to_local(resident.global_position)
		check(room.is_floor_clear(local, .3), "Vance stands on clear staff floor outside room furniture")
		var probe := PhysicsShapeQueryParameters3D.new()
		probe.shape = CapsuleShape3D.new()
		probe.shape.radius = .27
		probe.shape.height = 1.76
		probe.transform = Transform3D(Basis.IDENTITY, resident.global_position + Vector3(0, .9, 0))
		probe.collision_mask = 1
		check(stage.get_world_3d().direct_space_state.intersect_shape(probe).is_empty(), "Vance's full capsule does not overlap scenery")
	room.queue_free()
	await frames(2)
	check(not is_instance_valid(resident), "room removal frees its resident and physical body")
	stage.queue_free()
	await frames(2)
	print("AMMUNATION_VANCE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
