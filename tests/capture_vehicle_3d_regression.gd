extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("24303a"))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	stage.add_child(camera)
	camera.make_current()
	var ids := ["sport_estate", "nordic_estate", "bike_sport", "metro_hatch"]
	for index in ids.size():
		var vehicle := preload("res://cars/traffic/TrafficVehicle.gd").new()
		vehicle.name = "Vehicle3DRegression_%d" % index
		vehicle.defer_presentation = false
		vehicle.position = Vector2(190.0 + index * 300.0, 360.0)
		stage.add_child(vehicle)
		vehicle.apply_archetype(ids[index])
		vehicle.ensure_presentation()
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("D:/geteco/artifacts/vehicle-3d-regression.png")
	# Exercise the exact streaming path that previously left a contact shadow
	# visible while the 3D body texture stayed black/empty.
	var wake_vehicle := stage.get_node("Vehicle3DRegression_0")
	wake_vehicle.compact_presentation_for_sleep()
	for frame in 3: await process_frame
	wake_vehicle.restore_presentation_after_sleep()
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var wake_image := root.get_texture().get_image()
	wake_image.save_png("D:/geteco/artifacts/vehicle-3d-regression-wake-after.png")
	print("VEHICLE_3D_REGRESSION_CAPTURE saved=true")
	quit(0)
