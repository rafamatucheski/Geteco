extends Control
## Resolution-independent first identity proposal; no bitmap dependencies.
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("080d13"))
	var city := elapsed >= 3.7
	var age := elapsed - 3.7 if city else elapsed
	var duration := 2.8 if city else 3.7
	var alpha := clampf(age / 0.65, 0.0, 1.0) * clampf((duration - age) / 0.65, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var scale_factor := minf(size.x / 1280.0, size.y / 720.0)
	var title := "HARBOR" if city else "RCM"
	var subtitle := "Uma nova cidade. Um assunto inacabado." if city else "S T U D I O S"
	var title_size := maxi(20, int((54 if city else 108) * scale_factor))
	var small := maxi(12, int(20 * scale_factor))
	var center := size * 0.5
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	draw_string(font, center + Vector2(-width / 2, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.94, 0.95, 0.96, alpha))
	width = font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, center + Vector2(-width / 2, 45 * scale_factor), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.65, 0.74, 0.79, alpha))
	if not city:
		var reveal := clampf(age / 1.6, 0.0, 1.0)
		draw_line(center + Vector2(-115, 15) * scale_factor, center + Vector2(-115 + 230 * reveal, 15) * scale_factor, Color(0.55, 0.76, 0.8, alpha), 2.0 * scale_factor, true)
