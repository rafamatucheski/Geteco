extends SceneTree
const FACTORY = preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1000,700)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-2000,-2000),Vector2(2000,-2000),Vector2(2000,2000),Vector2(-2000,2000)])
	ground.color = Color("50585b")
	world.add_child(ground)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * 5
	world.add_child(camera)
	for spec in VehicleCatalog.get_all_specs():
		var car = FACTORY.spawn_parked_vehicle(world, spec.id, Vector2.ZERO, 0, spec.id, 0)
		car.ensure_presentation()
		car.set_headlights(true)
		check(not car._lamp_mounts.is_empty(), spec.id + " has authored headlamp origins")
		for heading in [0.0, PI*0.5, PI, -0.7]:
			car.rotation = heading
			car._update_3d_orientation(0)
			var view: Camera3D = car.body_viewport.get_camera_3d()
			for i in car._lamp_mounts.size():
				var light: PointLight2D = car.headlight if i == 0 else car.second_headlight
				var pixel := view.unproject_position(car.body_model.to_global(car._lamp_mounts[i]))
				var expected: Vector2 = car.visual.to_global(pixel-Vector2(car.body_viewport.size)*0.5)
				check(light != null and light.global_position.distance_to(expected) < 0.01, spec.id + " light follows lens at " + str(heading))
		if spec.id == "port_forklift":
			check(car._lamp_mounts.size() == 2, "Forklift has two cage work lamps")
			for mount in car._lamp_mounts: check(mount.y > 1.5 and mount.z < 0, "Forklift beam starts at cage, not fork tip")
			if DisplayServer.get_name() != "headless":
				for frame in 4: await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/forklift-lamps-fixed.png")
			car.rotation = 0
			var peer = FACTORY.spawn_parked_vehicle(world,"LiftedForklift",Vector2(35,0),PI*0.5,"port_forklift",0)
			peer.ensure_presentation()
			peer.set_headlights(true)
			await physics_frame
			await process_frame
			var lift = car.get_node("ForkliftLift")
			check(lift.attach(peer), "Forklift can pick up another sideways")
			if is_instance_valid(lift.cargo):
				lift.height = 1.3
				lift._physics_process(0)
				check(not peer.get_node("ForkliftLift").eligible(car), "Cannot lift an already loaded forklift")
				if DisplayServer.get_name() != "headless":
					for frame in 4: await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("D:/geteco/artifacts/forklift-lifting-forklift.png")
				lift.release(true)
			peer.queue_free()
		car.queue_free()
		await process_frame
	for path in ["res://prototypes/living_cast/HarborCoupe.gd", "res://world/harbor/monaliza/MonalizaCar.gd", "res://world/mountain_pass/MountainPickup.gd", "res://world/mountain_pass/MountainSUV.gd", "res://world/mountain_pass/ArcticJeep.gd"]:
		var car = load("res://cars/traffic/SavedPlayerCar.tscn").instantiate()
		car.set_script(load(path))
		car.active_archetype_id = "sport_coupe"
		world.add_child(car)
		check(car._headlamp_mounts().size() == 2, path + " has two lens anchors")
		for heading in [0.0, PI*0.5, PI, -0.7]:
			car.rotation = heading
			car.body_model.rotation.y = -heading - PI*0.5
			car.sprite.global_rotation = 0
			car._update_projected_lamps()
			for i in 2:
				var pixel: Vector2 = car.body_viewport.get_camera_3d().unproject_position(car.body_model.to_global(car._headlamp_mounts()[i]))
				var expected: Vector2 = car.sprite.to_global(pixel-Vector2(car.body_viewport.size)*0.5)
				var light: PointLight2D = car.headlight if i == 0 else car.second_headlight
				check(light.global_position.distance_to(expected) < 0.01, path + " beam tracks lens")
		car.queue_free()
		await process_frame
	print("VEHICLE_LAMP_ORIGINS failures=", failures)
	quit(1 if failures else 0)
