extends SceneTree

const REGION := preload("res://world/regions/NativeRegion.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var center: Vector3 = CEMETERY.world_position()
	var region := REGION.build_region("harbor", center)
	fixture.add_child(region)
	for frame in 12:
		await process_frame
	await physics_frame
	var half: Vector2 = CEMETERY.LOT_SIZE * CEMETERY.SCALE * 0.5
	var floor := Rect2(Vector2(center.x, center.z) - half, half * 2.0)
	var land_count := 0
	var surrounding_land := false
	var outside := Vector2(floor.position.x - 1.0, center.z)
	# Request the neighbouring cell as gameplay does on entry. Twelve frames
	# cannot guarantee its queued streaming job has finished construction.
	region._ensure_chunk(region._cell(Vector3(outside.x,0,outside.y)))
	await physics_frame
	await process_frame
	for chunk in region.chunks.values():
		for child in chunk.get_children():
			# Desde 2026-10-13 o chão base "Land" é uma malha recortada (camada única de chão); a pegada
			# física continua sendo a caixa de colisão de 0,3 m, filha do nó.
			# A chunk can contain several disjoint base pieces. Godot renames
			# repeated Land nodes; identify support by its material and collider.
			if not child is MeshInstance3D:
				continue
			# _material() multiplica a cor pelo relevo (commit c6685136): comparar com o material do chão
			# base que a própria região entrega, não com a cor crua.
			if child.material_override != region._material(Color("737b69")):
				continue
			var body := child.get_child(0) as StaticBody3D if child.get_child_count() > 0 else null
			if body == null or not is_equal_approx(body.global_position.y, -0.15):
				continue
			land_count += 1
			var size: Vector3 = ((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
			var point: Vector3 = body.global_position
			var bounds := Rect2(Vector2(point.x - size.x * 0.5, point.z - size.z * 0.5), Vector2(size.x, size.z))
			_check(not bounds.intersection(floor).has_area(), "Generic land overlaps the cemetery floor")
			surrounding_land = surrounding_land or bounds.has_point(outside)
	_check(land_count > 0 and surrounding_land, "Surrounding harbor land remains present")
	var outside_hit := fixture.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(outside.x,1,outside.y),Vector3(outside.x,-1,outside.y),1))
	_check(not outside_hit.is_empty(),"Surrounding ground has physical support after streaming entry")
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 2.0, center + Vector3.DOWN, 1)
	var hit := fixture.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider.name == "CemeterySolids", "Cemetery floor remains the physical support")
	print("CEMETERY_GROUND_OVERLAP failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if value:
		return
	failures.append(message)
	push_error(message)
