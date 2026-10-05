extends "res://tests/measure/measure_motocross.gd"
## Real paddock, public boarding/exit, two cycles per car and 30 s seated samples.
var variant := "before"
func _process(_delta: float) -> bool: return false
func shot(camera: Camera3D, car: Node3D, label_text: String) -> void:
	camera.global_position = car.to_global(Vector3(-4,2.4,-4))
	camera.look_at(car.global_position+Vector3.UP*.9)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/digo/boarding-"+variant+"-"+label_text+".png")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=")
	paddock_focus = true
	await super.run()
	started = 0
	world.session.state.intro.stage = "complete"
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	world.add_child(camera)
	var rows: Array = []
	for car in [world.session.motocross.digo_car,world.session.motocross.digo_amarok]:
		assert(is_instance_valid(car))
		await shot(camera,car,car.archetype+"-parked")
		for cycle in 2:
			world.player.teleport(car.driver_door_anchor(-1))
			assert(world.driving.interact(),"Public interaction must board Digo's car")
			assert(world.driving.car == car)
			await create_timer(.45).timeout
			await shot(camera,car,car.archetype+"-opening-"+str(cycle))
			for i in 300:
				await physics_frame
				if car.controlled: break
			assert(car.controlled)
			car.input_locked = true
			await shot(camera,car,car.archetype+"-seated-"+str(cycle))
			if cycle == 0:
				await create_timer(3).timeout
				await shot(camera,car,car.archetype+"-closed")
				var values: Array[float] = []
				var begin := Time.get_ticks_usec()
				var previous_frame := begin
				while Time.get_ticks_usec()-begin<30000000:
					await process_frame
					var now := Time.get_ticks_usec()
					values.append((now-previous_frame)/1000.0)
					previous_frame=now
				rows.append({"car":car.archetype,"summary":stats(values),"frames_ms":values})
			car.input_locked = false
			assert(world.driving.leave())
			for i in 300:
				await physics_frame
				if not world.driving.occupied and not world.driving.is_body_transition_active(): break
			assert(not world.driving.occupied and not world.player.input_locked)
			await shot(camera,car,car.archetype+"-exited-"+str(cycle))
	var file := FileAccess.open("res://evidence/digo/boarding-"+variant+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size()},"\t"))
	file.close()
	print("DIGO_BOARDING_PASS ",variant," two cycles per vehicle")
	world.queue_free()
	await process_frame
	quit()
