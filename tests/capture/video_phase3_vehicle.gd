extends "res://tests/test_video_phase3_vehicle.gd"
## Same Main theft fixture with full body/car physics; normal gameplay camera.
## Visual evidence only. The user's other running game precludes FPS approval.
var captures: Array[Dictionary] = []

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	selected_cases.assign(["moving_sedan", "fresh_impact_coupe"])
	report_name = "phase3-vehicle-render-physics.json"
	await super.run()

func capture_state(car: CharacterBody3D, label: String, phase: String, frame: int) -> void:
	await RenderingServer.frame_post_draw
	var name := "phase3-vehicle-%s-%s-%03d.png" % [label, phase, frame]
	var pixels: Image = root.get_texture().get_image()
	check(pixels.save_png(OUTPUT + name) == OK, "capture " + name)
	captures.append({"file":name,"car":str(car.global_position),"player":str(world.player.global_position),"camera":str(world.camera.global_position),"floor":car.is_on_floor(),"physics_active":car.is_physics_processing(),"traffic":car.traffic,"speed":car.speed,"body_transition":world.driving.is_body_transition_active(),"pixel_size":str(pixels.get_size())})

func finish() -> void:
	var file := FileAccess.open(OUTPUT + "phase3-vehicle-captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captures,"failures":failures,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"type":"Main functional render, not benchmark","scope":"Moving sedan theft and theft immediately after a real coupe collision; actual physics/streaming, normal camera. Setup teleports are outside the sampled transitions. Original under-terrain fall has not been reproduced."}, "\t"))
	file.close()
	await super.finish()
