extends SceneTree

func _init() -> void: call_deferred("run")

func frame_image() -> Image:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	root.size = Vector2i(1280,800)
	var lab = load("res://prototypes/living_cast/CoupeCrashLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	var car = lab.car
	car.manual_input = false
	car.position = Vector3(1.8,0,-6)
	lab.set_process(false)
	lab.hud.text = "TESTE REAL / farois projetando luz no piso e na barreira\nCena 3D isolada — sem integrar ao distrito"
	lab.camera.position = Vector3(9,7,5)
	lab.camera.look_at(Vector3(0,0,-13))
	car.light_mode = 0
	car.update_lights()
	var dark := await frame_image()
	car.light_mode = 2
	car.update_lights()
	var lit := await frame_image()
	var result := lit.save_png("D:/geteco/coupe_headlights_test.png")
	var brighter := 0
	for y in range(160,mini(750,lit.get_height()),4):
		for x in range(60,mini(1220,lit.get_width()),4):
			if lit.get_pixel(x,y).get_luminance() - dark.get_pixel(x,y).get_luminance() > 0.035: brighter += 1
	print("COUPE_LIGHT_RENDER brighter_samples=%d save=%d" % [brighter,result])
	car.position = Vector3(1.8,0,8)
	car.throttle = 1
	for frame in 360:
		await physics_frame
		if car.collision_count > 0: break
	car.throttle = 0
	car.braking = true
	for i in 40: await physics_frame
	car.set_physics_process(false)
	lab.set_night(false)
	lab.camera.position = car.position + Vector3(4.8,3.1,-6.5)
	lab.camera.look_at(car.position+Vector3(0,0.55,0))
	lab.hud.text = "APOS COLISAO FISICA / canto direito amassado e farol quebrado\nIntegridade %d%% | Impactos %d | R no laboratorio restaura carro e farois" % [car.health,car.collision_count]
	# Move only the camera-facing test barrier out of the photograph after impact.
	for node in lab.get_children():
		if node is MeshInstance3D and node.position.is_equal_approx(Vector3(0,0.7,-23)): node.hide()
	var damaged := await frame_image()
	result = damaged.save_png("D:/geteco/coupe_damage_test.png")
	print("COUPE_DAMAGE_RENDER collisions=%d save=%d" % [car.collision_count,result])
	quit(0 if brighter > 100 and car.collision_count > 0 and result == OK else 1)
