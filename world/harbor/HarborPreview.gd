extends Node2D

## Standalone playable review. No main-menu, save, district or mission rewiring.
const WEATHER_MANAGER := preload("res://systems/DayNightWeatherManager.gd")
@export var review_mode := true

var world_build_ready := false
var _overview := true
var _dragging := false
var _follow_train := false
var _status: Label
var _panel: CanvasLayer
var _clock := 0.0

# Environment panel — reuses the existing DayNightWeatherManager (time palette,
# clouds, drizzle particles+audio, time_changed/is_raining contract) rather than
# a second weather system. See world/harbor/README.md for the
# lamp-post/window-light interface this exposes.
var weather: CanvasModulate
var _review_time_index := 1
var _review_weather_index := 0
var _show_perf_hud := false
var _perf_hud: Label

func _ready() -> void:
	add_child(preload("res://world/harbor/WorldPerimeter.gd").new())
	var combat_effects := preload("res://guns/combat/WeaponEffects.gd").new()
	combat_effects.name = "WeaponEffects"
	add_child(combat_effects)
	weather = WEATHER_MANAGER.new()
	weather.name = "DayNightWeather"
	weather.is_dynamic_time = false
	weather.time_of_day = 0.45
	add_child(weather)
	weather.enable_regional_atmosphere()
	var road_lighting := preload("res://geodata/roads/RoadLighting.gd").new()
	road_lighting.name = "RoadLighting"
	add_child(road_lighting)
	if review_mode:
		_build_review_ui()
	call_deferred("_start_review")

func _start_review() -> void:
	# A campanha consulta o território no mesmo ciclo de inicialização.
	_setup_cobras()
	await get_tree().process_frame
	_setup_emergency_services()
	await get_tree().process_frame
	_setup_thematic_fleet()
	await get_tree().process_frame
	# Exterior-only reviews intentionally do not create interior rooms.
	if review_mode and $Interiors.enabled:
		var paint_bay := preload("res://prototypes/living_cast/HarborPaintBay.gd").new()
		paint_bay.name = "PaintAndSpray"
		$Interiors.garage_interior.add_child(paint_bay)
		await get_tree().process_frame
	# Local pacing preset, applied after PlayerCar has loaded its catalog stats.
	$PlayerCar.max_speed *= 0.75
	$PlayerCar.acceleration *= 0.75
	$PlayerCar/Camera.max_speed = $PlayerCar.max_speed
	if review_mode:
		$OverviewCamera.make_current()
		$OverviewCamera.zoom = Vector2.ONE * _full_map_zoom()
	var errors: Array = []
	var building_count := 0
	var access_count := 0
	for district in [$District, $EastDistrict, $NorthDistrict]:
		errors.append_array(district.get_spatial_audit())
		await get_tree().process_frame
		building_count += district.sites.size()
		access_count += district.accesses.size()
	errors.append_array($RoadNetwork.get_validation_errors())
	errors.append_array($RoadSafety.get_safety_data().validation_errors)
	for error in errors:
		push_error("Breakwater: " + String(error))
	print("BREAKWATER_AUDIT buildings=%d access_routes=%d issues=%d" % [building_count, access_count, errors.size()])
	if has_node("CobraNeighborhood"):
		for issue in $CobraNeighborhood.get_spatial_audit():
			push_error("Ashbend Court: " + issue)

	# GETECO-PERF-03A: HarborSouthPort._ready() agora constrói em etapas (ver o
	# script) em vez de bloquear um quadro inteiro; world_build_ready não pode
	# virar true antes dela terminar, ou GameLoading libera o jogador com o
	# porto pela metade. Mesmo padrão de espera já usado para region_ready em
	# MountainPass/ContinuousWorld.
	if has_node("SouthPort"):
		while not $SouthPort.port_ready: await get_tree().process_frame

	world_build_ready = true

func _setup_emergency_services() -> void:
	if has_node("HarborEmergencyDirector"):
		return
	var director := preload("res://world/harbor/HarborEmergencyDirector.gd").new()
	director.name = "HarborEmergencyDirector"
	add_child(director)
	director.configure(self)

func _setup_thematic_fleet() -> void:
	if has_node("ThematicFleet"):
		return
	var fleet_root := Node2D.new()
	fleet_root.name = "ThematicFleet"
	add_child(fleet_root)

	var factory := preload("res://emergency/ModernTrafficFactory.gd")
	# 1. Ambulância 3D na baia médica da clínica
	# Keep the clinic dispatch apron clear for the actual service ambulance.
	# Side service bay: keep the garage door and its approach clear.
	factory.spawn_parked_vehicle(fleet_root, "WorkshopTowTruck", Vector2(565, 1870), PI * 0.5, "towmaster", 0)
	# Dock Street's north sidewalk spans y=2098..2140. The former freight
	# display vehicles at y=2115 blocked pedestrians; this frontage stays clear.

func _setup_cobras() -> void:
	if not has_node("CobraNeighborhood") or has_node("CobraTerritory"):
		return
	var neighborhood := $CobraNeighborhood
	# Authored lamps are ready before this scene creates its weather manager.
	# Bind the new area's lamps now, without changing the shared lamp script.
	for lamp in neighborhood.get_children():
		if lamp is StreetLamp:
			if not weather.time_changed.is_connected(lamp.set_lit):
				weather.time_changed.connect(lamp.set_lit)
			lamp.set_lit(weather.is_dark)
	if get_tree().get_first_node_in_group("gang_manager") == null:
		var gangs := preload("res://characters/GangManager.gd").new()
		gangs.name = "HarborGangReputation"
		add_child(gangs)
	var territory := preload("res://world/harbor/cobras/CobraTerritory.gd").new()
	territory.name = "CobraTerritory"
	territory.configure(neighborhood.get_neighborhood_bounds(), neighborhood.get_spawn_points(), neighborhood.get_pedestrian_routes())
	add_child(territory)
	var vehicles := preload("res://world/harbor/cobras/CobraVehicles.gd").new()
	vehicles.name = "CobraVehicles"
	vehicles.parking_positions = neighborhood.get_parking_positions()
	call_deferred("_finish_cobra_vehicles", vehicles)

func _finish_cobra_vehicles(vehicles: Node2D) -> void:
	if is_instance_valid(vehicles) and not has_node("CobraVehicles"):
		add_child(vehicles)

func _full_map_zoom() -> float:
	var viewport_size := get_viewport_rect().size
	return minf(viewport_size.x / 10600.0, maxf(240.0, viewport_size.y - 120.0) / 11000.0)

func _build_review_ui() -> void:
	_panel = CanvasLayer.new()
	_panel.name = "ReviewUI"
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	var name_label := Label.new()
	name_label.text = "BREAKWATER"
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color("#f6dfae"))
	title.add_child(name_label)
	var subtitle := Label.new()
	subtitle.text = "01 / HARBOR DISTRICT     •     PROTÓTIPO INDEPENDENTE"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color("#b1cbc7"))
	title.add_child(subtitle)
	for entry in [["Explorar a pé", _walk], ["Dirigir", _drive], ["Ir ao cais", _visit_ship], ["Visão geral [Tab]", _toggle_overview]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(125, 40)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(entry[1])
		row.add_child(button)

	var env_row := HBoxContainer.new()
	env_row.add_theme_constant_override("separation", 10)
	env_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(env_row)
	var day_night_button := Button.new()
	day_night_button.text = "☀ Dia"
	day_night_button.custom_minimum_size = Vector2(125, 40)
	day_night_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	day_night_button.pressed.connect(func():
		var presets := [
			{"label": "🌅 Amanhecer", "time": 0.23},
			{"label": "☀ Dia", "time": 0.45},
			{"label": "🌇 Pôr do sol", "time": 0.77},
			{"label": "🌙 Noite", "time": 0.90},
		]
		_review_time_index = (_review_time_index + 1) % presets.size()
		var preset: Dictionary = presets[_review_time_index]
		day_night_button.text = preset.label
		weather.time_of_day = preset.time
		weather.set_biome(weather.current_biome)
	)
	env_row.add_child(day_night_button)
	var rain_button := Button.new()
	rain_button.text = "☀ Limpo"
	rain_button.custom_minimum_size = Vector2(125, 40)
	rain_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rain_button.pressed.connect(func():
		var presets := [
			{"label": "☀ Limpo", "state": DayNightWeatherManager.WeatherState.CLEAR},
			{"label": "☁ Nublado", "state": DayNightWeatherManager.WeatherState.CLOUDY},
			{"label": "🌦 Garoa", "state": DayNightWeatherManager.WeatherState.DRIZZLE},
		]
		_review_weather_index = (_review_weather_index + 1) % presets.size()
		var preset: Dictionary = presets[_review_weather_index]
		rain_button.text = preset.label
		if preset.state == DayNightWeatherManager.WeatherState.DRIZZLE:
			weather.set_rain_intensity(0.22)
		weather.set_weather(preset.state)
	)
	env_row.add_child(rain_button)
	var perf_button := Button.new()
	perf_button.text = "📊 FPS"
	perf_button.custom_minimum_size = Vector2(90, 40)
	perf_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	perf_button.pressed.connect(func():
		_show_perf_hud = not _show_perf_hud
		_perf_hud.visible = _show_perf_hud
	)
	env_row.add_child(perf_button)

	_perf_hud = Label.new()
	_perf_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_perf_hud.offset_left = -190
	_perf_hud.offset_top = 18
	_perf_hud.offset_right = -24
	_perf_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf_hud.add_theme_font_size_override("font_size", 13)
	_perf_hud.add_theme_color_override("font_color", Color("#9be89b"))
	_perf_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_perf_hud.add_theme_constant_override("shadow_offset_x", 1)
	_perf_hud.add_theme_constant_override("shadow_offset_y", 1)
	_perf_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf_hud.visible = false
	_panel.add_child(_perf_hud)

	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -55
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.09, 0.94)
	style.content_margin_left = 24
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	footer.add_theme_stylebox_override("panel", style)
	_panel.add_child(footer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color("#d4dfd7"))
	footer.add_child(_status)

func _walk() -> void:
	_follow_train = false
	if $PlayerCar.is_driven_by_player:
		$PlayerCar.exit_vehicle()
	_overview = false
	$Player/Camera.make_current()

func _visit_ship() -> void:
	# Review shortcut starts on LAND, not aboard: boarding still requires walking
	# across the physical gangway with the normal Player controller.
	_walk()
	var access: Dictionary = $Waterfront.get_ship_access_data()
	var route: PackedVector2Array = access.get("walk_route", PackedVector2Array())
	if not route.is_empty():
		$Player.global_position = $Waterfront.to_global(route[0])
		$Player.velocity = Vector2.ZERO
		$Player/Camera.reset_smoothing()

func _visit_south_port() -> void:
	_walk()
	$Player.global_position = Vector2(3570,2070)
	$Player.velocity = Vector2.ZERO
	$Player/Camera.reset_smoothing()

func _drive() -> void:
	_follow_train = false
	if not $PlayerCar.is_driven_by_player:
		# Review shortcut places the actor at the parked vehicle, then uses the
		# existing entry implementation (no second driving controller).
		$Player.global_position = $PlayerCar.global_position + Vector2(-48, 0)
		$PlayerCar.enter_vehicle($Player)
	_overview = false
	$PlayerCar/Camera.make_current()

func _toggle_overview() -> void:
	_follow_train = false
	_overview = not _overview
	if _overview:
		$OverviewCamera.make_current()
	elif $PlayerCar.is_driven_by_player:
		$PlayerCar/Camera.make_current()
	else:
		$Player/Camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if not review_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_overview()
		elif event.keycode == KEY_P:
			_visit_south_port()
		elif event.keycode == KEY_T:
			_follow_train = not _follow_train
			_overview = true
			$OverviewCamera.make_current()
			$OverviewCamera.zoom = Vector2.ONE * 0.85
		elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_N, KEY_0]:
			_follow_train = false
			_overview = true
			$OverviewCamera.make_current()
			var point := Vector2(3320, 800)
			var scale_value := _full_map_zoom()
			if event.keycode == KEY_1:
				point = Vector2(1260, 890)
				scale_value = 0.65
			elif event.keycode == KEY_2:
				point = Vector2(1450, 1840)
				scale_value = 0.65
			elif event.keycode == KEY_3:
				point = Vector2(3200, 1380)
				scale_value = 0.48
			elif event.keycode == KEY_4:
				point = Vector2(5550, 1250)
				scale_value = 0.40
			elif event.keycode == KEY_5:
				point = Vector2(2200, 892)
				scale_value = 0.65
			elif event.keycode == KEY_6:
				point = Vector2(3114, 3100)
				scale_value = 0.65
			elif event.keycode == KEY_7:
				point = Vector2(855, 860)
				scale_value = 0.95
			elif event.keycode == KEY_8:
				point = Vector2(5100, 1460)
				scale_value = 0.55
			elif event.keycode == KEY_9:
				point = Vector2(6000, -3010)
				scale_value = minf(0.35, maxf(240.0, get_viewport_rect().size.y - 120.0) / 2700.0)
			elif event.keycode == KEY_N:
				point = Vector2(5550, -1100)
				scale_value = minf(0.50, maxf(240.0, get_viewport_rect().size.y - 120.0) / 2250.0)
			$OverviewCamera.position = point
			$OverviewCamera.zoom = Vector2.ONE * scale_value
	if not _overview:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			$OverviewCamera.zoom = Vector2.ONE * clampf($OverviewCamera.zoom.x * factor, 0.04, 1.4)
	elif event is InputEventMouseMotion and _dragging:
		$OverviewCamera.position -= event.relative / $OverviewCamera.zoom

func _process(delta: float) -> void:
	if _show_perf_hud and _perf_hud != null:
		var fps := Engine.get_frames_per_second()
		_perf_hud.text = "FPS: %d\nFrame: %.1f ms" % [fps, 1000.0 / maxf(fps, 0.001)]
	if _follow_train:
		var train := $FreightRail.get_node_or_null("AmbientTrain") as Node2D
		if train != null and train.self_modulate.a > 0.1:
			$OverviewCamera.position = train.global_position
	_clock += delta
	if _clock < 0.5 or _status == null:
		return
	_clock = 0.0
	var population: Dictionary = $Life.get_population_snapshot()
	_status.text = "WASD mover • E entrar/sair • Tab mapa • P passarela do Porto Sul • 4 Northbank • 5 viaduto • 6 túnel • 8 ruas • 9 rodovia • T trem • 0 geral\n%d veículos / %d pedestres • Porto Sul: desça pela passarela na popa ou pela ponte ao fim da avenida do cais." % [population.vehicles, population.pedestrians]
