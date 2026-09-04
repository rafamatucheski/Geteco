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
