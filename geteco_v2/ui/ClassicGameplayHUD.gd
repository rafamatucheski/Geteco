extends CanvasLayer
## Production V1 gameplay HUD mounted over the V2 state model.
## FullSession and Driving keep their compatibility nodes; this adapter reads
## and hides those sources, without moving presentation into central systems.

const STYLE := preload("res://ui/GameStyle.gd")
const WEAPON_ICON := preload("res://ui/v1/WeaponIcon3D.gd")
const INTERACTION_KEYCAP := preload("res://ui/v1/InteractionKeycap.gd")
const WEATHER_ICON := preload("res://ui/v1/WeatherIcon.gd")
const MINIMAP := preload("res://ui/v1/HarborMinimap3D.gd")
const FONT_SEMIBOLD := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")

const MONEY_COLOR := Color("609b62")
const STAR_COLOR := Color(1.0, 0.85, 0.0, 1.0)
const HEALTH_COLOR := Color("c83e42")
const ARMOR_COLOR := Color("c4dcec")

var world: Node
var root_control: Control
var root_margin: MarginContainer
var top_right_panel: VBoxContainer
var weather_row: HBoxContainer
var weather_icon: Control
var clock_label: Label
var status_row: HBoxContainer
var weapon_row: VBoxContainer
var weapon_icon: Control
var ammo_label: Label
var vitals: VBoxContainer
var health_bar: ProgressBar
var armor_row: HBoxContainer
var armor_bar: ProgressBar
var money_label: Label
var stars_label: Label
var objective_card: PanelContainer
var objective_label: Label
var interaction_row: HBoxContainer
var interaction_key: Label
var interaction_label: Label
var notice_label: Label
var speed_label: Label
var thermal_label: Label
var minimap: Control

var _session: Node
var _driving: Node
var _controls: Node
var _legacy_stats: Label
var _legacy_objective: Label
var _legacy_prompt: Label
var _legacy_notice: Label
var _legacy_thermal: Label
var _legacy_driving_prompt: Label
var _legacy_help: Label
var _legacy_speed: Label
var _bound := false
var _status_clock := 0.0
var _last_notice := ""
var _notice_tween: Tween
var _last_modal_signature := ""

func _ready() -> void:
	name = "HUD"
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	add_to_group("hud")
	_build_v1_interface()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_v1_interface() -> void:
	root_control = Control.new()
	root_control.name = "GameplayHUDRoot"
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	root_margin = MarginContainer.new()
	root_margin.name = "RootMargin"
	root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(root_margin)

	top_right_panel = VBoxContainer.new()
	top_right_panel.name = "TopRightPanel"
	top_right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_right_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_right_panel.add_theme_constant_override("separation", 4)
	root_margin.add_child(top_right_panel)
	weather_row = HBoxContainer.new()
	weather_row.name = "WeatherReadout"
	weather_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	weather_row.add_theme_constant_override("separation", 5)
	top_right_panel.add_child(weather_row)
	weather_icon = WEATHER_ICON.new()
	weather_icon.custom_minimum_size = Vector2(24, 24)
	weather_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_row.add_child(weather_icon)
	clock_label = _outlined_label("Clock", 24, Color("d9e3e5"), 3)
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weather_row.add_child(clock_label)

	status_row = HBoxContainer.new()
	status_row.name = "Status"
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_row.add_theme_constant_override("separation", 6)
	top_right_panel.add_child(status_row)

	weapon_row = VBoxContainer.new()
	weapon_row.name = "WeaponRow"
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weapon_row.add_theme_constant_override("separation", 0)
	status_row.add_child(weapon_row)
	weapon_icon = WEAPON_ICON.new()
	weapon_icon.name = "WeaponIcon"
	weapon_icon.custom_minimum_size = Vector2(64, 48)
	weapon_icon.set("frameless", true)
	weapon_row.add_child(weapon_icon)
	ammo_label = _outlined_label("AmmoLabel", 18, Color(0.88, 0.91, 0.94, 0.85), 5)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_row.add_child(ammo_label)

	vitals = VBoxContainer.new()
	vitals.name = "TopLeftPanel"
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vitals.add_theme_constant_override("separation", 6)
	status_row.add_child(vitals)
	var health_row := HBoxContainer.new()
	health_row.name = "HealthRow"
	vitals.add_child(health_row)
	health_bar = _make_bar("HealthBar", Vector2(120, 12), HEALTH_COLOR)
	health_row.add_child(health_bar)
	armor_row = HBoxContainer.new()
	armor_row.name = "ArmorRow"
	vitals.add_child(armor_row)
	armor_bar = _make_bar("ArmorBar", Vector2(120, 8), ARMOR_COLOR)
	armor_row.add_child(armor_bar)
	thermal_label = _outlined_label("Thermal", 14, Color("e9f2f6"), 3)
	thermal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vitals.add_child(thermal_label)

	money_label = _outlined_label("Money", 28, MONEY_COLOR, 5)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right_panel.add_child(money_label)
	stars_label = _outlined_label("Stars", 22, STAR_COLOR, 5)
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right_panel.add_child(stars_label)

	objective_card = PanelContainer.new()
	objective_card.name = "ObjectiveCard"
	objective_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_card.custom_minimum_size = Vector2(320, 0)
	objective_card.set_meta("preserve_panel_style", true)
	objective_card.add_theme_stylebox_override("panel", STYLE.objective_strip())
	root_control.add_child(objective_card)
	objective_label = _plain_label("Objective", 15, Color.WHITE)
	objective_label.custom_minimum_size = Vector2(298, 0)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	objective_label.add_theme_constant_override("shadow_offset_x", 1)
	objective_label.add_theme_constant_override("shadow_offset_y", 1)
	objective_card.add_child(objective_label)

	# V1 prompts are world-space. The 3D projection needs a fixed safe anchor,
	# while retaining the same compact keycap and unboxed typography.
	interaction_row = HBoxContainer.new()
	interaction_row.name = "Interaction"
	interaction_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_row.add_theme_constant_override("separation", 12)
	root_control.add_child(interaction_row)
	interaction_key = _plain_label("InteractionKey", 16, Color("f4eddf"))
	interaction_key.custom_minimum_size = Vector2(42, 32)
	interaction_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_row.add_child(interaction_key)
	interaction_label = _outlined_label("InteractionText", 20, Color.WHITE, 4)
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_row.add_child(interaction_label)

	notice_label = _outlined_label("NoticeLabel", 20, Color.WHITE, 5)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_control.add_child(notice_label)
	notice_label.hide()

	speed_label = _outlined_label("VehicleSpeed", 28, Color.WHITE, 5)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root_control.add_child(speed_label)
	speed_label.hide()
	minimap = MINIMAP.new()
	minimap.world = world
	root_control.add_child(minimap)

	# Driving looks this up by name. It remains a hidden compatibility source,
	# not the rejected permanent instruction ribbon.
	var help := Label.new()
	help.name = "Help"
	help.hide()
	add_child(help)

func _outlined_label(node_name: String, size_value: int, color: Color, outline: int) -> Label:
	var label := _plain_label(node_name, size_value, color)
	label.set_meta("preserve_hud_ink", true)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	return label

func _plain_label(node_name: String, size_value: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT_SEMIBOLD)
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color)
	return label

func _make_bar(node_name: String, minimum: Vector2, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = minimum
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var background := StyleBoxFlat.new()
	background.bg_color = Color("08090b")
	background.set_border_width_all(2)
	background.border_color = Color.BLACK
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill_color
	foreground.set_border_width_all(2)
	foreground.border_color = Color.BLACK
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", foreground)
	return bar

func _process(delta: float) -> void:
	if not _bound:
		_try_bind()
		if not _bound:
			_suppress_invented_scope_overlay()
			return
	_hide_legacy_sources()
	_sync_channels()
	_style_modal_if_needed()
	_suppress_invented_scope_overlay()
	_status_clock += delta
	if _status_clock >= 0.08:
		_status_clock = 0.0
		_sync_status()
		_layout()

func _try_bind() -> void:
	if world == null or not is_instance_valid(world): return
	_session = world.get("session")
	_driving = world.get("driving")
	_controls = get_node_or_null("/root/GameInput")
	if not is_instance_valid(_session) or not is_instance_valid(_driving): return
	_legacy_stats = _session.get("stats")
	_legacy_objective = _session.get("objective")
	_legacy_prompt = _session.get("prompt")
	_legacy_notice = _session.get("notice")
	_legacy_thermal = _session.get("thermal_status")
	_legacy_driving_prompt = _driving.get("prompt")
	_legacy_speed = _driving.get("speed_label")
	_legacy_help = get_node_or_null("Help")
	if not is_instance_valid(_legacy_stats) or not is_instance_valid(_legacy_objective) or not is_instance_valid(_legacy_prompt) or not is_instance_valid(_legacy_notice): return
	_bound = true
	_layout()
	_sync_status()

func _hide_legacy_sources() -> void:
	for source in [_legacy_stats, _legacy_objective, _legacy_prompt, _legacy_notice, _legacy_thermal, _legacy_driving_prompt, _legacy_help, _legacy_speed]:
		if is_instance_valid(source): source.hide()

func _sync_channels() -> void:
	var modal: bool = bool(_session.get("modal"))
	var input_locked: bool = bool(world.player.get("input_locked")) if is_instance_valid(world.player) else true
	root_margin.visible = not modal

	var objective_text := str(_legacy_objective.text).strip_edges()
	var state: Variant = _session.get("state")
	var mission_active := false
	if state != null:
		# V1 keeps onboarding/arrival prose off-screen and guides it through the
		# minimap. Only an authored active campaign uses the objective strip.
		mission_active = str(state.campaign.active_id) != ""
	if objective_text in ["J  Missões · M  Mapa", "J Missions · M Map"]: objective_text = ""
	objective_label.text = objective_text
	objective_card.visible = not modal and mission_active and not objective_text.is_empty()

	var action_text := ""
	var action_name := "interact"
	var legacy_key := "E"
	var session_action := str(_legacy_prompt.text).strip_edges()
	if not session_action.is_empty():
		action_text = _strip_action_prefix(session_action, "E")
	elif float(_driving.get("status_time")) <= 0.0:
		var driving_action := str(_legacy_driving_prompt.text).strip_edges()
		if not driving_action.is_empty():
			action_name = "exit_vehicle" if "Sair do carro" in driving_action else "vehicle_interact"
			legacy_key = "F"
			action_text = _strip_action_prefix(driving_action, legacy_key)
	var entering_car := action_name == "vehicle_interact" and action_text == "Entrar no carro"
	interaction_key.text = _hint(action_name, legacy_key)
	interaction_key.visible = not entering_car
	interaction_label.text = action_text
	interaction_row.visible = not modal and not input_locked and not action_text.is_empty()
	if interaction_row.visible: INTERACTION_KEYCAP.sync(interaction_key, not entering_car)

	var feedback := ""
	var feedback_time := 0.0
	if float(_session.get("notice_time")) > 0.0:
		feedback = str(_legacy_notice.text).strip_edges()
		feedback_time = float(_session.get("notice_time"))
	elif float(_driving.get("status_time")) > 0.0:
		feedback = str(_driving.get("status")).strip_edges()
		feedback_time = float(_driving.get("status_time"))
	if feedback != _last_notice and not feedback.is_empty(): _show_notice(feedback, feedback_time)
	if feedback.is_empty() and (_notice_tween == null or not _notice_tween.is_valid()): notice_label.hide()

	var occupied: bool = bool(_driving.get("occupied"))
	speed_label.text = str(_legacy_speed.text).strip_edges()
	speed_label.visible = occupied and not modal and not speed_label.text.is_empty()

func _sync_status() -> void:
	if not is_instance_valid(_session) or _session.get("state") == null: return
	var state: Variant = _session.get("state")
	var gameplay: Variant = world.get("gameplay")
	if gameplay == null: return
	money_label.text = "$%08d" % maxi(0, int(state.economy.balance))
	var stars := clampi(int(gameplay.stars), 0, 6)
	stars_label.text = "★".repeat(stars) + "☆".repeat(6 - stars)
	stars_label.visible = stars > 0
	var weapon_id := str(state.equipped_weapon)
	weapon_icon.call("set_weapon", weapon_id)
	weapon_row.visible = true
	var ammo: Dictionary = state.get_ammo(weapon_id)
	var magazine := int(ammo.get("magazine", -1))
	ammo_label.visible = magazine >= 0
	ammo_label.text = "%d-%d" % [magazine, maxi(0, int(ammo.get("reserve", 0)))] if magazine >= 0 else ""
	var health := clampi(roundi(float(gameplay.health)), 0, 100)
	var armor := clampi(roundi(float(gameplay.armor)), 0, 100)
	health_bar.value = health
	armor_bar.value = armor
	armor_row.visible = armor > 0
	var thermal_text := ""
	if _session.get("cold") != null:
		var thermal: Dictionary = _session.cold.status()
		if bool(thermal.get("visible", false)): thermal_text = "❄  %d%%" % roundi(float(thermal.get("temperature", 0)))
	thermal_label.text = thermal_text
	thermal_label.visible = not thermal_text.is_empty()
	_sync_weather()

func _sync_weather() -> void:
	var weather: Variant = _session.get("weather")
	weather_row.visible = weather != null and not bool(_session.get("modal")) and not get_tree().paused
	if not weather_row.visible: return
	var day := fposmod(float(weather.get("time_of_day")), 1.0)
	var minutes := int(floor(day * 1440.0)) % 1440
	clock_label.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	var next_state := "sun"
	if str(_session.state.region_id) == "mountain":
		next_state = "snow"
	elif int(weather.get("weather_state")) == 3:
		next_state = "cloud"
	elif int(weather.get("weather_state")) > 0:
		next_state = "storm" if int(weather.get("weather_state")) == 2 else "rain"
	elif day < 0.30 or day >= 0.79:
		next_state = "moon"
	if str(weather_icon.get("state")) != next_state:
		weather_icon.set("state", next_state)
		weather_icon.queue_redraw()

func _strip_action_prefix(text: String, legacy: String) -> String:
	for prefix in [legacy + "  ", legacy + " ", "[" + legacy + "] "]:
		if text.begins_with(prefix): return text.trim_prefix(prefix).strip_edges()
	return text

func _hint(action: String, fallback: String) -> String:
	if is_instance_valid(_controls) and _controls.has_method("hint"):
		var result := str(_controls.hint(action))
		if not result.is_empty() and result != "—": return result
	return fallback

func _show_notice(text: String, source_time: float) -> void:
	_last_notice = text
	notice_label.text = text
	if _notice_tween != null and _notice_tween.is_valid(): _notice_tween.kill()
	notice_label.modulate.a = 0.0
	notice_label.show()
	_notice_tween = create_tween()
	_notice_tween.tween_property(notice_label, "modulate:a", 1.0, 0.18)
	_notice_tween.tween_interval(maxf(2.3, source_time - 0.88))
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.7)
	_notice_tween.tween_callback(notice_label.hide)
	_notice_tween.tween_callback(func(): _last_notice = "")

func _style_modal_if_needed() -> void:
	if not is_instance_valid(_session.get("panel")): return
	var panel: PanelContainer = _session.panel
	var child_ids := PackedStringArray()
	for child in _session.column.get_children(): child_ids.append(str(child.get_instance_id()))
	var signature := "%s:%s" % [panel.visible, ",".join(child_ids)]
	if signature == _last_modal_signature: return
	_last_modal_signature = signature
	if not panel.visible: return
	STYLE.apply(panel)
	STYLE.trap_focus.call_deferred(panel)
	_layout_modal()

func _layout() -> void:
	if not is_instance_valid(root_control): return
	var dimensions := get_viewport().get_visible_rect().size
	var scale := clampf(minf(dimensions.x / 1280.0, dimensions.y / 720.0), 0.82, 1.18)
	root_margin.add_theme_constant_override("margin_left", roundi(24.0 * scale))
	root_margin.add_theme_constant_override("margin_top", roundi(24.0 * scale))
	root_margin.add_theme_constant_override("margin_right", roundi(24.0 * scale))
	root_margin.add_theme_constant_override("margin_bottom", roundi(24.0 * scale))
	objective_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	objective_card.position = Vector2(dimensions.x - 24.0 * scale - 320.0 * scale, maxf(180.0 * scale, top_right_panel.get_global_rect().end.y + 12.0 * scale)).round()
	objective_card.size = Vector2(320.0 * scale, objective_card.get_combined_minimum_size().y).round()
	objective_card.custom_minimum_size.x = 320.0 * scale
	objective_label.custom_minimum_size.x = 298.0 * scale
	interaction_row.reset_size()
	var interaction_size := interaction_row.get_combined_minimum_size()
	interaction_row.position = Vector2((dimensions.x - interaction_size.x) * 0.5, dimensions.y - 78.0 * scale).round()
	notice_label.position = Vector2((dimensions.x - minf(560.0 * scale, dimensions.x - 48.0)) * 0.5, 146.0 * scale).round()
	notice_label.size = Vector2(minf(560.0 * scale, dimensions.x - 48.0), 52.0 * scale).round()
	speed_label.position = Vector2(dimensions.x - 244.0 * scale, dimensions.y - 86.0 * scale).round()
	speed_label.size = Vector2(200.0 * scale, 46.0 * scale).round()
	minimap.position = Vector2(roundi(24.0 * scale), roundi(dimensions.y - 24.0 * scale - minimap.size.y))
	_layout_modal()

func _layout_modal() -> void:
	if not _bound or not is_instance_valid(_session.get("panel")): return
	var modal_panel: Control = _session.panel
	var dimensions := get_viewport().get_visible_rect().size
	var extent := Vector2(minf(640.0, dimensions.x - 48.0), minf(480.0, dimensions.y - 48.0))
	modal_panel.position = ((dimensions - extent) * 0.5).round()
	modal_panel.custom_minimum_size = extent.round()

func _suppress_invented_scope_overlay() -> void:
	# V1 scope presentation is the authored zoom, without the V2 four-bar layer.
	var reticle := get_node_or_null("ScopeReticle")
	if reticle == null: return
	for child in reticle.get_children():
		if child is CanvasItem: child.visible = false
