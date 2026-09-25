extends SceneTree
## Capturas na Main real para o feedback de 25/09/2026: corrida com soqueira, pistola
## com laser e lanterna à noite (sem mirar e mirando) e lança-chamas girando a mira.
## Recorte ampliado em volta do Dante. Saída em evidence/weapon-feedback-20260925.
## --no-save --skip-arrival obrigatórios.

const OUTPUT := "res://evidence/weapon-feedback-20260925/"
var world
var gameplay
var player

func _initialize() -> void: run.call_deferred()

func frames(n: int) -> void:
	for i in n: await physics_frame

func shot(file_name: String, half := Vector2(240, 150)) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var center: Vector2 = world.camera.unproject_position(player.global_position + Vector3.UP)
	var scale_factor := Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var rect := Rect2i(Vector2i((center - half) * scale_factor), Vector2i(half * 2.0 * scale_factor))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var crop := image.get_region(rect)
	crop.resize(960, 600, Image.INTERPOLATE_LANCZOS)
	crop.save_png(ProjectSettings.globalize_path(OUTPUT + file_name))
	print("CAPTURE ", file_name)

func aim_toward(direction: Vector3) -> void:
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0
	down.y = 0
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	controls.touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))
	gameplay.aim_point = player.global_position + direction * 6.0

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(150).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 900)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for tick in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await create_timer(1.0).timeout
	# O save padrão começa dentro da garagem do Maciota, onde arma não aparece.
	print("PLACE_BEFORE ", world.session.state.place_id, " blocked=", world.session.is_transition_blocked(), " weapons=", world.session.state.weapons_allowed())
	if not world.session.state.place_id.is_empty():
		print("LEAVE ", await world.session.leave_place())
		for tick in 300:
			await process_frame
			if world.session.state.place_id.is_empty() and not world.session.is_transition_blocked(): break
	await create_timer(1.5).timeout
	print("PLACE_AFTER ", world.session.state.place_id, " weapons=", world.session.state.weapons_allowed())
	gameplay = world.gameplay
	player = world.player
	gameplay.health = 1000000
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.economy.grant_reward("capture_fixture", 20000)
	# Rua aberta perto do carro do jogador (a garagem do Maciota bloqueia armas).
	var street: Vector3 = world.production.nearest_road(world.driving.car.global_position + Vector3(0, 0, 14))
	player.teleport(street + Vector3.UP * 0.1)
	await create_timer(1.5).timeout

	# 1) Corrida com soqueira: seis quadros de um ciclo.
	gameplay.state.equip_weapon("knuckles")
	await frames(30)
	print("EQUIPPED ", gameplay.equipped(), " allowed=", gameplay.attack_allowed(), " gun=", gameplay.gun.visible)
	# De perfil para a câmera: corre para o lado livre da tela.
	var side: Vector3 = world.camera.global_basis.x
	side.y = 0
	var run_action := "move_right"
	var probe := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, player.global_position + Vector3.UP + side.normalized() * 12.0, 1)
	if not world.get_world_3d().direct_space_state.intersect_ray(probe).is_empty(): run_action = "move_left"
	Input.action_press(run_action)
	Input.action_press("sprint")
	await frames(40)
	for i in 6:
		await shot("knuckles_run_%d.png" % i, Vector2(120, 75))
		await frames(4)
	Input.action_release("sprint")
	Input.action_release(run_action)
	await frames(40)

	# 2) Noite, pistola com laser e lanterna.
	world.session.weather.time_of_day = 0.94
	gameplay.state.equip_weapon("pistol")
	gameplay.buy_attachment("pistol", "laser_red")
	gameplay.buy_attachment("pistol", "flashlight")
	await frames(20)
	gameplay.toggle_flashlight()
	var facing := -Vector3(world.camera.global_basis.z.x, 0, world.camera.global_basis.z.z).normalized()
	aim_toward(facing.rotated(Vector3.UP, -0.6))
	await frames(40)
	await shot("pistol_night_idle.png", Vector2(320, 200))
	Input.action_press("aim")
	await frames(40)
	await shot("pistol_night_aim.png", Vector2(320, 200))
	print("LAMP visible=", gameplay.flashlight.visible, " enabled=", gameplay.flashlight_enabled, " installed=", gameplay.customization.get("pistol", {}), " pos=", gameplay.flashlight.global_position, " player=", player.global_position, " fwd=", -gameplay.flashlight.global_basis.z, " scale=", gameplay.gun.global_basis.get_scale())
	world.session.weather.time_of_day = 0.02
	await frames(30)
	await shot("pistol_midnight_aim.png", Vector2(320, 200))
	if "--probe-lamp" in OS.get_cmdline_user_args():
		var lamp_probe := SpotLight3D.new()
		lamp_probe.top_level = true
		world.add_child(lamp_probe)
		lamp_probe.global_transform = Transform3D(gameplay.flashlight.global_basis.orthonormalized(), gameplay.flashlight.global_position)
		lamp_probe.spot_range = 22.0
		lamp_probe.spot_angle = 30.0
		lamp_probe.light_energy = 3.2
		gameplay.flashlight.visible = false
		gameplay.flashlight_enabled = false
		await frames(3)
		await shot("lamp_probe_world_light.png", Vector2(320, 200))
		lamp_probe.light_energy = 25.0
		await frames(3)
		await shot("lamp_probe_world_light_25.png", Vector2(320, 200))
		var counts := {}
		for light in world.find_children("*", "Light3D", true, false):
			if not light.is_visible_in_tree() or light is DirectionalLight3D: continue
			if (light as Node3D).global_position.distance_to(player.global_position) < 40.0:
				counts[light.get_class() + ":" + str(light.get_parent().name)] = int(counts.get(light.get_class() + ":" + str(light.get_parent().name), 0)) + 1
		print("LIGHTS_NEAR ", counts)
		var road_meshes := []
		for mesh in world.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree(): continue
			var aabb: AABB = mesh.global_transform * mesh.get_aabb()
			var foot: Vector3 = player.global_position + Vector3(0, 0.02, 0)
			if aabb.grow(0.05).has_point(foot) and aabb.size.x > 3.0: road_meshes.append(str(mesh.get_path()).right(70) + " mat=" + str(mesh.material_override.get_class() if mesh.material_override else (mesh.mesh.surface_get_material(0).get_class() if mesh.mesh and mesh.mesh.get_surface_count() > 0 and mesh.mesh.surface_get_material(0) else "none")))
		print("GROUND_MESHES ", road_meshes)
		for mesh in world.find_children("HarborRoad_*", "MeshInstance3D", true, false):
			var m = mesh.material_override if mesh.material_override else mesh.mesh.surface_get_material(0)
			print("ROAD_MAT ", mesh.name, " shading=", m.shading_mode, " albedo=", m.albedo_color, " rough=", m.roughness, " metal=", m.metallic, " vertex=", m.vertex_color_use_as_albedo, " tex=", m.albedo_texture != null)
			break
		print("LAYERS gun=", gameplay.gun.get("layers"), " mask=", gameplay.flashlight.light_cull_mask, " max_lights=", ProjectSettings.get_setting("rendering/limits/forward_renderer/max_lights_per_object", "?"))
		quit(0)
	aim_toward(facing.rotated(Vector3.UP, 1.4))
	await frames(40)
	await shot("pistol_night_aim_turned.png", Vector2(320, 200))
	Input.action_release("aim")
	await frames(10)

	# 3) Lança-chamas de dia, girando a mira durante o jato.
	world.session.weather.time_of_day = 0.45
	gameplay.state.equip_weapon("flamethrower")
	await frames(40)
	Input.action_press("aim")
	for step in 3:
		var direction := facing.rotated(Vector3.UP, -0.8 + step * 0.8)
		aim_toward(direction)
		for tick in 14:
			gameplay.cooldown = 0.0
			gameplay.fire_at(player.global_position + direction * 6.0)
			await physics_frame
		await shot("flame_%d.png" % step, Vector2(300, 190))
	Input.action_release("aim")
	quit(0)
