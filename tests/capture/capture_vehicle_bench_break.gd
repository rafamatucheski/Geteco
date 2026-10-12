extends "res://tests/measure/measure_katana_session.gd"
const FRAGILE = preload("res://gameplay/street_physics/FragileProps3D.gd")
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	output_dir = "res://output/vehicle-breakables/flow"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world = load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene = world
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	var point := Vector3(1650.0/16.0,0,2070.0/16.0)
	world.player.teleport(point+Vector3(4,.1,7)); world.production.region.set_focus(point)
	await frames(100)
	var items: Array = FRAGILE.query(point,2).filter(func(item): return item.kind == "bench_seat" and item.point.distance_to(point)<1)
	check(items.size() == 1,"native road bench registered at authored point")
	if items.is_empty(): world.queue_free(); quit(1); return
	var item: Dictionary = items[0]
	var camera := Camera3D.new(); world.add_child(camera)
	camera.look_at_from_position(point+Vector3(8,6,10),point+Vector3.UP*.8); camera.make_current()
	var car = world.driving.car
	car.place(point+Vector3(0,.1,7),0); car.controlled = true; car.traffic = false; car.external_input = true
	car.brake_input = true; car.throttle_input = 0
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("before.png"))
	car.brake_input = false; car.throttle_input = 1; car.speed = 12; car.horizontal_velocity = Vector3(0,0,-12)
	for index in 4:
		await frames(15)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir.path_join("impact-%d.png"%index))
	car.throttle_input = 0; car.brake_input = true
	check(item.state == "down","native Vehicle physics breaks bench on actual movement")
	check(not item.root.get_ref().visible,"intact bench disappears")
	check(preload("res://gameplay/street_physics/StreetPhysics.gd").instance.find_children("*","RigidBody3D",true,false).size() > 0,"live street has physical debris")
	world.queue_free(); await process_frame
	print("VEHICLE_BENCH_FLOW checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
