extends SceneTree

const REGION := preload("res://world/regions/NativeRegion.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const WATER_STEPS := preload("res://runtime/world/WaterSteps.gd")

var errors: Array[String] = []
func check(ok: bool,label: String) -> void:
	if not ok: errors.append(label)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var wet_point: Vector3 = CATALOG._at(Vector2(7000,100),"mountain")
	var dry_point: Vector3 = CATALOG._at(Vector2(6950,-250),"mountain")
	var region = REGION.build_region("mountain",wet_point)
	root.add_child(region)
	region.prepare_collision_at(wet_point)
	var alpine: Node3D
	for node in get_nodes_in_group("native_water_surface"):
		if node.get_parent() != null and region.is_ancestor_of(node) and node.variant == "alpine": alpine = node
	check(alpine != null,"alpine lake streamed into playable area")
	if alpine != null:
		check(alpine.contains_water(wet_point),"feet inside alpine water polygon")
		check(not alpine.contains_water(dry_point),"Ammu-Nation access remains dry")
		var surface := alpine.get_node_or_null("AlpineWater") as MeshInstance3D
		check(surface != null and surface.material_override is ShaderMaterial,"water is a shaded geometric surface")
		if surface != null and surface.mesh != null:
			check(surface.mesh.get_faces().size() > 100,"water has wave-ready tessellation")
	var actor := CharacterBody3D.new()
	actor.name = "WaterContactActor"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = .9
	actor.add_child(shape)
	root.add_child(actor)
	actor.global_position = wet_point + Vector3.UP * 2.0
	for i in 120:
		await physics_frame
		actor.velocity.y -= 9.8/60.0
		actor.move_and_slide()
	check(actor.is_on_floor(),"actor lands on walkable ground beneath water")
	# O lago virou bacia (LakeBasins, 0,6 m): o chão fica até 0,6 m abaixo do ponto nominal, nunca acima.
	var feet_dy := actor.global_position.y-wet_point.y
	check(feet_dy > -.65 and feet_dy < .25 and Vector2(actor.global_position.x-wet_point.x,actor.global_position.z-wet_point.z).length() < .25,"actor feet remain within shallow water depth")
	var steps = WATER_STEPS.new()
	root.add_child(steps)
	check(steps.actor_step(actor,false,false),"water step emits wet contact")
	check(steps.wet_steps > 0 and not steps.marks.is_empty(),"water step leaves splash marks")
	actor.global_position = dry_point
	check(not steps.actor_step(actor,false,false),"dry access does not emit a water step")
	steps.free()
	actor.free()
	region.free()
	print("MOUNTAIN_WATER_CONTACT failures=",errors)
	quit(0 if errors.is_empty() else 1)
