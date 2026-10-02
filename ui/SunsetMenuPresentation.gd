extends Control
## Static presentation; MainMenu owns save routing, settings and scene changes.
const STYLE := preload("res://ui/GameStyle.gd")
const DISPLAY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
var buttons: Array[Button] = []
var background: ColorRect
var brand_accent: ColorRect
var resume_label: Label
var source_menu: Control

func install(menu: Control) -> void:
	source_menu = menu
	name = "SunsetPresentation"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.get_node("Background").hide()
	menu.get_node("CitySilhouette").hide()
	menu.get_node("MainLayout").hide()
	background = ColorRect.new()
	background.name = "StaticBackground"
	background.color = Color("101216")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	menu.game_title.reparent(self)
	menu.game_title.add_theme_font_override("font", DISPLAY_FONT)
	menu.game_title.add_theme_color_override("font_color", STYLE.TEXT)
	menu.game_title.add_theme_constant_override("outline_size", 0)
	menu.game_title.add_theme_constant_override("shadow_offset_y", 0)
	menu.sub_title.hide()
	brand_accent = ColorRect.new()
	brand_accent.color = STYLE.ACCENT
	brand_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand_accent)
	buttons.assign([menu.btn_new_game, menu.btn_load_game, menu.btn_import, menu.btn_settings, menu.btn_quit])
	if menu.btn_continue.visible: buttons.push_front(menu.btn_continue)
	for button in buttons:
		button.reparent(self)
		button.custom_minimum_size = Vector2.ZERO
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override("font", DISPLAY_FONT)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		normal.content_margin_left = 14
		var active := normal.duplicate() as StyleBoxFlat
		active.bg_color = Color(STYLE.ACCENT, .10)
		active.border_width_left = 2
		active.border_color = STYLE.ACCENT
		var pressed := active.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(STYLE.ACCENT, .18)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", active)
		button.add_theme_stylebox_override("focus", active)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_color", STYLE.TEXT)
		button.add_theme_color_override("font_hover_color", STYLE.ACCENT)
		button.add_theme_color_override("font_focus_color", STYLE.ACCENT)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
	if not menu.latest_save.is_empty():
		resume_label = Label.new()
		resume_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		resume_label.add_theme_font_override("font", BODY_FONT)
		resume_label.add_theme_color_override("font_color", STYLE.MUTED)
		resume_label.text = str(menu.latest_save.get("label", ""))
		add_child(resume_label)
	resized.connect(arrange)
	arrange()
	# Only opacity changes. The opaque backdrop always covers the warming world.
	var intro := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for child in get_children():
		if child == background: continue
		child.modulate.a = 0.0
		intro.tween_property(child, "modulate:a", 1.0, .45)

func arrange() -> void:
	var left := size.x * .12
	source_menu.game_title.position = Vector2(left, size.y * .13)
	source_menu.game_title.size = Vector2(size.x * .55, size.y * .13)
	source_menu.game_title.add_theme_font_size_override("font_size", maxi(42, int(size.y * .10)))
	brand_accent.position = Vector2(left + 4, size.y * .28)
	brand_accent.size = Vector2(44, 2)
	var menu_top := size.y * .35
	for i in buttons.size():
		var button := buttons[i]
		button.position = Vector2(left - 10, menu_top + size.y * i * .066)
		button.size = Vector2(minf(420, size.x * .72), size.y * .058)
		button.add_theme_font_size_override("font_size", maxi(15, int(size.y * .027)))
	if resume_label != null:
		resume_label.position = Vector2(left + 4, menu_top + size.y * (buttons.size() * .066 + .018))
		resume_label.size = Vector2(minf(420, size.x * .72), size.y * .09)
		resume_label.add_theme_font_size_override("font_size", maxi(13, int(size.y * .019)))

func play_start_transition() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 0.0, .35)
	await tween.finished
