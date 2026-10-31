extends SceneTree
## Só regressão de resolução/cache do dono; a folga física da escada é coberta
## por test_harbor_service_roofs.gd na cena real.
var checks := 0
var failures: Array[String] = []

class Room extends Node3D:
	var spawn_position := Vector3.ZERO
	var interior_spawn := Vector3.ZERO
	var model: Node3D

class GarageRoom extends Node3D:
	var spawn_position := Vector3.ZERO
	var interior_spawn := Vector3.ZERO
	var room: Node3D

class AuthoredAccess extends Node3D:
	var roof_access_point := Vector3(4.86,0,2.0)
	var roof_access_yaw := PI*.5
	var roof_access_route: Array[Vector3] = [Vector3(3.5,0,2.5)]

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
	var sweep_allowed := true
	func _sweep_clear(_from: Vector3, _to: Vector3) -> bool:
		return sweep_allowed
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
	# MaciotaPlace real guarda a sala em `room` (WorkshopProps), que autora a escada na parede
	# dos fundos; o spawn deixa de decidir onde ela fica.
	var garage := GarageRoom.new()
	fixture.add_child(garage)
	garage.rotation.y = PI * .5
	garage.interior_spawn = Vector3(30, 1, 12)
	var workshop := AuthoredAccess.new()
	garage.add_child(workshop)
	garage.room = workshop
	session.room = garage
	runtime._update_ground_access()
	check(runtime.access_owner == garage and runtime.access_point.is_equal_approx(workshop.to_global(workshop.roof_access_point)+Vector3.UP*.04), "garage uses the workshop's authored wall access")
	check(runtime.access_route.size()==2, "garage keeps the authored approach route")
	session.room = room_a
	# Uma casa ou loja mobiliada é dona do acesso arquitetônico, independente do
	# spawn. Uma rota autoral bloqueada nunca pode recair para dentro da sala.
	session.state.place_id = "cobra_leader_house"
	var authored := AuthoredAccess.new()
	room_a.add_child(authored)
	room_a.model = authored
	runtime._update_ground_access()
	var expected_authored := authored.to_global(authored.roof_access_point)+Vector3.UP*.04
	check(runtime.access_point.is_equal_approx(expected_authored), "wall access uses model coordinates rather than spawn offsets")
	check((runtime.access_frame*Vector3.BACK).is_equal_approx(authored.global_basis*Vector3.RIGHT), "authored orientation points into the side wall")
	check(runtime.access_route.size()==2 and runtime.access_route[0].is_equal_approx(authored.to_global(authored.roof_access_route[0])+Vector3.UP*.04), "authored approach waypoints preserve room transform")
	runtime._release_access()
	runtime.sweep_allowed = false
	var built_before := runtime.ladders_built
	runtime._update_ground_access()
	check(runtime.access_visual == null and runtime.ladders_built==built_before, "blocked authored route cannot create a floating fallback ladder")
	check(runtime.access_route.is_empty(), "released access does not retain a route from the old owner")
	fixture.queue_free()
	await process_frame
	print("ROOF_ACCESS_OWNER checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
