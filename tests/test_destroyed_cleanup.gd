extends SceneTree
## Requires a rendering backend: headless Dummy does not retain MultiMesh transforms.
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const PROPS := preload("res://gameplay/street_physics/FragileProps3D.gd")
const UNIT := preload("res://gameplay/dispatch/DispatchUnit.gd")
class Victim extends CharacterBody3D:
	var dead := true
	var is_player := false
class GameplayFixture extends Node:
	var stars := 2
class DispatchFixture extends Node3D:
	var gameplay := GameplayFixture.new()
	func is_unseen(_point: Vector3) -> bool: return false
	func emit_dispatch_event(_event: String, _details: Dictionary) -> void: pass
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor := Victim.new()
	world.add_child(actor)
	var visual := preload("res://gameplay/PoliceModel.gd").new()
	actor.add_child(visual)
	visual.equip("ak47")
	await process_frame
	await process_frame
	visual.update_pose(0.1, true, false, 0.0, 0.0)
	FALL.apply_fall(actor, visual, Vector3.BACK)
	check(visual.weapon.get_parent() == actor, "Weapon released when death starts")
	check(absf(visual.weapon.global_basis.z.normalized().y) < 0.01, "Barrel lies parallel to ground")
	check(not visual.body.hand_provider.is_valid(), "Dead hands no longer follow aiming IK")
	await create_timer(1.3).timeout
	check(not visual.body.is_processing(), "Fall owns body pose")
	check(absf(visual.body.upper_arms[0].rotation.x) < 0.8, "Resting arm is no longer aiming")
	var mesh: GeometryInstance3D = visual.body.find_children("*", "MeshInstance3D", true, false)[0]
	await create_timer(8.0).timeout
	check(is_instance_valid(actor) and mesh.transparency == 0.0, "Corpse remains before ten seconds")
	await create_timer(1.5).timeout
	check(is_instance_valid(actor) and mesh.transparency > 0.0 and mesh.transparency < 1.0, "Corpse fades gradually after ten seconds")
	await create_timer(1.5).timeout
	check(not is_instance_valid(actor), "Corpse and gun are freed after fade")
	var alive := Victim.new()
	alive.dead = false
	alive.set_meta("street_pose_owned", true)
	world.add_child(alive)
	var living_visual := Node3D.new()
	alive.add_child(living_visual)
	FALL.apply_fall(alive, living_visual)
	check(not alive.has_meta("destroyed_cleanup"), "Nonlethal knockdown is not removed")
	var car := preload("res://scripts/Vehicle.gd").new()
	world.add_child(car)
	car.set_physics_process(false)
	car.health = 0
	car.set_meta("garage_reward", true)
	car.set_meta("wreck_hold", true)
	car._tick_wreck(9.9)
	check(car._wreck_fade < 0.0, "Car remains before ten seconds")
	car._tick_wreck(0.1)
	car._tick_wreck(1.0)
	check(car._wreck_fade > 0.0 and car._wreck_meshes[0].transparency > 0.0, "Owned wreck fades despite dispatch hold")
	car.repair()
	check(car._wreck_fade < 0 and car.collision_layer == 4, "Repair cancels fade and restores collisions")
	car.health = 0
	car._tick_wreck(10.0)
	car._tick_wreck(1.0)
	car._tick_wreck(1.0)
	await process_frame
	check(not is_instance_valid(car), "Destroyed car removed")
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = BoxMesh.new()
	batch.instance_count = 2
	batch.set_instance_transform(0, Transform3D.IDENTITY)
	var intact := Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))
	batch.set_instance_transform(1, intact)
	PROPS._fade_post({"multimesh": batch, "index": 0, "extra": [], "chunk": weakref(world)})
	check(batch.get_instance_transform(0).basis.get_scale().is_zero_approx(), "Fallen post transferred to fade geometry")
	check(batch.get_instance_transform(1) == intact, "Intact neighboring post preserved")
	var dispatch := DispatchFixture.new()
	world.add_child(dispatch)
	dispatch.add_child(dispatch.gameplay)
	var unit := UNIT.new()
	unit.controller = dispatch
	unit.service = "police"
	unit.wrecked = true
	unit.officers = [alive]
	unit.tick(1.0)
	check(not unit.finished and not alive.is_queued_for_deletion(), "Officers survive removal of their wreck")
	alive.dead = true
	unit.tick(1.0)
	check(unit.finished, "Dispatch finishes safely after wreck and crew are gone")
	world.queue_free()
	await process_frame
	print("DESTROYED_CLEANUP checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
