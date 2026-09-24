extends SceneTree

const TRAFFIC_SCENE := preload("res://cars/traffic/TrafficVehicle.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Brake-light capture requires a renderer")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("user://tests/vehicle-brake-lights.png")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_file="):
			output = arg.trim_prefix("out_file=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)

	var stage := Node2D.new()
	root.add_child(stage)
	var asphalt := ColorRect.new()
	asphalt.size = Vector2(960, 540)
	asphalt.color = Color("161b21")
	stage.add_child(asphalt)
	for y in [130.0, 270.0, 410.0]:
		var stripe := ColorRect.new()
		stripe.position = Vector2(0, y)
		stripe.size = Vector2(960, 3)
		stripe.color = Color(0.85, 0.73, 0.28, 0.34)
		stage.add_child(stripe)

	var archetypes := ["union_sedan", "metro_hatch", "bike_sport"]
	for index in archetypes.size():
		var vehicle := TRAFFIC_SCENE.instantiate()
		vehicle.position = Vector2(480, 95 + index * 140)
		stage.add_child(vehicle)
		vehicle.apply_archetype(archetypes[index], Color("556879") if index == 0 else Color("354b3f"))
		vehicle.brake_lights.set_braking(true)

	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Could not save brake-light capture: %s" % error_string(error))
		quit(1)
		return
	print("VEHICLE_BRAKE_LIGHTS_CAPTURE: %s" % output)
	quit(0)
