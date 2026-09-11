extends "res://tests/measure_aa_performance.gd"
var matrix_done := false
var driving_measured := false
func _measure(label: String, car: CharacterBody2D, drive: bool) -> void:
	if drive:
		if driving_measured: return
		await super._measure(label,car,true)
		return
	var world := current_scene
	var player: Node2D = world.get_node("Player")
	var stream := world.get_node("ContinuousWorld")
	stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var places := {
		"centro":Vector2(700,425), "terminal":Vector2(1790,1020),
		"cais":Vector2(3520,1760), "porto_sul":Vector2(4500,3500),
		"cemiterio":Vector2(-600,1790), "acesso_norte":Vector2(6020,-4490),
		"serra":Vector2(9000,-5200), "cume":Vector2(10500,-7400)}
	for place in places:
		car.global_position = places[place]
		player.global_position = car.global_position
		car.velocity = Vector2.ZERO
		car.reset_physics_interpolation()
		var camera := root.get_camera_2d()
		if camera:
			camera.reset_smoothing()
			camera.reset_physics_interpolation()
		for i in 120: await process_frame
		await super._measure(place,car,false)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/measurements/aa-performance-0911/"+output+"-"+place+".png")
	if OS.get_cmdline_user_args().has("full"):
		car.global_position = Vector2(700,425)
		player.global_position = car.global_position
		car.reset_physics_interpolation()
		for i in 120: await process_frame
		await super._measure("driving",car,true)
		driving_measured = true
		for place in ["terminal", "porto_sul"]:
			car.global_position = places[place]
			player.global_position = car.global_position
			car.reset_physics_interpolation()
			world.weather.time_of_day = 0.95
			world.weather.set_weather(2)
			for i in 180: await process_frame
			await super._measure(place+"_night_storm",car,false)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/measurements/aa-performance-0911/"+output+"-"+place+"-storm.png")
		world.weather.time_of_day = 0.45
		world.weather.set_weather(0)
		world._walk()
		var interiors := world.get_node("Interiors")
		for room in interiors.get_node("InteriorSpaces").get_children():
			if not room.is_in_group("harbor_interior") or room.get("spawn_point") == null: continue
			player.global_position = room.spawn_point.global_position
			player.set_meta("police_exterior_position",Vector2(700,425))
			player.set_meta("harbor_interior",true)
			player.set_meta("interior_camera_overview",room.get_meta("fixed_camera",false))
			player.reset_physics_interpolation()
			world._restore_room_presentation()
			world.weather.set_interior_mode(true)
			for i in 120: await process_frame
			await super._measure("interior_"+room.name,car,false)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/measurements/aa-performance-0911/"+output+"-"+room.name+".png")
		player.remove_meta("police_exterior_position")
		player.remove_meta("harbor_interior")
		player.remove_meta("interior_camera_overview")
		world.weather.set_interior_mode(false)
	car.global_position = Vector2(700,425)
	player.global_position = car.global_position
	world._restore_room_presentation()
	if not driving_measured and not car.is_driven_by_player: car.enter_vehicle(player)
	car.reset_physics_interpolation()
	for i in 120: await process_frame
	matrix_done = true
