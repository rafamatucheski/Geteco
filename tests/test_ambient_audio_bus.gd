extends SceneTree
## Ambiente tem canal próprio: mexer nele não altera Música nem Efeitos, e a chuva
## (barramento privado com filtro) desemboca nele em vez de em SFX.
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("OK   " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	await process_frame
	await process_frame
	var sm := root.get_node("/root/SettingsManager")
	var ambient := AudioServer.get_bus_index("Ambient")
	check(ambient >= 0, "Barramento Ambient existe")
	var music_before := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sfx_before := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	sm.set_ambient_volume(0.5)
	check(absf(AudioServer.get_bus_volume_db(ambient) - linear_to_db(0.5)) < 0.01, "Volume do ambiente aplicado ao barramento")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), music_before), "Música não muda junto")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), sfx_before), "Efeitos não mudam junto")
	sm.set_ambient_volume(0.0)
	check(AudioServer.is_bus_mute(ambient), "Ambiente em zero silencia o canal")
	check("ambient_volume" in sm.interface_snapshot(), "Cancelar a tela restaura o ambiente")

	var weather: Node = preload("res://audio/weather/WeatherAudioMixer.gd").new()
	root.add_child(weather)
	var weather_index := AudioServer.get_bus_index(weather.bus_name)
	check(AudioServer.get_bus_send(weather_index) == &"Ambient", "Chuva envia para Ambient")
	# O Godot só mistura envios para barramentos anteriores.
	check(weather_index > ambient, "Barramento da chuva vem depois do Ambient na mixagem")
	weather.queue_free()

	var city := root.get_node_or_null("/root/CityAudioManager")
	if city != null:
		check(city.ambience_player.bus == &"Ambient" and city.park_ambience_player.bus == &"Ambient", "Ambiente global da cidade saiu do canal de música")

	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.slider_ambient.value == 0.0, "Controle mostra o valor atual")
	menu.slider_ambient.value = 0.7
	check(is_equal_approx(sm.ambient_volume, 0.7), "Controle da tela altera o ambiente")
	check(not menu.label_ambient_row.text.is_empty() and menu.label_music_row.text != menu.label_ambient_row.text, "Música e Ambiente têm rótulos distintos")
	menu.queue_free()
	sm.set_ambient_volume(1.0)

	print("RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
