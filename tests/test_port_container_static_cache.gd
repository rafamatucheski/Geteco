extends SceneTree
## Isolated real meshes, bodies, physics sweeps and instance-owned interaction.
## Rendered visual acceptance and the full service flow are separate tests.
const CONTAINER = preload("res://world/regions/LootablePortContainer.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func settled() -> void:
	await process_frame
	await physics_frame
	await physics_frame
	await process_frame

func spawn(point: Vector3, size: Vector2):
	var cargo = CONTAINER.new()
	stage.add_child(cargo)
	cargo.build(point,size)
	return cargo

func collect(node: Node3D, transform: Transform3D, result: Dictionary) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion() or not child is Node3D: continue
		var pose: Transform3D = transform*child.transform
		if child is MeshInstance3D:
			var surfaces: Array = []
			for index in child.mesh.get_surface_count():
				surfaces.append(hash(child.mesh.surface_get_arrays(index)))
			var material: StandardMaterial3D = child.material_override
			result.meshes.append([pose,surfaces,material.albedo_color,material.roughness,material.metallic,material.albedo_texture,child.cast_shadow,child.layers])
		if child is StaticBody3D:
			for shape in child.get_children():
				if shape is CollisionShape3D:
					result.solids.append([str(child.name),pose*shape.transform,shape.shape.get_class(),shape.shape.size if shape.shape is BoxShape3D else Vector3.ZERO,shape.disabled,child.collision_layer,child.collision_mask])
		collect(child,pose,result)

func signature(cargo) -> Dictionary:
	var result := {"meshes":[],"solids":[]}
	collect(cargo,Transform3D.IDENTITY,result)
	return result

func shared_batch_geometry(first, second) -> bool:
	var left: Array = first.roof.find_children("*","MeshInstance3D",true,false)
	var right: Array = second.roof.find_children("*","MeshInstance3D",true,false)
	if left.size() != right.size() or left.is_empty(): return false
	for index in left.size():
		if left[index] == right[index] or left[index].mesh != right[index].mesh: return false
	return true

func door_body(cargo) -> StaticBody3D:
	return cargo.doors[0].get_node("DoorSolid") as StaticBody3D

func sweep(cargo, start: Vector3, motion: Vector3) -> bool:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = .86
	actor.add_child(collider)
	stage.add_child(actor)
	actor.global_position = cargo.to_global(start)
	await physics_frame
	var collision := actor.move_and_collide(motion)
	actor.free()
	return collision != null

func run() -> void:
	create_timer(45,true,false,true).timeout.connect(func(): push_error("CONTAINER CACHE TIMEOUT"); quit(3))
	stage = Node3D.new()
	root.add_child(stage)
	# Fresh process and no Main/save service: no player data is loaded or written.
	CONTAINER._static_parts.clear()
	var size := Vector2(20.625,4.0625)
	var first = spawn(Vector3.ZERO,size)
	await settled()
	var original := signature(first)
	var second = spawn(Vector3(30,0,0),size) # Same palette and upper variant.
	await settled()
	check(original == signature(second),"cache hit preserves every mesh transform/material and collider")
	check(shared_batch_geometry(first,second),"cache hit shares batched geometry, never live mesh nodes")
	check(first.doors[0] != second.doors[0] and door_body(first) != door_body(second),"hinges and collision bodies belong to each instance")
	check(first.contents != second.contents and first.lid != second.lid,"loot chest and lid remain instance-owned")
	check(first.get_node("RearCrateSolid") != second.get_node("RearCrateSolid"),"cargo layout solids remain instance-owned")
	check(await sweep(second,Vector3(0,.04,-4),Vector3(0,0,5)),"cached side wall blocks swept actor")
	check(await sweep(second,Vector3(size.x*.5+2,.04,-size.y*.25),Vector3(-4,0,0)),"cached closed door blocks swept actor")
	first.apply_state({"opened":true,"looted":true,"cycle":1})
	await settled()
	check(first.opened and first.looted and not second.opened and not second.looted,"opening and looting one instance cannot alter another")
	check(not is_zero_approx(first.doors[0].rotation.y) and is_zero_approx(second.doors[0].rotation.y),"door rotation and its body stay local")
	check(is_zero_approx(second.lid.rotation.x) and first.lid.rotation.x < -.5,"lid animation state is local")
	second.apply_state({"opened":true,"looted":false,"cycle":0})
	await settled()
	var aisle_blocked: bool = await sweep(second,Vector3(size.x*.5+2,.04,0),Vector3(-4,0,0))
	check(not aisle_blocked,"cached opened doors leave the original aisle traversable")
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(15,18,15)
	first.set_revealed(true,camera)
	await create_timer(.4).timeout
	var first_roof: Array = first.roof.find_children("*","MeshInstance3D",true,false)
	var second_roof: Array = second.roof.find_children("*","MeshInstance3D",true,false)
	var independent := first_roof.size() == second_roof.size() and not first_roof.is_empty()
	for index in first_roof.size():
		independent = independent and not first_roof[index].visible and second_roof[index].visible
		independent = independent and first_roof[index].material_override != second_roof[index].material_override
		independent = independent and is_equal_approx(second_roof[index].material_override.albedo_color.a,1.0)
	check(independent,"Mobile fade owns private materials and leaves the other roof opaque")
	var third = spawn(Vector3(60,0,0),size)
	await settled()
	check(original == signature(third),"new cache hit is pristine after older instance changed state and faded")
	first.set_revealed(false,camera)
	await create_timer(.4).timeout
	var restored := true
	for mesh in first_roof:
		restored = restored and mesh.visible and is_equal_approx(mesh.material_override.albedo_color.a,1.0) and mesh.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	check(restored,"leaving restores the same opaque roof materials")
	# Exercise independent cache keys, including an upper container and its absence.
	for point in [Vector3(1,0,20),Vector3(2,0,40),Vector3(3,0,60)]:
		var cold = spawn(point,size)
		await settled()
		var warm = spawn(point+Vector3(30,0,0),size)
		await settled()
		check(signature(cold) == signature(warm) and shared_batch_geometry(cold,warm),"palette/upper variant preserves exact geometry: "+str(point.x))
		cold.free()
		warm.free()
	var smaller = spawn(Vector3(90,0,0),Vector2(12.19,2.44))
	await settled()
	check(signature(smaller).meshes != original.meshes,"dimensions never reuse incompatible geometry")
	print("PORT_CONTAINER_STATIC_CACHE checks=",checks," failures=",JSON.stringify(failures))
	stage.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
