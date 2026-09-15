extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func _run() -> void:
	var cold := ColdSurvivalController.new()
	root.add_child(cold)
	cold.set_process(false)
	check(not cold.should_show_status(), "arrival outside exposure keeps cold HUD hidden")
	cold.force_cold_active = true
	check(cold.should_show_status(), "cold HUD appears immediately during arrival grace")
	cold.is_in_vehicle = true
	cold._update_temperature(1.0)
	check(cold.should_show_status() and cold.exposure_seconds == 0.0, "cold HUD stays visible in a heated vehicle without exposure")
	cold.is_in_vehicle = false
	cold._update_temperature(15.0)
	check(cold.current_temperature == 100, "first 15 seconds outdoors do not drain temperature")
	cold._update_temperature(5.0)
	check(cold.current_temperature > 95 and cold.current_temperature < 100, "cold starts gently after preparation time")
	var split := ColdSurvivalController.new()
	root.add_child(split)
	split.set_process(false)
	split.force_cold_active = true
	for i in 200: split._update_temperature(0.1)
	check(is_equal_approx(split.current_temperature, cold.current_temperature), "ramp is frame-rate independent")
	cold.exposure_seconds = 40
	cold.current_temperature = 100
	cold._update_temperature(1)
	var unprotected := 100.0 - cold.current_temperature
	cold.current_temperature = 100
	cold.outfit_protection = OutfitCatalog.cold_protection("dante_arctic")
	cold._update_temperature(1)
	check(is_equal_approx(100.0-cold.current_temperature, unprotected*.2), "parka reduces actual heat loss by 80 percent")
	cold.current_temperature = 0
	cold._update_temperature(1)
	check(cold.is_hypothermic, "parka still requires shelter after prolonged exposure")
	cold.sheltered = true
	cold._update_temperature(1)
	check(cold.current_temperature > 0 and not cold.is_hypothermic, "shelter restores heat and ends hypothermia")
	cold.sheltered = false
	cold.is_in_vehicle = true
	cold._update_temperature(1)
	check(cold.current_temperature >= 35, "vehicle heater recovers temperature")
	cold.is_in_vehicle = false
	cold.is_near_heat_source = true
	cold._update_temperature(1)
	check(cold.current_temperature >= 70, "fire warms the player")
	cold.force_cold_active = false
	cold._update_temperature(30)
	check(not cold.should_show_status(), "fully recovered outside cold hides HUD again")
	cold.current_temperature = 25
	var hud := ColdStatusHUD.new()
	root.add_child(hud)
	hud.set_process(false)
	cold.current_temperature = 100
	cold.force_cold_active = true
	cold.exposure_seconds = 0
	hud._process(0.5)
	check(hud._panel.visible, "cold panel is visible immediately on snowy arrival")
	check(hud._panel.custom_minimum_size.x <= ColdStatusHUD.COMPACT_WIDTH and hud._panel.custom_minimum_size.y <= 12, "cold HUD is a compact vital instead of a large card")
	check(hud._temp_label.text == "25%" and not hud._temp_label.text.contains("TEMPERATURA"), "compact vital keeps only the temperature percentage")
	cold.current_temperature = 25
	check(is_equal_approx(hud._bar_fill.size.x, ColdStatusHUD.BAR_WIDTH*.25), "HUD initializes from restored temperature")
	hud._on_temp_changed(100, 100)
	check(hud._bar_fill.size.x == ColdStatusHUD.BAR_WIDTH, "full bar uses its full width")
	# MountainPass creates ColdStatusHUD before its main HUD. The one-shot node
	# watcher must still attach the vital without polling every frame.
	var player_hud = load("res://HUD.tscn").instantiate()
	root.add_child(player_hud)
	await process_frame
	var vitals: VBoxContainer = player_hud.health_bar.get_parent().get_parent()
	check(hud._panel.get_parent() == vitals, "late-created player HUD receives the temperature vital below armor")
	hud.queue_free()
	player_hud.queue_free()
	cold.queue_free()
	split.queue_free()
	await process_frame
	quit(failures)
