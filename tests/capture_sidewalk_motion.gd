extends "res://tests/capture_lighting_glitches.gd"
## Sequential images are visual evidence only, never frame-time samples.
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	output_dir="res://evidence/sidewalk-glitches/motion"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.weather!=null: break
	if world.session==null or world.session.weather==null: quit(1); return
	world.player.controlled_automatically=true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	for entry in [["day",.55,3],["sunset",.75,0],["night",.84,0],["rain",.55,1]]:
		await move_to(Vector3(137.5,.08,105),0,26,true)
		world.session.weather.time_of_day=entry[1]
		world.session.weather.weather_state=entry[2]
		world.session.weather.weather_timer=10000
		world.session.weather._update()
		world.session.weather.set_process(false)
		for i in 80:
			# Still, walking, zoom, rotation: 20 frames per phase.
			world.player.automatic_direction=Vector3(0,0,-1) if i>=20 and i<40 else Vector3.ZERO
			if i>=40 and i<60: world.camera.target_size=26-(i-40)*.4
			if i>=60: world.camera.heading=(i-60)*.025
			await create_timer(.1).timeout
			await capture(output_dir+"/%s-%03d.png"%[entry[0],i])
		print("SIDEWALK_MOTION ",entry[0])
	world.queue_free()
	await process_frame
	quit()
