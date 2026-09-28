extends SceneTree
## Physical cemetery geometry and real service actors, independent of unrelated
## world-editor imports. Complements test_cemetery_npcs (integrated Main).
const SERVICE := preload("res://gameplay/urban_v1/CemeteryOperations.gd")
const GEOMETRY := preload("res://world/regions/OriginalCemetery3D.gd")

class Yard extends Node3D:
	var player: Node3D
	var gameplay: Node
	var driving := {"occupied": false}

class Session extends RefCounted:
	var world: Node3D
	var state := {"region_id": "harbor", "place_id": ""}
	var room: Node3D

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: return
	failures.append(label)
	push_error(label)

func run() -> void:
	Engine.time_scale = 3.0
	for plot in [0, 1, 2, 11]:
		if "--plot=0" in OS.get_cmdline_user_args() and plot != 0: continue
		var yard := Yard.new()
		root.add_child(yard)
		yard.player = Node3D.new()
		yard.add_child(yard.player)
		yard.player.position = SERVICE.CENTER + Vector3(5,0,13)
		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(100,.2,100)
		floor_shape.shape = box
		floor_body.add_child(floor_shape)
		floor_body.position = SERVICE.CENTER - Vector3.UP*.12
		yard.add_child(floor_body)
		var geometry := GEOMETRY.new()
		geometry.position = SERVICE.CENTER
		yard.add_child(geometry)
		var session := Session.new()
		session.world = yard
		var service := SERVICE.new()
		service.configure(session)
		yard.add_child(service)
		service.set_process(false)
		var identity := "route:%d" % plot
		service.register_synthetic_case(identity, "Visitante")
		service.cases[identity].plot = plot
		service._start_trip(identity)
		for frame in 1500:
			await physics_frame
			service._tick_trip(.05)
			if service.trip_phase == "working": break
		check(service.trip_phase == "working", "All guests reach plot %d without blocked aisle" % plot)
		if service.trip_phase != "working":
			for guest in service.mourners: print("BLOCKED_ARRIVAL plot=",plot," position=",guest.position," index=",guest.route_index)
		else:
			service._tick_trip(5.1)
			for frame in 1500:
				await physics_frame
				service._tick_trip(.05)
				if service.trip_identity.is_empty(): break
			check(service.trip_identity.is_empty(), "All guests leave plot %d through the gate" % plot)
			if not service.trip_identity.is_empty():
				print("BLOCKED_WORKER plot=",plot," position=",service.mortician.position," index=",service.mortician.route_index," route=",service.mortician.route)
				print("BLOCKED_KEEPER position=",service.keeper.position," index=",service.keeper.route_index)
				for guest in service.mourners: print("BLOCKED_EXIT plot=",plot," position=",guest.position," index=",guest.route_index)
		print("CEMETERY_ROUTE plot=",plot," phase=",service.trip_phase)
		yard.free()
		await process_frame
	Engine.time_scale = 1.0
	print("CEMETERY_ROUTES ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
