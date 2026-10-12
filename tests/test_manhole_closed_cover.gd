extends "res://tests/test_manhole_ladder_access.gd"
## Production vehicle physics over each closed shaft, without unrelated city obstacles.
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	scene = Node3D.new()
	root.add_child(scene)
	floor_piece(Vector3(-2.28125,-.1,0), Vector3(3.4375,.2,8))
	floor_piece(Vector3(2.28125,-.1,0), Vector3(3.4375,.2,8))
	floor_piece(Vector3(0,-.1,-2.28125), Vector3(1.125,.2,3.4375))
	floor_piece(Vector3(0,-.1,2.28125), Vector3(1.125,.2,3.4375))
	var camera := Camera3D.new()
	camera.position = Vector3(0,6,6)
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	for id in preload("res://world/places/sewers/SewerNetwork.gd").ids():
		hatch = HATCH.new()
		hatch.setup({"id":id,"kind":"sewer","size":Vector2(2,2)})
		scene.add_child(hatch)
		check(not hatch.ladder_handles.visible and hatch.ladder_handle_collision.collision_layer == 0, id+": escada recolhida não bloqueia carro")
		for direction in [1.0,-1.0]:
			var car = preload("res://scripts/Vehicle.gd").new()
			car.archetype = "sport_coupe"
			car.position = Vector3(-2.8*direction,.04,0)
			scene.add_child(car)
			car.set_external_driver(true)
			car.place(car.position,-PI*.5 if direction>0 else PI*.5)
			car.brake_input = true
			for i in 20: await physics_frame
			var health: float = car.health
			car.brake_input = false
			car.throttle_input = 1
			var crossed := false
			var min_y := INF
			for i in 180:
				await physics_frame
				min_y = minf(min_y,car.position.y)
				if car.position.x*direction>2.65: crossed=true; break
			check(crossed and car.health>=health and min_y>-.1,id+": carro real cruza tampa sem dano/queda, sentido "+str(direction))
			car.free()
		hatch.free()
		await physics_frame
	print("MANHOLE_CLOSED_COVER failures=",failures)
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
