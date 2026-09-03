class_name WeaponWheel
extends Control

var active_id := "pistol"
var owned := {}
var ammo := {}
var notice := ""
var notice_until := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200

func show_state(next_active: String, next_owned: Dictionary, next_ammo: Dictionary) -> void:
	active_id = next_active
	owned = next_owned.duplicate(true)
	ammo = next_ammo.duplicate(true)

func show_notice(text: String) -> void:
	notice = text
	notice_until = Time.get_ticks_msec() / 1000.0 + 1.2
	queue_redraw()

func _process(_delta: float) -> void:
	if notice_until > 0.0:
		queue_redraw()

func _draw() -> void:
	# Apenas desenha uma notificação sutil e discreta no rodapé se houver aviso (ex: SEM MUNIÇÃO)
	var now := Time.get_ticks_msec() / 1000.0
	if now < notice_until and not notice.is_empty():
		var rect := Rect2(size.x * 0.5 - 120.0, size.y - 60.0, 240.0, 28.0)
		draw_rect(rect, Color(0.05, 0.05, 0.05, 0.75), true)
		draw_rect(rect, Color("f4d35e"), false, 1.5)
		var default_font := ThemeDB.fallback_font
		draw_string(default_font, rect.position + Vector2(0, 19), notice, HORIZONTAL_ALIGNMENT_CENTER, 240, 14, Color.WHITE)
