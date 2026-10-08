extends "res://tests/test_armored_guard_service_path.gd"
const ROAD := preload("res://world/desert/DesertRoadGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
class Transport extends "res://gameplay/armored/ArmoredTransport.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _ground_at(_point: Vector3) -> bool: return true
	func _update_crew() -> void: pass
func _initialize() -> void:
	create_timer(45).timeout.connect(func(): check(false,"bounded physical ramp admission"); quit(3))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("ARMORED_RAMP ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	for scenario in ["north","south","obstacle","missing","too_far","physical_saved"]:
		var world := World.new()
		root.add_child(world)
		current_scene = world
		world.player = Node3D.new()
		world.player.position = Vector3(365,2,-410)
		world.add_child(world.player)
		world.gameplay.player = world.player
		if scenario != "missing":
			var road := ROAD.new()
			road.configure(LAYOUT.roads())
			road.build_chunk(world,Rect2(288,-480,96,96))
		var controller = preload("res://runtime/ProductionWorld.gd").new()
		controller.world = world
		var event := Transport.new()
		event.session = {"world":world,"controller":controller,"state":{"world_state":{}}}
		event.data = SCHEDULE.initial({"id":"1:0","origin":"harbor_bank","destination":"desert_bank"})
		event.profile = SCHEDULE.security(0)
		event.data.phase = "driving"
		event.data.cargo_cycles = [2,2]
		event.data.route_offset = 17.75
		event.road = Curve3D.new()
		var a := LAYOUT.BRIDGE_END
		var b := Vector3(342.5,0,-445)
		event.road.add_point(b if scenario == "south" else a)
		event.road.add_point(a if scenario == "south" else b)
		for index in 4:
			var point := event._virtual_point(index)
			if scenario == "too_far": point.y += 1.0
			var tangent := event._route_heading(event._virtual_offset(index))
			event.data.vehicles.append({"point":[point.x,point.y,point.z],"yaw":atan2(-tangent.x,-tangent.z),"health":600.0 if index<2 else 130.0})
		if scenario == "physical_saved": event.data.virtual_poses = false
		world.add_child(event)
		if scenario == "obstacle":
			var obstacle := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(4,1,8)
			shape.shape = box
			obstacle.add_child(shape)
			obstacle.position = event._virtual_point(0)+Vector3.UP*.5
			world.add_child(obstacle)
		for frame in 3: await physics_frame
		var records_before: Array = event.data.vehicles.duplicate(true)
		event._admit()
		print("ARMORED_RAMP_ADMISSION ",JSON.stringify({"scenario":scenario,"status":event.admission_status,"probe":event.admission_probe,"fleet":event.fleet.size()}))
		if scenario in ["north","south"]:
			check(event.fleet.size()==4,"four real vehicle hulls admit on authored descent toward "+scenario)
			if event.fleet.size()==4:
				check(event.fleet.all(func(car): return controller.vehicle_position_clear(car,car.position,car.rotation.y)),"every corrected hull passes production floor/solid admission")
				for frame in 60: await physics_frame
				check(event.fleet.all(func(car): return car.is_on_floor() and not car.is_on_wall()),"admitted bodies settle physically on the real ramp")
				check(event.fleet[0].health==600 and event.fleet[3].health==130,"support correction retains persisted vehicle damage")
				event._persist()
				check(event.data.virtual_poses==false,"physical snapshot clears virtual pose marker")
		else:
			check(event.fleet.is_empty(),"admission rejects "+scenario+" without ignoring collisions")
			check(event.data.vehicles==records_before,"rejected admission preserves saved records for "+scenario)
		event._release()
		await physics_frame
		world.free()
		controller.free()
		await physics_frame
	print("ARMORED_RAMP_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
