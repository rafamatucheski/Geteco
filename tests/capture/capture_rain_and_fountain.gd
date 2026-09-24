extends SceneTree
## Captura renderizada (Vulkan, não headless) do chafariz da Union Plaza e das poças
## de chuva em volta. Rodar com --no-save. Saída em res://evidence/rain-fountain-0924/.
const OUTPUT := "res://evidence/rain-fountain-0924/"
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
func weather_node():
	return world.session.weather
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
	var fountain: Vector3 = CATALOG._at(Vector2(1675, 1810), "harbor")
	world.player.teleport(fountain + Vector3(0, .1, 6.5))
	world.session.controller.region.set_focus(world.player.global_position)
	var weather = weather_node()
	weather.time_of_day = .5
	weather.weather_state = 0
	weather.weather_timer = 99999.0
	await frames(240)
	await shot("01_chafariz_dia")
	weather.weather_state = 1
	var puddles = world.find_child("RainPuddles", true, false)
	if puddles != null: puddles.wetness = .95
	await frames(180)
	await shot("02_chafariz_chuva_pocas")
	# Vai até a poça ativa mais próxima para ver o asfalto molhado de perto.
	var target := fountain + Vector3(0, .1, 14)
	if puddles != null and not puddles._active.is_empty():
		for p in puddles._active.values():
			print("PUDDLE ", p.global_position, " visible=", p.visible, " fill=", puddles.wetness)
		target = puddles._active.values()[0].global_position + Vector3(0, .1, 3)
	world.player.teleport(target)
	world.session.controller.region.set_focus(world.player.global_position)
	await frames(180)
	await shot("03_rua_chuva_pocas")
	weather.time_of_day = .95
	await frames(120)
	await shot("04_rua_chuva_noite")
	print("PUDDLES_ACTIVE ", puddles._active.size() if puddles != null else -1)
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
