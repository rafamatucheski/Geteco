extends SceneTree
## Vídeo de 25/09: à noite, a lanterna e o clarão do tiro acendiam o mar inteiro de
## ciano. Reproduz na Main real: Dante na beira do mar, pistola com lanterna, mirando
## e atirando para a água (borda leste do Harbor, onde fica o cais do vídeo). Mede o brilho médio do mar longe do facho e grava capturas
## em evidence/night-sea-light-20260925. --no-save --skip-arrival obrigatórios.

const OUTPUT := "res://evidence/night-sea-light-20260925/"
var world
var gameplay
var player

func _initialize() -> void: run.call_deferred()

func frames(n: int) -> void:
	for i in n: await physics_frame

func shot(file_name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT + file_name))
	print("CAPTURE ", file_name)
	return image

## Brilho médio de uma janela da tela (0..1), longe do Dante e do facho.
func brightness(image: Image, point: Vector3) -> float:
	var factor := Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var center := Vector2i(world.camera.unproject_position(point) * factor)
	var total := 0.0
	var count := 0
	for y in range(-20, 21, 4):
		for x in range(-20, 21, 4):
			var p := center + Vector2i(x, y)
			if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height(): continue
			total += image.get_pixelv(p).get_luminance()
			count += 1
	return total / maxf(1.0, count)

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
	gameplay = world.gameplay
	player = world.player
	gameplay.health = 1000000
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.economy.grant_reward("sea_capture_fixture", 20000)
	# Borda leste da terra principal (harbor_land: x até 3200 px); a leste fica o mar.
	var edge := Vector3(3160.0, 0, 1000.0) / 16.0
	print("SHORE ", edge)
	player.teleport(edge + Vector3.UP * 0.1)
	world.session.weather.time_of_day = 0.02
	gameplay.state.equip_weapon("pistol")
	gameplay.buy_attachment("pistol", "flashlight")
	await frames(20)
	var sea_far := edge + Vector3(12, 0, 9)
	var dark := await shot("sea_idle.png")
	var dark_level := brightness(dark, sea_far)
	gameplay.toggle_flashlight()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0
	down.y = 0
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	controls.touch_aim = Vector2(Vector3.RIGHT.dot(right.normalized()), Vector3.RIGHT.dot(down.normalized()))
	gameplay.aim_point = player.global_position + Vector3.RIGHT * 6.0
	Input.action_press("aim")
	await frames(40)
	var lamp := await shot("sea_flashlight.png")
	var lamp_level := brightness(lamp, sea_far)
	gameplay.cooldown = 0.0
	gameplay.fire_at(player.global_position + Vector3.RIGHT * 8.0)
	await frames(1)
	var flash := await shot("sea_muzzle.png")
	var flash_level := brightness(flash, sea_far)
	Input.action_release("aim")
	print("SEA_BRIGHTNESS idle=%.3f flashlight=%.3f muzzle=%.3f" % [dark_level, lamp_level, flash_level])
	# Fora do cone e longe do tiro, o mar não pode acender (tolerância para onda e ruído).
	var ok := lamp_level < dark_level + 0.04 and flash_level < dark_level + 0.04
	print("SEA_LIGHT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
