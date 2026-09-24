extends SceneTree
class Rig extends Node:
	var material := ShaderMaterial.new()
class Actor extends Node:
	var viewport_3d: SubViewport
	var model_root: Node3D
	var meshy_rig: Rig
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	var actor := Actor.new()
	root.add_child(actor)
	actor.viewport_3d = SubViewport.new()
	actor.viewport_3d.own_world_3d = true
	actor.add_child(actor.viewport_3d)
	actor.model_root = Node3D.new()
	actor.viewport_3d.add_child(actor.model_root)
	actor.meshy_rig = Rig.new()
	actor.model_root.add_child(actor.meshy_rig)
	actor.meshy_rig.material.shader = load("res://scripts/player/meshy_dante_outfit.gdshader")
	var mesh := MeshInstance3D.new()
	actor.model_root.add_child(mesh)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 35, 0)
	key.shadow_enabled = true
	actor.viewport_3d.add_child(key)
	var original := key.transform
	var destination := SubViewport.new()
	destination.own_world_3d = true
	root.add_child(destination)
	var room_light := DirectionalLight3D.new()
	destination.add_child(room_light)
	var old_mask := room_light.light_cull_mask
	var adapter := preload("res://scripts/player/ActorSharedLighting.gd").new()
	adapter.configure(actor, destination, Basis(Vector3.RIGHT, 0.2))
	check(key.get_parent() == destination, "personal lighting follows shared depth without duplication")
	check(mesh.layers == adapter.ACTOR_LAYER and key.light_cull_mask == adapter.ACTOR_LAYER, "personal lights affect only admitted actor")
	check((room_light.light_cull_mask & adapter.ACTOR_LAYER) == 0, "station/car key cannot tint actor a second time")
	check(not key.shadow_enabled, "transfer does not add shadow rendering")
	adapter.restore()
	check(key.get_parent() == actor.viewport_3d and key.transform.is_equal_approx(original), "exit restores personal light parent and direction")
	check(key.shadow_enabled, "exit restores original street silhouette shadows")
	check(mesh.layers == 1 and room_light.light_cull_mask == old_mask, "exit restores original mesh and room masks")
	adapter.restore()
	check(adapter.lights.is_empty(), "cleanup is idempotent")
	actor.queue_free()
	destination.queue_free()
	await process_frame
	print("ACTOR_SHARED_LIGHTING failures=", failures)
	quit(0 if failures == 0 else 1)
