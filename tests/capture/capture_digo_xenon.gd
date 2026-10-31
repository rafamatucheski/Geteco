extends "res://tests/measure/measure_motocross.gd"
## Trinta segundos de quadros renderizados consecutivos no Main, com manifesto de timestamps.
## O custo da captura fica de propósito fora do benchmark de FPS separado.
func _process(_delta: float) -> bool: return false

func run() -> void:
	paddock_focus = true
	await super.run()
	started = 0
	var car = world.session.motocross.digo_amarok
	assert(is_instance_valid(car))
	world.session.state.intro.stage = "complete"
	world.player.teleport(car.driver_door_anchor(-1))
	assert(world.driving._begin_entry(car,-1))
	for i in 180:
		await physics_frame
		if car.controlled: break
	assert(car.controlled,"Actual boarding must complete before testing driver headlights")
	car.input_locked = true
	world.session.weather.time_of_day = .02
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var equipment = car.ensure_equipment(world)
	equipment.headlights_on = true
	equipment._refresh()
	assert(equipment.lamps.all(func(item: Dictionary): return item.lamp.visible))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	world.add_child(camera)
	camera.make_current()
	root.size = Vector2i(640,360)
	Engine.max_fps = 60
	var archive := ZIPPacker.new()
	assert(archive.open("res://evidence/digo/xenon-driver-frames.zip") == OK)
	var records: Array = []
	var beginning := Time.get_ticks_msec()
	var frame := 0
	while Time.get_ticks_msec()-beginning < 30000:
		var elapsed := float(Time.get_ticks_msec()-beginning)/1000.0
		var angle := 0.0 if elapsed < 10 else (elapsed-10)*.12
		camera.size = 17 if elapsed < 20 else 17 + sin((elapsed-20)*.6)*6
		camera.global_position = car.to_global(Vector3(-7*cos(angle),9,-9+7*sin(angle)))
		camera.look_at(car.to_global(Vector3(0,0,-7)))
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		archive.start_file("%05d.jpg" % frame)
		archive.write_file(picture.save_jpg_to_buffer(.88))
		archive.close_file()
		var enabled := 0
		for item: Dictionary in equipment.lamps:
			if item.lamp.visible: enabled += 1
		records.append({"frame":frame,"ms":Time.get_ticks_msec()-beginning,"lamps":enabled})
		if frame in [30,900,1700]:
			picture.save_png("res://evidence/digo/xenon-driver-%d.png" % frame)
		frame += 1
	archive.close()
	var report := FileAccess.open("res://evidence/digo/xenon-driver-timeline.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"scene":"Main / paddock / stationary Amarok","frames":records,"resolution":str(root.size),"scenario":"10s fixed camera,10s orbit,10s zoom; clear night","continuous_render_capture":true},"\t"))
	report.close()
	print("DIGO_XENON_CAPTURE frames=",frame," duration_ms=",Time.get_ticks_msec()-beginning)
	world.queue_free()
	await process_frame
	quit()
