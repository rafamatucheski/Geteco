extends "res://tests/test_vehicle_glass_damage.gd"
## Fotos do vidro do carro levando tiro (26/10/2026): antes, depois de um tiro e depois de dois no mesmo
## vidro, de lado e de cima como a câmera do jogo. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_vehicle_glass.gd -- --no-save [arquétipo]
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var id := "monaliza"
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"): id = arg
	var output := "res://evidence/vehicle-glass-%s-%d" % [id, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("6f7a7f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cfd6da")
	environment.environment.ambient_light_energy = .7
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.mesh.size = Vector2(40, 40)
	root.add_child(floor)
	var combat := Combat.new()
	root.add_child(combat)
	var car := car_at(id, Vector3.ZERO)
	for tick in 4: await physics_frame
	var camera := Camera3D.new()
	camera.fov = 30
	root.add_child(camera)
	camera.current = true
	var side := ray_for(car, 0)
	var front := ray_for(car, 1)
	print("VEHICLE_GLASS rays side=", not side.is_empty(), " front=", not front.is_empty())
	await _views(camera, output, "0-intacto")
	if not side.is_empty():
		combat._damage_bullet(car, 10.0, combat, side[0], side[1])
		for decal: Decal in car.find_children(GLASS.CRACK_NAME, "Decal", true, false):
			print("VEHICLE_GLASS marca ", decal.global_position, " normal ", decal.global_basis.y, " tamanho ", decal.size, " visível ", decal.is_visible_in_tree(), " camadas ", decal.cull_mask)
		print("VEHICLE_GLASS tiro ", GLASS.owner_for(car).contact(side[0], side[1]).get("point"))
		await _views(camera, output, "1-lado-um-tiro")
		combat._damage_bullet(car, 10.0, combat, side[0], side[1].lerp(side[0], .02) + Vector3(0, .05, .05))
		await _views(camera, output, "2-lado-dois-tiros")
	if not front.is_empty():
		combat._damage_bullet(car, 10.0, combat, front[0], front[1])
		await _views(camera, output, "3-frente-um-tiro")
	print("VEHICLE_GLASS_CAPTURE ", output)
	quit()

func _views(camera: Camera3D, output: String, label: String) -> void:
	for view in [["lado", Vector3(-6.5, 1.6, 1.0)], ["cima", Vector3(-9, 11, 9)]]:
		camera.position = view[1]
		camera.look_at(Vector3(0, .8, 0))
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join("%s-%s.png" % [label, view[0]])))
