extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var conditions = preload("res://ui/hud/WorldConditions.gd")
	assert(conditions.text(2, 0.0, "harbor", 0) == "seg · 00:00 · 18°C")
	assert(conditions.text(8, .5, "harbor", 2) == "dom · 12:00 · 21°C")
	assert(conditions.text(9, 1.0, "harbor", 3).begins_with("seg · 00:00"))
	assert(conditions.text(2, .5, "mountain", 0, {"front":1.0,"state":3}) == "seg · 12:00 · -10°C")
	assert(conditions.icon(0.0,"harbor",0) == "moon")
	assert(conditions.icon(.5,"harbor",0) == "sun")
	for weather in [1,2,3]:
		assert(conditions.icon(.5,"harbor",weather) == ["sun","rain","storm","cloud"][weather])
	assert(conditions.icon(.5,"mountain",2,{"state":1}) == "snow")
	assert(conditions.icon(.5,"mountain",0,{"state":3}) == "hail")
	assert(conditions.text(2, .5, "desert", 0).contains("38°C"))
	var map = preload("res://ui/v1/HarborMinimap3D.gd").new()
	root.add_child(map)
	var font: Font = map.weekday_label.get_theme_font("font")
	for region in ["harbor","mountain","desert"]:
		for weather in 4:
			var line: String = conditions.text(7, .9999, region, weather, {"front":1.0,"state":3})
			assert(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x <= map.weekday_label.size.x, line)
	assert(map.weekday_label.position.y == 190)
	assert(map.weather_icon.size == Vector2(20,20))
	print("WORLD_CONDITIONS_HUD PASS: clock, calendar rollover, regional Celsius, weather and label fit")
	quit()
