extends SceneTree
## Physical integration: stream the actual strip, not a duplicate prop layout.
const REGION := preload("res://world/desert/DesertRegion.gd")
const MEET := preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("DRAG_SPECTATORS timeout"); quit(3))
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var records := MEET.strip_records()
	var spectators: Array[Dictionary] = []
	var cars := 0
	var barriers := 0
	var sides: Dictionary = {}
	for record in records:
		var point: Vector3 = record.position
		_check(LAYOUT.DRAG_STRIP_BOUNDS.has_point(Vector2(point.x, point.z)), "Authored strip record remains in reserved shoulder")
		if record.type == "strip_spectator":
			spectators.append(record)
			sides[signf(point.z - LAYOUT.DRAG_START.z)] = true
			_check(absf(point.z - LAYOUT.DRAG_START.z) >= 10.0, "Spectators stay outside both driving lanes")
		elif record.type == "strip_car": cars += 1
		elif record.type == "barrier": barriers += 1
	_check(spectators.size() == 24 and cars == 12 and barriers == 12, "Finite 24-person, 12-car roadside budget")
	_check(sides.size() == 2, "Spectator pockets occupy both shoulders")
	var region := REGION.new()
	region.initial_focus = spectators[0].position
	root.add_child(region)
	for index in range(0, spectators.size(), 4):
		var center: Vector3 = spectators[index].position
		region.set_focus(center)
		for frame in 800:
			if region.is_streaming_idle(): break
			await process_frame
		await physics_frame
		await physics_frame
		_check(region.is_streaming_idle(), "Roadside pocket finishes streaming")
		for slot in range(index, index + 4):
			var point: Vector3 = spectators[slot].position
			_check(_floor(point), "Spectator has physical floor")
			_check(_clear(point), "Spectator capsule clears cars and barriers")
		for offset in [-12.0, 0.0, 12.0]:
			for lane in [-2.0, 2.0]:
				var point := Vector3(center.x + offset, 0, LAYOUT.DRAG_START.z + lane)
				_check(_floor(point) and _clear(point), "Both race lanes retain floor and obstacle clearance")
		var live := get_nodes_in_group("desert_drag_strip_spectator")
		_check(not live.is_empty() and live.size() <= spectators.size(), "Streaming owns a bounded spectator population")
		for actor in live:
			_check(actor.has_method("receive_damage") and not actor.get_meta("invulnerable", false), "Spectators retain ordinary civilian damage behavior")
	region.release_chunks()
	await process_frame
	await process_frame
	_check(get_nodes_in_group("desert_drag_strip_spectator").is_empty(), "Unloading chunks releases spectators")
	region.free()
	for failure in failures: push_error(failure)
	print("DRAG_SPECTATORS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _floor(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .4, point - Vector3.UP * .4, 1)
	return not root.world_3d.direct_space_state.intersect_ray(query).is_empty()

func _clear(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.78
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = point + Vector3.UP * .96
	query.collision_mask = 1
	return root.world_3d.direct_space_state.intersect_shape(query, 1).is_empty()
