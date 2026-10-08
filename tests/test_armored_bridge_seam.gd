extends "res://tests/test_armored_guard_service_path.gd"
const ROAD := preload("res://world/desert/DesertRoadGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const TRUCK := preload("res://gameplay/armored/ArmoredTruck.gd")
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): check(false,"bounded bridge seam probe"); quit(3))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("ARMORED_BRIDGE_SEAM ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func slab(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	body.position = at
	parent.add_child(body)
func run() -> void:
	var scenarios := [{"authored":false,"suv":false,"south":false},{"authored":true,"suv":false,"south":false}]
	if "--baseline" not in OS.get_cmdline_user_args():
		scenarios.append_array([{"authored":true,"suv":true,"south":false},{"authored":true,"suv":false,"south":true},{"authored":true,"suv":true,"south":true}])
	var first_mesh_hash := 0
	for scenario in scenarios:
		var authored: bool = scenario.authored
		var south: bool = scenario.south
		var world := World.new()
		root.add_child(world)
		current_scene = world
		world.player = Node3D.new()
		world.player.position = Vector3(330,2.4,-360)
		world.add_child(world.player)
		world.gameplay.player = world.player
		slab(world,Vector3(342.5,2.3,-353.5),Vector3(26,.2,40))
		var road := ROAD.new()
		if authored:
			road.configure(LAYOUT.roads())
			road.build_chunk(world,Rect2(288,-384,96,96))
			road.build_chunk(world,Rect2(288,-480,96,96))
			var mesh_hash := hash((world.get_node("WeatheredAsphalt") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			if first_mesh_hash == 0: first_mesh_hash = mesh_hash
			else: check(mesh_hash == first_mesh_hash,"regenerated chunk retains identical transition geometry")
		else:
			slab(world,Vector3(342.5,2.318,-393.5),Vector3(10,.2,40))
		for frame in 3: await physics_frame
		var surfaces: Array = []
		for z in [-373.14,-373.15,-373.2,-373.5,-374.0,-376.0]:
			var query := PhysicsRayQueryParameters3D.create(Vector3(344.1,3,z),Vector3(344.1,1,z),1)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			surfaces.append({"z":z,"height":hit.get("position",Vector3.INF),"normal":hit.get("normal",Vector3.ZERO)})
		print("ARMORED_BRIDGE_SURFACE ",JSON.stringify({"authored":authored,"heights":surfaces,"extrapolated_base":road._height(Vector2(344.1,-373.15))}))
		var truck = preload("res://gameplay/dispatch/DispatchVehicle.gd").new() if scenario.suv else TRUCK.new()
		if scenario.suv: truck.archetype = "winter_suv_heavy"
		truck.position = Vector3(344.1,road._height(Vector2(344.1,-383))+.058,-383) if south else Vector3(344.1,2.44,-362)
		if south: truck.rotation.y = PI
		world.add_child(truck)
		truck.set_physics_process(false)
		for frame in 3: await physics_frame
		truck.set_external_driver(true)
		truck.throttle_input = .15
		truck.brake_input = false
		truck.set_physics_process(true)
		var horizontal_contact := false
		var contacts: Array = []
		for frame in 840:
			await physics_frame
			if (south and truck.position.z > -367) or (not south and truck.position.z < -380): break
			for index in truck.get_slide_collision_count():
				var hit := truck.get_slide_collision(index)
				if absf(hit.get_normal().y) < .2:
					horizontal_contact = true
					contacts = [{"point":hit.get_position(),"normal":hit.get_normal(),"body":str(hit.get_collider().get_path())}]
		print("ARMORED_BRIDGE_CONTACT ",JSON.stringify({"scenario":scenario,"point":truck.position,"contacts":contacts}))
		if not authored or "--baseline" in OS.get_cmdline_user_args():
			check(horizontal_contact and truck.position.z > -374,"real truck reproduces physical lip obstruction (%s)" % ("authored" if authored else "18mm"))
		else:
			check((south and truck.position.z > -367) or (not south and truck.position.z < -380),"real %s crosses authored seam toward %s" % ["SUV" if scenario.suv else "truck","bridge" if south else "desert"])
		check(truck.health == truck.max_health,"low-speed seam contact does not damage truck")
		world.free()
		await physics_frame
	print("ARMORED_BRIDGE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
