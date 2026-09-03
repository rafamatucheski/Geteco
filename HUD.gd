extends CanvasLayer

@onready var money_label: Label = $RootMargin/TopRightPanel/Money
@onready var stars_label: Label = $RootMargin/TopRightPanel/Stars
@onready var health_bar: ProgressBar = $RootMargin/TopLeftPanel/HealthRow/HealthBar
@onready var armor_bar: ProgressBar = $RootMargin/TopLeftPanel/ArmorRow/ArmorBar
@onready var weapon_icon: WeaponIcon3D = $RootMargin/TopLeftPanel/WeaponRow/WeaponIcon
@onready var ammo_label: Label = $RootMargin/TopLeftPanel/WeaponRow/AmmoLabel

var current_money: int = 0
var current_stars: int = 0

func _ready() -> void:
	add_to_group("hud")
	update_money(0)
	update_stars(0)
	_style_bar(health_bar, Color("2ed573"))
	_style_bar(armor_bar, Color("1e90ff"))

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
		ammo_label.text = "%d / %d" % [int(ammo.get("clip", 0)), int(ammo.get("reserve", 0))]
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
