extends SceneTree

const REGION := preload("res://world/regions/NativeRegion.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _floor_at(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 3.0, 1)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else -INF

func _crosses(from: Vector3, to: Vector3, vehicle := false) -> bool:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var shape := CollisionShape3D.new()
	if vehicle:
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.2, 2.8)
		shape.shape = box
		shape.position.y = 0.62
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.7
		shape.shape = capsule
		shape.position.y = 0.88
	actor.add_child(shape)
	root.add_child(actor)
	actor.global_position = from
	var collision := actor.move_and_collide(to - from, true)
	actor.free()
	return collision == null

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Mountain road access test requires --no-save")
		quit(2)
		return
	var region := REGION.build_region("mountain", CATALOG._at(Vector2(6550, 515), "mountain"))
	root.add_child(region)
	for _frame in 4: await physics_frame
	for road in region.roads:
		if not str(road.id).begins_with("mountain_track_"): continue
		var points: PackedVector3Array = road.points
		var a: Vector3 = points[0].lerp(points[1], 0.62)
		var b: Vector3 = points[1].lerp(points[2], 0.38)
		for sample in [a, b]:
			var center: Vector3 = sample
			region.prepare_collision_at(center)
			var direction := (points[1] - points[0]).normalized()
			var lateral := Vector3(-direction.z, 0, direction.x)
			for side in [-1.0, 1.0]:
				var road_point := center
				var shoulder_point: Vector3 = center + lateral * float(side) * (float(road.width) * 0.5 + 2.0)
				region.prepare_collision_at(shoulder_point)
				var road_y := _floor_at(road_point)
				var shoulder_y := _floor_at(shoulder_point)
				var label := "%s at %s side %s" % [road.id, str(center), str(side)]
				_check(road_y > -INF and shoulder_y > -INF, label + ": both floors exist")
				if road_y == -INF or shoulder_y == -INF: continue
				_check(absf(road_y - shoulder_y) < 0.035, label + ": street and shoulder are level (%.3f versus %.3f)" % [road_y, shoulder_y])
				_check(_crosses(shoulder_point + Vector3.UP * shoulder_y, road_point + Vector3.UP * shoulder_y), label + ": can reenter from shoulder")
				_check(_crosses(road_point + Vector3.UP * road_y, shoulder_point + Vector3.UP * road_y), label + ": can leave toward shoulder")
				_check(_crosses(shoulder_point + Vector3.UP * shoulder_y, road_point + Vector3.UP * shoulder_y, true), label + ": vehicle can reenter from shoulder")
				_check(_crosses(road_point + Vector3.UP * road_y, shoulder_point + Vector3.UP * road_y, true), label + ": vehicle can leave toward shoulder")
	region.free()
	for failure in failures: push_error(failure)
	print("MOUNTAIN_SIDE_ROAD_ACCESS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
