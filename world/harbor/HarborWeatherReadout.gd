extends CanvasLayer
## Read-only presentation. Campaign/weather remain the sole clock and climate
## authorities; this widget never starts particles, audio or another day timer.

class WeatherIcon extends Control:
	var state := "sun"
	const INK := Color("d9e3e5")
	func _draw() -> void:
		var c := Vector2(15, 15)
		match state:
			"sun":
				draw_arc(c, 5, 0, TAU, 24, INK, 1.5, true)
				for i in 8:
					var d := Vector2.from_angle(i * TAU / 8.0)
					draw_line(c + d * 8, c + d * 11, INK, 1.5, true)
			"moon":
				var crescent := PackedVector2Array()
				for i in 25:
					crescent.append(c + Vector2.from_angle(PI * 0.5 + i * PI / 24.0) * 9)
				for i in 25:
					crescent.append(c + Vector2(4, 0) + Vector2.from_angle(-PI * 0.5 - i * PI / 24.0) * Vector2(5, 9))
				draw_colored_polygon(crescent, INK)
			"cloud", "rain", "storm":
				draw_circle(Vector2(10, 12), 5, INK)
				draw_circle(Vector2(16, 9), 6, INK)
				draw_circle(Vector2(22, 12), 4, INK)
				draw_line(Vector2(8, 16), Vector2(23, 16), INK, 2, true)
				if state == "storm":
					draw_polyline(PackedVector2Array([Vector2(18,17),Vector2(14,22),Vector2(18,22),Vector2(14,28)]), Color("e5cf8e"), 2, true)
				elif state == "rain":
					for x in [10, 16, 22]:
						draw_line(Vector2(x, 20), Vector2(x-2, 25), Color("9dc8da"), 1.5, true)
			"snow":
				for i in 6:
					var d := Vector2.from_angle(i * TAU / 6.0)
					draw_line(c, c+d*10, INK, 1.5, true)
					draw_line(c+d*6, c+d*6+d.rotated(2.3)*4, INK, 1.5, true)
			"wind":
				for i in 3:
					draw_line(Vector2(5+i*2, 9+i*6),Vector2(24-i*2,9+i*6), INK, 1.5, true)

var row: HBoxContainer
var icon: WeatherIcon
var clock_label: Label
var _mounted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	row = HBoxContainer.new()
	row.name = "WeatherReadout"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_theme_constant_override("separation", 5)
	icon = WeatherIcon.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	clock_label = Label.new()
	clock_label.set_meta("preserve_hud_ink", true)
	clock_label.add_theme_font_override("font", preload("res://ui/ProjectTypography.gd").SEMIBOLD)
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_label.add_theme_font_size_override("font_size", 24)
	clock_label.add_theme_color_override("font_color", Color("d9e3e5"))
	clock_label.add_theme_color_override("font_outline_color", Color(0.05,0.07,0.09,0.85))
	clock_label.add_theme_constant_override("outline_size", 3)
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(clock_label)
	add_child(row)
	row.hide()
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(refresh)
	add_child(timer)
	timer.start()
	call_deferred("refresh")

func refresh() -> void:
	var world := get_parent()
	if not is_instance_valid(world) or not "weather" in world or not is_instance_valid(world.weather):
		row.hide()
		return
	if not _mounted:
		# Participate in the existing HUD layout rather than overlaying its money
		# or stars. No edit to HUD.tscn; if UI is being reorganized, stay hidden.
		for hud in get_tree().get_nodes_in_group("hud"):
			if world.is_ancestor_of(hud):
				var target := hud.get_node_or_null("RootMargin/TopRightPanel")
				if target is BoxContainer:
					row.reparent(target)
					target.move_child(row, 0)
					_mounted = true
					break
	var weather: Node = world.weather
	var state := describe(weather)
	clock_label.text = state.clock
	if icon.state != state.icon:
		icon.state = state.icon
		icon.queue_redraw()
	var arrival := world.get_node_or_null("ArrivalMission")
	var opening := arrival != null and str(arrival.get("phase")) == "arrival"
	row.visible = _mounted and bool(world.get("gameplay_ready")) and not opening and not get_tree().paused

static func describe(weather: Node) -> Dictionary:
	var day := float(weather.get("time_of_day"))
	if not is_finite(day):
		day = 0.0
	var minutes := int(floor(fposmod(day, 1.0) * 1440.0)) % 1440
	var state := "sun"
	var biome := int(weather.get("current_biome"))
	var precipitation := int(weather.get("weather_state"))
	if biome == 1:
		state = "snow"
	elif biome == 2:
		state = "wind"
	elif precipitation == 3:
		state = "cloud"
	elif precipitation > 0:
		state = "storm" if precipitation == 2 else "rain"
	elif day < 0.30 or day >= 0.79:
		state = "moon"
	return {"icon": state, "clock": "%02d:%02d" % [minutes / 60, minutes % 60]}

func _exit_tree() -> void:
	# Row may belong to the HUD after reparenting; release only our own widget.
	if is_instance_valid(row):
		row.queue_free()
