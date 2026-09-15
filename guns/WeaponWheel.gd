class_name WeaponWheel
extends Control

var active_id := "pistol"
var owned := {}
var ammo := {}
var notice := ""
var notice_until := 0.0
var _notice_panel: PanelContainer
var _notice_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	_notice_panel = PanelContainer.new()
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	style.border_color = Color("f4d35e")
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_notice_panel.add_theme_stylebox_override("panel", style)
	add_child(_notice_panel)
	_notice_label = Label.new()
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 14)
	_notice_label.add_theme_color_override("font_color", Color.WHITE)
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.add_child(_notice_label)
	_notice_panel.hide()
	set_process(false)

func show_state(next_active: String, next_owned: Dictionary, next_ammo: Dictionary) -> void:
	active_id = next_active
	owned = next_owned.duplicate(true)
	ammo = next_ammo.duplicate(true)

func show_notice(text: String) -> void:
	notice = text
	notice_until = Time.get_ticks_msec() / 1000.0 + clampf(text.length() * 0.05, 1.2, 4.5)
	if is_instance_valid(_notice_label): _notice_label.text = text
	set_process(true)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_notice_panel.visible = now < notice_until and not notice.is_empty()
	if not _notice_panel.visible:
		set_process(false)
		return
	var text_width := ThemeDB.fallback_font.get_string_size(notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
	var width := minf(maxf(240.0, text_width), maxf(160.0, size.x - 48.0))
	_notice_label.custom_minimum_size.x = width - 24.0
	_notice_panel.size = Vector2(width, _notice_label.get_minimum_size().y + 16.0)
	_notice_panel.position = Vector2((size.x-width)*0.5, size.y-_notice_panel.size.y-24.0)
