extends SceneTree
## Captura renderizada (Vulkan, não headless) do pátio da delegacia: viaturas nas
## vagas, lockpick aberto, alarme com giroflex e lanterna da arma à noite.
## Rodar com --no-save. Saída em res://evidence/police-motor-pool-0922/.
const OUTPUT := "res://evidence/police-motor-pool-0922/"
var world
func _initialize() -> void: run.call_deferred()
func shot(label: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
func frames(count: int) -> void:
	for i in count: await process_frame
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	var pool = session.police_motor_pool
	var lot: Vector3 = pool.BAYS[0].position.lerp(pool.BAYS[1].position, .5) + Vector3(6, .1, 0)
	world.player.teleport(lot)
	session.controller.region.set_focus(lot)
	for i in 1200:
		await process_frame
		if is_instance_valid(pool.cars[0]) and is_instance_valid(pool.cars[1]): break
	await frames(90)
	await shot("01_patio_viaturas")
	var cruiser = pool.cars[0]
	world.player.teleport(cruiser.driver_door_anchor(-1) + Vector3.UP * .05)
	await frames(10)
	if world.driving._entry_option().get("car") != cruiser:
		world.player.teleport(cruiser.driver_door_anchor(1) + Vector3.UP * .05)
		await frames(10)
	await frames(20)
	await shot("02_prompt_arrombar")
	world.driving.interact()
	await frames(40)
	await shot("03_lockpick")
	pool.lockpick.angle = pool.lockpick.target_angle + PI
	pool.lockpick.attempt()
	# Uma captura por fase do giroflex (alterna a cada 160 ms de relógio real).
	await frames(10)
	var equipment = cruiser.equipment
	for wanted_phase in [0, 1]:
		while equipment._phase != wanted_phase: await process_frame
		await shot("0%d_alarme_giroflex_fase%d" % [4 + wanted_phase, wanted_phase])
	# Noite: a lanterna da arma só faz sentido visível no escuro.
	for node in world.find_children("*", "", true, false):
		if node.get("time_of_day") != null and node.get("weather_state") != null:
			node.time_of_day = .02
	session.state.world_state.time = .02
	session.state.grant_weapon("pistol")
	session.state.equip_weapon("pistol")
	world.gameplay.customization["pistol"] = {"owned": true, "installed": true, "owned_parts": [], "parts": {}}
	world.gameplay.visual_id = "@rebuild"
	world.gameplay.clear_wanted()
	world.player.teleport(lot + Vector3(2, 0, 6))
	await frames(120)
	var viewport_size: Vector2 = root.get_visible_rect().size
	# Mesma pose com a lanterna desligada e ligada, para comparar os pixels.
	# Segurar a mira mantém o corpo virado para o alvo nas duas capturas.
	var aim: Vector3 = world.player.global_position + Vector3(-6, 0, -4)
	Input.warp_mouse(world.camera.unproject_position(aim))
	Input.action_press("aim")
	await frames(60)
	await shot("06_lanterna_desligada")
	session._toggle_weapon_flashlight()
	await frames(20)
	await shot("07_lanterna_ligada")
	Input.action_release("aim")
	var lamp: SpotLight3D = world.gameplay.flashlight
	print("CAPTURE_DONE flashlight=", lamp.visible, " origin=", lamp.global_position, " forward=", -lamp.global_basis.z, " player=", world.player.global_position, " viewport=", viewport_size)
	world.queue_free()
	await process_frame
	quit(0)
