extends CanvasLayer

@onready var money_label: Label = $RootMargin/TopRightPanel/Money
@onready var stars_label: Label = $RootMargin/TopRightPanel/Stars
@onready var health_bar: ProgressBar = $RootMargin/TopLeftPanel/HealthRow/HealthBar
@onready var armor_bar: ProgressBar = $RootMargin/TopLeftPanel/ArmorRow/ArmorBar
@onready var weapon_icon: WeaponIcon3D = $RootMargin/TopLeftPanel/WeaponRow/WeaponIcon
@onready var ammo_label: Label = $RootMargin/TopLeftPanel/WeaponRow/AmmoLabel
@onready var horn_test_button: Button = $RootMargin/VehicleTestPanel/HornTestButton
@onready var headlight_test_button: Button = $RootMargin/VehicleTestPanel/HeadlightTestButton
@onready var map_overview_button: Button = $RootMargin/VehicleTestPanel/MapOverviewButton

var current_money: int = 0
var current_stars: int = 0

func _ready() -> void:
	add_to_group("hud")
	update_money(0)
	update_stars(0)
	_style_bar(health_bar, Color("2ed573"))
	_style_bar(armor_bar, Color("1e90ff"))
	_update_vehicle_test_panel()

func _process(_delta: float) -> void:
	_update_vehicle_test_panel()
	_layout_achievement()

func update_money(amount: int) -> void:
	current_money += amount
	if money_label:
		money_label.text = "$ %08d" % current_money

func set_money(amount: int) -> void:
	current_money = maxi(0, amount)
	if money_label:
		money_label.text = "$ %08d" % current_money

func set_weapon_info(weapon_id: String, ammo: Dictionary) -> void:
	if ammo_label:
		var clip := int(ammo.get("clip", 0))
		if clip < 0:
			# Sentinela de arma corpo a corpo (fists/knife): sem carregador nem
			# reserva, nunca mostra "-1 / -1" pro jogador.
			ammo_label.text = "CORPO A CORPO"
		else:
			ammo_label.text = "%d / %d" % [clip, int(ammo.get("reserve", 0))]
	if weapon_icon:
		weapon_icon.set_weapon(weapon_id)

func set_armor(current: int, maximum: int) -> void:
	if armor_bar:
		armor_bar.max_value = maximum
		armor_bar.value = current

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

func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	if not bar: return
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.06, 0.08, 0.85)
	background.border_color = Color(0.18, 0.22, 0.28, 0.90)
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.set_corner_radius_all(4)
	
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill_color
	foreground.set_corner_radius_all(4)
	
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
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Georgia", "serif"])
		font.font_italic = true
		vehicle_name_label.add_theme_font_override("font", font)
		vehicle_name_label.add_theme_font_size_override("font_size", 34)
		vehicle_name_label.add_theme_color_override("font_color", Color("e8ce88"))
		vehicle_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
		vehicle_name_label.add_theme_constant_override("outline_size", 6)
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
		notice_label.add_theme_font_size_override("font_size", 20)
		notice_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
		notice_label.add_theme_constant_override("outline_size", 5)
		add_child(notice_label)
		notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		notice_label.offset_left = -280
		notice_label.offset_right = 280
		notice_label.offset_top = 54
		notice_label.offset_bottom = 86
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

## Below the money, stars and weather stack, including after window resizing.
func _layout_achievement() -> void:
	if not is_instance_valid(achievement_panel): return
	var top := $RootMargin/TopRightPanel as Control
	var bottom := top.get_global_rect().end.y + 12.0
	achievement_panel.offset_top = bottom
	achievement_panel.offset_bottom = bottom + maxf(achievement_panel.get_combined_minimum_size().y, 80.0)

func show_achievement(title: String, desc: String) -> void:
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
		achievement_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		achievement_panel.offset_left = -340
		achievement_panel.offset_right = -20
		achievement_panel.offset_top = 20
		achievement_panel.offset_bottom = 80

		var vbox := VBoxContainer.new()
		achievement_panel.add_child(vbox)

		var header := Label.new()
		header.text = "CONQUISTA DESBLOQUEADA"
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", Color("#f6c445"))
		vbox.add_child(header)

		achievement_title_label = Label.new()
		achievement_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		achievement_title_label.add_theme_font_size_override("font_size", 15)
		achievement_title_label.add_theme_color_override("font_color", Color("#ffffff"))
		vbox.add_child(achievement_title_label)

		achievement_desc_label = Label.new()
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
	achievement_panel.show()

	_achievement_audio.stream = ProceduralAudio.get_mission_passed_stream()
	_achievement_audio.pitch_scale = 1.15
	_achievement_audio.volume_db = -6.0
	_achievement_audio.play()

	_achievement_tween = create_tween()
	_achievement_tween.tween_property(achievement_panel, "modulate:a", 1.0, 0.25)
	_achievement_tween.tween_interval(3.4)
	_achievement_tween.tween_property(achievement_panel, "modulate:a", 0.0, 0.6)
	_achievement_tween.tween_callback(achievement_panel.hide)
