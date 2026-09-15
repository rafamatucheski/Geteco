extends CanvasLayer

@onready var money_label: Label = $RootMargin/TopRightPanel/Money
@onready var stars_label: Label = $RootMargin/TopRightPanel/Stars
@onready var health_bar: ProgressBar = $RootMargin/TopLeftPanel/HealthRow/HealthBar
@onready var armor_bar: ProgressBar = $RootMargin/TopLeftPanel/ArmorRow/ArmorBar
@onready var weapon_icon: WeaponIcon3D = $RootMargin/TopLeftPanel/WeaponRow/WeaponIcon
@onready var ammo_label: Label = $RootMargin/TopLeftPanel/WeaponRow/AmmoLabel
@onready var weapon_row: VBoxContainer = $RootMargin/TopLeftPanel/WeaponRow
@onready var armor_row: HBoxContainer = $RootMargin/TopLeftPanel/ArmorRow
@onready var horn_test_button: Button = $RootMargin/VehicleTestPanel/HornTestButton
@onready var headlight_test_button: Button = $RootMargin/VehicleTestPanel/HeadlightTestButton
@onready var map_overview_button: Button = $RootMargin/VehicleTestPanel/MapOverviewButton

var current_money: int = 0
var current_stars: int = 0

## Keep mission text below clock, weapon, vitals and optional wanted stars.
## Container resizing also covers font scaling and window changes.
func place_objective_card(card: Control) -> void:
	var column := $RootMargin/TopRightPanel as Control
	var layout := func():
		if is_instance_valid(card):
			card.position.y = maxf(180.0, column.get_global_rect().end.y + 12.0)
	column.resized.connect(layout)
	card.tree_exiting.connect(func():
		if column.resized.is_connected(layout): column.resized.disconnect(layout))
	layout.call_deferred()

func _layout_classic_status() -> void:
	var column := $RootMargin/TopRightPanel as VBoxContainer
	var vitals := $RootMargin/TopLeftPanel as VBoxContainer
	var status := HBoxContainer.new()
	status.name = "Status"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override("separation", 6)
	column.add_child(status)
	column.move_child(status, 0)
	weapon_row.reparent(status)
	vitals.reparent(status)
	vitals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vitals.add_theme_constant_override("separation", 6)
	weapon_icon.custom_minimum_size = Vector2(64, 48)
	health_bar.custom_minimum_size = Vector2(120, 12)
	armor_bar.custom_minimum_size = Vector2(120, 8)
	for label in [money_label, stars_label, ammo_label]:
		label.set_meta("preserve_hud_ink", true)
		label.add_theme_font_override("font", preload("res://ui/ProjectTypography.gd").SEMIBOLD)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
	money_label.add_theme_color_override("font_color", Color("609b62"))
	money_label.add_theme_font_size_override("font_size", 28)
	ammo_label.add_theme_font_size_override("font_size", 18)
	stars_label.add_theme_font_size_override("font_size", 22)
	column.add_theme_constant_override("separation", 4)

## Contextual vitals (such as body temperature) share the same quiet stack as
## health and body armor. Keeping the container owned by HUD also makes the
## indicator follow font scaling and the top-right safe margin automatically.
func attach_vital_indicator(indicator: Control) -> void:
	if not is_instance_valid(indicator) or not is_instance_valid(health_bar):
		return
	var vitals := health_bar.get_parent().get_parent() as VBoxContainer
	if not is_instance_valid(vitals):
		return
	if indicator.get_parent() != vitals:
		indicator.reparent(vitals)
	indicator.set_anchors_preset(Control.PRESET_TOP_LEFT)
	indicator.offset_left = 0.0
	indicator.offset_top = 0.0
	indicator.offset_right = 0.0
	indicator.offset_bottom = 0.0
	indicator.size_flags_horizontal = Control.SIZE_SHRINK_END
	# Context sits immediately after armor; when armor is absent it naturally
	# closes up under health without leaving an empty slot.
	vitals.move_child(indicator, armor_row.get_index() + 1)

func _ready() -> void:
	add_to_group("hud")
	_layout_classic_status()
	update_money(0)
	update_stars(0)
	_style_bar(health_bar, Color("c83e42"))
	_style_bar(armor_bar, Color("c4dcec"))
	set_weapon_info("fists", {})
	set_armor(0, 100)
	_update_vehicle_test_panel()

func _process(_delta: float) -> void:
	_update_vehicle_test_panel()
	_layout_achievement()

func update_money(amount: int) -> void:
	current_money += amount
	if money_label:
		money_label.text = "$%08d" % current_money

func set_money(amount: int) -> void:
	current_money = maxi(0, amount)
	if money_label:
		money_label.text = "$%08d" % current_money

func set_weapon_info(weapon_id: String, ammo: Dictionary) -> void:
	var equipped := not weapon_id.is_empty() and weapon_id != "fists"
	weapon_row.visible = true
	if ammo_label:
		var clip := int(ammo.get("clip", 0))
		var has_ammo := equipped and weapon_id != "knife" and clip >= 0
		ammo_label.visible = has_ammo
		ammo_label.text = "%d-%d" % [clip, maxi(0, int(ammo.get("reserve", 0)))] if has_ammo else ""
	if weapon_icon:
		weapon_icon.set_weapon(weapon_id)

func set_armor(current: int, maximum: int) -> void:
	if armor_bar:
		armor_bar.max_value = maximum
		armor_bar.value = current
		armor_row.visible = current > 0

func update_health(amount: int) -> void:
	if health_bar:
		health_bar.value = amount

func set_stars(level: int) -> void:
	update_stars(level)

func update_stars(level: int) -> void:
	current_stars = clamp(level, 0, 6)
	var stars_text := ""
	for i in range(6):
		if i < current_stars:
			stars_text += "★"
		else:
			stars_text += "☆"
	if stars_label:
		stars_label.text = stars_text
		stars_label.visible = current_stars > 0

func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	if not bar: return
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

func _update_vehicle_test_panel() -> void:
	var vehicle = _get_driven_vehicle()
	var camera := get_viewport().get_camera_2d()

	if map_overview_button and is_instance_valid(camera) and camera.has_method("is_overview_mode"):
		map_overview_button.text = "Mapa Inteiro (F9): " + ("ON" if camera.is_overview_mode() else "OFF")
		map_overview_button.disabled = false
	else:
		if map_overview_button:
			map_overview_button.disabled = true
			map_overview_button.text = "Mapa Inteiro (F9): OFF"

	if not is_instance_valid(vehicle):
		if horn_test_button:
			horn_test_button.disabled = true
		if headlight_test_button:
			headlight_test_button.disabled = true
			headlight_test_button.text = "Luz (L): OFF"
		return

	if horn_test_button:
		horn_test_button.disabled = false
	if headlight_test_button:
		var light_on := false
		if vehicle.has_method("is_headlight_on"):
			light_on = bool(vehicle.is_headlight_on())
		else:
			var node_headlight = vehicle.get("headlight")
			if node_headlight != null and node_headlight is PointLight2D:
				light_on = node_headlight.visible
		headlight_test_button.text = "Luz (L): " + ("LIGADA" if light_on else "DESLIGADA")
		headlight_test_button.disabled = false

func _get_driven_vehicle() -> Node:
	for car in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(car) and car.get("is_driven_by_player") == true:
			return car
	for car in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(car) and car.has_method("honk_horn"):
			return car
	return null

func _on_horn_test_button_pressed() -> void:
	var vehicle := _get_driven_vehicle()
	if vehicle and vehicle.has_method("honk_horn"):
		vehicle.honk_horn()

func _on_headlight_test_button_pressed() -> void:
	var vehicle := _get_driven_vehicle()
	if vehicle and vehicle.has_method("toggle_headlights"):
		vehicle.toggle_headlights()

func _on_map_overview_button_pressed() -> void:
	var camera = get_viewport().get_camera_2d()
	if is_instance_valid(camera) and camera.has_method("set_overview_mode") and camera.has_method("is_overview_mode"):
		camera.set_overview_mode(not camera.is_overview_mode())


var vehicle_name_label: Label
var _vehicle_name_tween: Tween

func show_vehicle_name(vehicle_name: String) -> void:
	if vehicle_name_label == null:
		vehicle_name_label = Label.new()
		vehicle_name_label.name = "VehicleName"
		vehicle_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vehicle_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vehicle_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vehicle_name_label.add_theme_font_override("font", preload("res://ui/ProjectTypography.gd").ITALIC)
		vehicle_name_label.add_theme_font_size_override("font_size", 28)
		vehicle_name_label.add_theme_color_override("font_color", Color("e8ce88"))
		vehicle_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
		vehicle_name_label.add_theme_constant_override("outline_size", 1)
		add_child(vehicle_name_label)
		vehicle_name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		vehicle_name_label.offset_left = -620
		vehicle_name_label.offset_right = -42
		vehicle_name_label.offset_top = -138
		vehicle_name_label.offset_bottom = -42
	if _vehicle_name_tween != null and _vehicle_name_tween.is_valid():
		_vehicle_name_tween.kill()
	vehicle_name_label.text = vehicle_name
	vehicle_name_label.modulate.a = 0.0
	vehicle_name_label.show()
	_vehicle_name_tween = create_tween()
	_vehicle_name_tween.tween_property(vehicle_name_label, "modulate:a", 1.0, 0.2)
	_vehicle_name_tween.tween_interval(3.2)
	_vehicle_name_tween.tween_property(vehicle_name_label, "modulate:a", 0.0, 0.8)
	_vehicle_name_tween.tween_callback(vehicle_name_label.hide)


var notice_label: Label
var _notice_tween: Tween

## Aviso central curto e genérico (achados, corridas, marcos) — some sozinho.
func show_notice(text: String, color: Color = Color("#ffffff")) -> void:
	if notice_label == null:
		notice_label = Label.new()
		notice_label.name = "NoticeLabel"
		notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice_label.add_theme_font_size_override("font_size", 20)
		notice_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
		notice_label.add_theme_constant_override("outline_size", 5)
		add_child(notice_label)
		notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		notice_label.offset_left = -280
		notice_label.offset_right = 280
		notice_label.offset_top = 146
		notice_label.offset_bottom = 198
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	notice_label.text = text
	notice_label.add_theme_color_override("font_color", color)
	notice_label.modulate.a = 0.0
	notice_label.show()
	_notice_tween = create_tween()
	_notice_tween.tween_property(notice_label, "modulate:a", 1.0, 0.18)
	_notice_tween.tween_interval(2.3)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.7)
	_notice_tween.tween_callback(notice_label.hide)


var achievement_panel: PanelContainer
var achievement_title_label: Label
var achievement_desc_label: Label
var _achievement_tween: Tween
var _achievement_audio: AudioStreamPlayer
var _achievement_queue: Array[Dictionary] = []
var _achievement_presenting := false

## Top-center, independently of the right-hand status stack.
func _layout_achievement() -> void:
	if not is_instance_valid(achievement_panel): return
	var width := minf(440.0, get_viewport().get_visible_rect().size.x - 48.0)
	achievement_panel.offset_left = -width * 0.5
	achievement_panel.offset_right = width * 0.5
	achievement_panel.offset_top = 28.0
	achievement_panel.offset_bottom = 28.0 + maxf(achievement_panel.get_combined_minimum_size().y, 80.0)
	if is_instance_valid(notice_label):
		notice_label.position.y = maxf(146.0, achievement_panel.get_global_rect().end.y + 12.0) if achievement_panel.visible else 146.0

func show_achievement(title: String, desc: String) -> void:
	_achievement_queue.append({"title": title, "desc": desc})
	if not _achievement_presenting: _show_next_achievement()

func _show_next_achievement() -> void:
	if _achievement_queue.is_empty():
		_achievement_presenting = false
		return
	_achievement_presenting = true
	var entry: Dictionary = _achievement_queue.pop_front()
	var title := String(entry.title)
	var desc := String(entry.desc)
	if achievement_panel == null:
		achievement_panel = PanelContainer.new()
		achievement_panel.name = "AchievementPanel"
		achievement_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.03, 0.92)
		style.border_color = Color("#f6c445")
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		achievement_panel.add_theme_stylebox_override("panel", style)
		add_child(achievement_panel)
		achievement_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)

		var vbox := VBoxContainer.new()
		achievement_panel.add_child(vbox)

		var header := Label.new()
		header.text = "CONQUISTA DESBLOQUEADA"
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", Color("#f6c445"))
		vbox.add_child(header)

		achievement_title_label = Label.new()
		achievement_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		achievement_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		achievement_title_label.add_theme_font_size_override("font_size", 15)
		achievement_title_label.add_theme_color_override("font_color", Color("#ffffff"))
		vbox.add_child(achievement_title_label)

		achievement_desc_label = Label.new()
		achievement_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		achievement_desc_label.add_theme_font_size_override("font_size", 10)
		achievement_desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		achievement_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(achievement_desc_label)

		_achievement_audio = AudioStreamPlayer.new()
		_achievement_audio.bus = &"SFX"
		add_child(_achievement_audio)

	achievement_title_label.text = title
	achievement_desc_label.text = desc
	_layout_achievement()
	if _achievement_tween != null and _achievement_tween.is_valid():
		_achievement_tween.kill()
	achievement_panel.modulate.a = 0.0
	achievement_panel.hide()

	_achievement_audio.stream = preload("res://audio/rewards/RewardAudioBank.gd").sound("achievement")
	_achievement_audio.pitch_scale = 1.0
	_achievement_audio.volume_db = -2.0
	# Let a discovery finish its short phrase before the achievement answers.
	var delay := 0.0
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var pool := host.get_node_or_null("RewardAudioVoices")
	if pool != null:
		for voice in pool.get_children():
			if voice is AudioStreamPlayer and voice.playing and voice.stream == preload("res://audio/rewards/RewardAudioBank.gd").sound("collectible"):
				delay = maxf(delay, voice.stream.get_length() - voice.get_playback_position())
	_achievement_tween = create_tween()
	if delay > 0.0: _achievement_tween.tween_interval(delay)
	_achievement_tween.tween_callback(func():
		achievement_panel.show()
		_achievement_audio.play()
	)
	_achievement_tween.tween_property(achievement_panel, "modulate:a", 1.0, 0.25)
	_achievement_tween.tween_interval(3.4)
	_achievement_tween.tween_property(achievement_panel, "modulate:a", 0.0, 0.6)
	_achievement_tween.tween_callback(achievement_panel.hide)
	_achievement_tween.tween_callback(_show_next_achievement)


var mission_passed_banner: VBoxContainer
var mission_passed_title: Label
var mission_passed_reward: Label
var _mission_passed_tween: Tween

## Presentation only: callers supply rewards already granted by mission state.
## Audio stays at the completion site, so loading saves cannot replay a victory.
func show_mission_passed(cash: int = 0, respect: int = 0) -> void:
	if not is_instance_valid(mission_passed_banner):
		mission_passed_banner = VBoxContainer.new()
		mission_passed_banner.name = "MissionPassed"
		mission_passed_banner.process_mode = Node.PROCESS_MODE_ALWAYS
		mission_passed_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mission_passed_banner.add_theme_constant_override("separation", -8)
		add_child(mission_passed_banner)
		mission_passed_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		mission_passed_title = Label.new()
		mission_passed_reward = Label.new()
		for label in [mission_passed_title, mission_passed_reward]:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.set_meta("preserve_hud_ink", true)
			label.add_theme_font_override("font", preload("res://ui/ProjectTypography.gd").SEMIBOLD)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 10)
			mission_passed_banner.add_child(label)
		mission_passed_title.add_theme_color_override("font_color", Color("d5a43a"))
		mission_passed_reward.add_theme_color_override("font_color", Color("f3f0e7"))
		get_viewport().size_changed.connect(_layout_mission_passed)
	var english := TranslationServer.get_locale().begins_with("en")
	mission_passed_title.text = "MISSION PASSED!" if english else "MISSÃO CUMPRIDA!"
	var rewards := PackedStringArray()
	if cash > 0: rewards.append("+$%d" % cash)
	if respect > 0: rewards.append(("RESPECT +%d" if english else "RESPEITO +%d") % respect)
	mission_passed_reward.text = "  ·  ".join(rewards)
	mission_passed_reward.visible = not rewards.is_empty()
	_layout_mission_passed()
	if _mission_passed_tween != null and _mission_passed_tween.is_valid():
		_mission_passed_tween.kill()
	mission_passed_banner.modulate.a = 0.0
	mission_passed_banner.show()
	_mission_passed_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_mission_passed_tween.tween_property(mission_passed_banner, "modulate:a", 1.0, 0.16)
	_mission_passed_tween.tween_interval(4.8)
	_mission_passed_tween.tween_property(mission_passed_banner, "modulate:a", 0.0, 0.85)
	_mission_passed_tween.tween_callback(mission_passed_banner.hide)

func _layout_mission_passed() -> void:
	if not is_instance_valid(mission_passed_banner): return
	var width := get_viewport().get_visible_rect().size.x
	var font_size := clampi(roundi(width * 0.048), 26, 78)
	mission_passed_title.add_theme_font_size_override("font_size", font_size)
	mission_passed_reward.add_theme_font_size_override("font_size", roundi(font_size * 0.64))
	mission_passed_banner.offset_left = -width * 0.46
	mission_passed_banner.offset_right = width * 0.46
	mission_passed_banner.offset_top = -72
	mission_passed_banner.offset_bottom = 50
