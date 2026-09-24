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
	for chunk in region.chunks.values():
		for child in chunk.get_children():
			if not child is MeshInstance3D or not child.mesh is BoxMesh:
				continue
			if not child.material_override is StandardMaterial3D or child.material_override.albedo_color != Color("737b69"):
				continue
			if not is_equal_approx(child.position.y, -0.15):
				continue
			land_count += 1
			var size: Vector3 = child.mesh.get_aabb().size
			var point: Vector3 = child.global_position
			var bounds := Rect2(Vector2(point.x - size.x * 0.5, point.z - size.z * 0.5), Vector2(size.x, size.z))
			_check(not bounds.intersection(floor).has_area(), "Generic land overlaps the cemetery floor")
			surrounding_land = surrounding_land or bounds.has_point(outside)
	_check(land_count > 0 and surrounding_land, "Surrounding harbor land remains present")
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
