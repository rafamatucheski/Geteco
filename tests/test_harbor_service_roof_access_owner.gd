extends SceneTree
## Owner resolution/cache regression only; physical ladder clearance is covered
## by test_harbor_service_roofs.gd in the actual scene.
var checks := 0
var failures: Array[String] = []

class Room extends Node3D:
	var spawn_position := Vector3.ZERO
	var interior_spawn := Vector3.ZERO

class Session extends RefCounted:
	var state := {"region_id":"harbor", "place_id":"harbor_supermarket"}
	var world := {"driving":{"occupied":false}}
	var room: Node3D
	var clearance_checks := 0
	func position_clear(_point: Vector3) -> bool:
		clearance_checks += 1
		return true

class RuntimeProbe extends "res://runtime/HarborServiceRoofRuntime.gd":
	var ladders_built := 0
	func _sweep_clear(_from: Vector3, _to: Vector3) -> bool:
		return true
	func _ladder_fits(_point: Vector3, _frame: Basis) -> bool:
		return true
	func _make_ladder() -> void:
		ladders_built += 1
		access_visual = Node3D.new()
		add_child(access_visual)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("ROOF_ACCESS_OWNER ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var room_a := Room.new()
	fixture.add_child(room_a)
	room_a.rotation.y = PI * .5
	room_a.spawn_position = Vector3(10, 2, -4)
	var room_b := Room.new()
	fixture.add_child(room_b)
	room_b.rotation.y = -PI * .5
	room_b.spawn_position = Vector3(-20, 5, 8)
	var session := Session.new()
	session.room = room_a
	var runtime := RuntimeProbe.new()
	fixture.add_child(runtime)
	runtime.session = session
	check(runtime.owner == null, "dynamically added runtime has no scene owner")
	runtime._update_ground_access()
	check(runtime.ladders_built == 1, "valid service room builds access without runtime.owner")
	check(runtime.access_owner == room_a, "access belongs to current room")
	check(runtime.access_definition.get("id", "") == "harbor_supermarket", "service identity retained")
	var offset := Vector3(2, 0, -.5)
	var expected_a := room_a.spawn_position + room_a.global_basis * offset + Vector3.UP * .04
	check(runtime.access_point.is_equal_approx(expected_a), "placement uses room spawn and rotation")
	var first_visual := runtime.access_visual
	var first_clearance_checks := session.clearance_checks
	runtime._update_ground_access()
	check(runtime.access_visual == first_visual and runtime.ladders_built == 1, "same room reuses access")
	check(session.clearance_checks == first_clearance_checks, "cached room skips repeated clearance queries")
	session.room = room_b
	runtime._update_ground_access()
	check(runtime.ladders_built == 2 and runtime.access_visual != first_visual, "same service in replacement room rebuilds access")
	check(first_visual.is_queued_for_deletion(), "old room access is released")
	check(runtime.access_owner == room_b, "replacement access belongs to replacement room")
	var expected_b := room_b.spawn_position + room_b.global_basis * offset + Vector3.UP * .04
	check(runtime.access_point.is_equal_approx(expected_b), "replacement room supplies spawn and rotation")
	session.room = null
	runtime._update_ground_access()
	check(runtime.access_visual == null and runtime.access_owner == null, "missing room releases access without dereferencing null")
	check(runtime.access_definition.is_empty() and not runtime.access_point.is_finite(), "missing room clears cached destination")
	check(runtime.ladders_built == 2, "missing room does not create access")
	session.state.place_id = "maciota"
	session.room = room_a
	room_a.interior_spawn = Vector3(30, 1, 12)
	runtime._update_ground_access()
	var expected_garage := room_a.interior_spawn + room_a.global_basis * offset + Vector3.UP * .04
	check(runtime.access_owner == room_a and runtime.access_point.is_equal_approx(expected_garage), "garage uses its interior spawn with current room owner")
	fixture.queue_free()
	await process_frame
	print("ROOF_ACCESS_OWNER checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
