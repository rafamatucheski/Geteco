extends SceneTree

const OUTPUT := "D:/geteco/artifacts/living-city-0911"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(180.0).timeout.connect(func(): printerr("LIVING_CITY_INTEGRATION TIMEOUT"); quit(2))
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_arrival_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var world := current_scene
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	world.campaign_controller.skip_cinematic()
	paused = false
	var restaurants: Node2D = world.get_node_or_null("RestaurantLife")
	check(restaurants != null and restaurants.terraces.size() == 6, "Partida real integra seis mesas em três restaurantes")
	check(world.has_node("WorldEvents"), "Partida real mantém o diretor de ocorrências")
	check(world.weather.is_dynamic_time and world.weather.day_length_seconds == 1440.0, "Horário progride num ciclo de 24 minutos")
	var initial_hour: float = world.weather.time_of_day
	await create_timer(.3).timeout
	check(world.weather.time_of_day > initial_hour, "Relógio avança durante a partida")
	paused = true
	initial_hour = world.weather.time_of_day
	await create_timer(.2, true).timeout
	check(world.weather.time_of_day == initial_hour, "Pausa congela os horários")
	paused = false
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 12.0/24.0
	world.weather.set_weather(0)
	world.weather._update_lighting()
	var player: Node2D = world.get_node("Player")
	player.set_physics_process(false)
	world.get_node("WorldEvents").set_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE * 3.0
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var sites := [
		{"id":"anchor", "position":Vector2(620,1100)},
		{"id":"tideline", "position":Vector2(5790,1595)},
		{"id":"early_shift", "position":Vector2(6200,-1280)},
	]
	for site in sites:
		player.global_position = site.position + Vector2(0,90)
		camera.global_position = site.position
		camera.force_update_scroll()
		for i in 50: await process_frame
		var built := 0
		for table in restaurants.terraces:
			if table.venue_id != site.id: continue
			check(table.active and is_instance_valid(table.model), "Apresentação 3D aparece em " + table.name)
			if is_instance_valid(table.model):
				built += 1
				check(table.get_status().guests == 2, "Almoço ocupa " + table.name)
		check(built == 2, "Duas mesas disponíveis em " + site.id)
		check(restaurants.get_status().active_views <= 2, "Somente as mesas próximas atualizam a apresentação")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT.path_join(site.id + "-lunch.png"))
	# Chuva usa o mesmo clima da cidade; nada depende de um relógio paralelo.
	world.weather.set_weather(1)
	world.weather.rain_intensity = .7
	for i in 45:
		restaurants.update_context(12.0,.7,camera.global_position,.1)
		await process_frame
	for table in restaurants.terraces:
		if table.venue_id == "early_shift":
			check(table.model.get_status().umbrella_open, "Chuva abre guarda-sol em " + table.name)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("early-shift-rain.png"))
	world.weather.time_of_day = 23.5/24.0
	for i in 45:
		restaurants.update_context(23.5,0.0,camera.global_position,.1)
		await process_frame
	check(restaurants.get_status().guests == 0, "Mesas desocupam depois do fechamento")
	var quarter: Node2D = world.get_node("HarborSoundscape/LivingQuarter")
	quarter.update_context(Vector2(621,1132),null,true,1.0,1.0,2.0)
	check(not quarter.sources.cafe.playing and not quarter.sources.cafe_radio.playing, "Restaurante fechado silencia conversa e rádio")
	print("LIVING_CITY_INTEGRATION failures=", failures)
	quit(0 if failures == 0 else 1)
