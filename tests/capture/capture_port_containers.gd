extends SceneTree
var world
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	create_timer(180,true,false,true).timeout.connect(func(): quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(271,.1,245.15625))
	world.production.region.set_focus(world.player.position)
	for i in 180: await physics_frame
	var containers := get_nodes_in_group("lootable_port_containers")
	containers.sort_custom(func(a,b): return a.cargo_id < b.cargo_id)
	for index in [0,1,6]:
		var cargo = containers[index]
		cargo.apply_state({"opened":true,"looted":false})
		world.player.teleport(cargo.global_position+Vector3(4,.1,0))
		for i in 90: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/port-lockpick-20260928/final-interior-%d.png"%index)
		print("VISIBLE_INTERIOR ",cargo.cargo_id," revealed=",cargo.revealed)
		if not cargo.revealed or world.camera.global_basis.z.dot(Vector3.UP) < .99: quit(4); return
		if index == 0:
			world.session.modal = true
			for i in 20: await physics_frame
			if not cargo.revealed: quit(5); return
			world.session.modal = false
			world.session.weather.time_of_day = .9
			world.session.weather.weather_state = 1
			world.session.weather._update()
			if world.session.weather.precipitation.visible: quit(6); return
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/port-lockpick-20260928/night-rain-interior.png")
			world.session.weather.time_of_day = .4
			world.session.weather.weather_state = 0
			world.session.weather._update()
	world.player.teleport(containers[0].door_point()+Vector3(3,0,0))
	for i in 90: await physics_frame
	if world.player.get_meta("port_container_shelter",false) or world.camera.has_meta("port_container_focus"): quit(7); return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/port-lockpick-20260928/final-exterior.png")
	world.queue_free()
	for i in 3: await process_frame
	print("CONTAINER_VIEW: overhead, modal, rain shelter and exit PASS")
	quit()
