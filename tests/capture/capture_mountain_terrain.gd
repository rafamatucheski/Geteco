extends SceneTree
## Captura renderizada (Vulkan, não headless) do terreno de Mountain em pontos de
## encosta aberta, longe das clareiras. Rodar com --no-save.
## Saída em res://evidence/mountain-terrain-0924/.
const OUTPUT := "res://evidence/mountain-terrain-0924/"
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
# Pontos na coordenada da V1 (px) de Mountain.
const SPOTS := {"a_floresta": Vector2(6900, 250), "b_encosta": Vector2(6750, -1100), "c_neve": Vector2(6450, -2050), "d_ponte_leste": Vector2(9050, -4560+4960)}
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
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
	var controller = world.session.controller
	controller.travel("mountain")
	for i in 900:
		await process_frame
		if not controller.travel_busy and controller.state.region_id == "mountain": break
	var weather = world.session.weather
	weather.time_of_day = .45
	for label in SPOTS:
		var point: Vector3 = CATALOG._at(SPOTS[label], "mountain")
		var region = controller.regions.get("mountain")
		if region != null and region.terrain != null: point.y = region.terrain.surface_height_at(Vector2(point.x, point.z)) + .2
		world.player.teleport(point)
		if region != null: region.set_focus(point)
		await frames(240)
		await shot(label)
	# Beira de estrada à noite: trilha e postes da montanha acesos.
	var road_point: Vector3 = CATALOG._at(SPOTS["b_encosta"], "mountain")
	road_point = controller.nearest_road(road_point)
	world.player.teleport(road_point + Vector3(0, .2, 0))
	controller.regions.get("mountain").set_focus(road_point)
	weather.time_of_day = .5
	await frames(200)
	await shot("e_estrada_dia")
	weather.time_of_day = .95
	await frames(120)
	await shot("f_estrada_noite")
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
